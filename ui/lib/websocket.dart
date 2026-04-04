import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'client_identity_default.dart'
    if (dart.library.html) 'client_identity_browser.dart'
    as client_identity;
import 'http_client_default.dart'
    if (dart.library.html) 'http_client_browser.dart'
    as session_http;
import 'ws_channel_default.dart'
    if (dart.library.html) 'ws_channel_browser.dart';

typedef WebSocketConnector =
    WebSocketChannel Function(Uri uri, {Map<String, dynamic>? headers});

class RoomUnavailable implements Exception {
  final int roomId;
  final String code;

  RoomUnavailable(this.roomId, {this.code = 'room-unavailable'});

  @override
  String toString() => 'RoomUnavailable(roomId: $roomId, code: $code)';
}

class WebsocketService {
  WebsocketService({
    String? baseurl,
    WebSocketConnector? connector,
    Duration reconnectDelay = const Duration(seconds: 1),
    Duration maxReconnectDelay = const Duration(seconds: 30),
    Duration subscriptionTimeout = const Duration(seconds: 5),
  }) : baseurl = baseurl ?? Environment().config.apiUrl,
       _connector = connector ?? connectWsChannel,
       _initialReconnectDelay = reconnectDelay,
       _maxReconnectDelay = maxReconnectDelay,
       _subscriptionTimeout = subscriptionTimeout,
       _nextReconnectDelay = reconnectDelay;

  final String baseurl;
  final WebSocketConnector _connector;
  final Duration _initialReconnectDelay;
  final Duration _maxReconnectDelay;
  final Duration _subscriptionTimeout;

  WebSocketChannel? _websocket;
  StreamSubscription? _subscription;
  final StreamController<Map<String, dynamic>> _streamController =
      StreamController.broadcast();
  final StreamController<String> _connectionController =
      StreamController.broadcast();
  Future<void>? _connectTask;
  Timer? _reconnectTimer;
  Duration _nextReconnectDelay;
  bool _shouldReconnect = false;
  bool _hasConnected = false;
  final Set<int> _desiredRoomSubscriptions = <int>{};
  final Set<int> _activeRoomSubscriptions = <int>{};
  final Map<int, Completer<void>> _pendingSubscriptions = {};

  Future<Map<String, dynamic>?> _buildHeaders() async {
    final sessionCookie = await session_http.readSessionCookie();
    if (sessionCookie == null || sessionCookie.isEmpty) {
      return null;
    }
    return {'Cookie': sessionCookie};
  }

  Future<void> reconnect() async {
    _shouldReconnect = true;
    _cancelReconnectTimer();
    await _startConnect(forceReconnect: true);
  }

  Future<void> _startConnect({bool forceReconnect = false}) async {
    if (_connectTask != null) {
      return _connectTask!;
    }
    final task = _connect(forceReconnect: forceReconnect);
    _connectTask = task;
    try {
      await task;
    } catch (error) {
      _scheduleReconnectIfNeeded();
      rethrow;
    } finally {
      if (identical(_connectTask, task)) {
        _connectTask = null;
      }
    }
  }

  Future<void> _connect({required bool forceReconnect}) async {
    _cancelReconnectTimer();
    if (forceReconnect) {
      await _closeCurrentConnection();
    } else if (_websocket != null) {
      return;
    }

    final wsUri = createWebSocketUri(
      baseurl,
      clientId: await client_identity.readClientIdentity(),
    );

    late final WebSocketChannel channel;
    try {
      channel = _connector(wsUri, headers: await _buildHeaders());
      await channel.ready;
    } catch (error) {
      if (_isUnauthorizedWebSocketError(error)) {
        _handleUnauthorizedDisconnect();
        return;
      }
      _scheduleReconnectIfNeeded();
      rethrow;
    }
    _websocket = channel;
    _subscription = channel.stream.listen(
      _handleEvent,
      onError: (error, stackTrace) {
        _streamController.addError(error, stackTrace);
        _handleDisconnect(channel);
      },
      onDone: () {
        _handleDisconnect(channel);
      },
    );
    _nextReconnectDelay = _initialReconnectDelay;
    try {
      await _restoreSubscriptions();
    } catch (_) {
      await _closeCurrentConnection();
      _scheduleReconnectIfNeeded();
      rethrow;
    }
    final event = _hasConnected ? 'reconnected' : 'connected';
    _hasConnected = true;
    _connectionController.add(event);
  }

  void _handleEvent(dynamic rawEvent) {
    Map<String, dynamic> event;
    try {
      event = jsonDecode(rawEvent) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = event['type'];
    final data = event['data'];
    if (type == 'subscribed-room' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      if (roomId != null) {
        _activeRoomSubscriptions.add(roomId);
        _pendingSubscriptions.remove(roomId)?.complete();
      }
    } else if (type == 'unsubscribed-room' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      if (roomId != null) {
        _activeRoomSubscriptions.remove(roomId);
      }
    } else if (type == 'room-deleted' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      if (roomId != null) {
        _handleRoomUnavailable(roomId, code: 'room-deleted');
      }
    } else if (type == 'error' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      final code = '${data['code']}';
      if (code == 'room-access-denied' && roomId != null) {
        _handleRoomUnavailable(roomId, code: code, emitRoomDeleted: true);
      }
    } else if (type == 'signout') {
      _desiredRoomSubscriptions.clear();
      _activeRoomSubscriptions.clear();
      _shouldReconnect = false;
      _cancelReconnectTimer();
      unawaited(_closeCurrentConnection());
      _connectionController.add('signed-out');
    }
    _streamController.add(event);
  }

  void _handleDisconnect(WebSocketChannel channel) {
    if (!identical(_websocket, channel)) {
      return;
    }
    _websocket = null;
    _subscription = null;
    _activeRoomSubscriptions.clear();
    _failPendingSubscriptions(StateError('WebSocket disconnected'));
    _connectionController.add('disconnected');
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  bool _isUnauthorizedWebSocketError(Object error) {
    return '$error'.contains('HTTP status code: 401');
  }

  void _handleUnauthorizedDisconnect() {
    _shouldReconnect = false;
    _cancelReconnectTimer();
    _desiredRoomSubscriptions.clear();
    _activeRoomSubscriptions.clear();
    _failPendingSubscriptions(StateError('WebSocket unauthorized'));
    _connectionController.add('signed-out');
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) {
      return;
    }
    final delay = _nextReconnectDelay;
    final nextDelayMs = (_nextReconnectDelay.inMilliseconds * 2).clamp(
      _initialReconnectDelay.inMilliseconds,
      _maxReconnectDelay.inMilliseconds,
    );
    _nextReconnectDelay = Duration(milliseconds: nextDelayMs.toInt());
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_shouldReconnect && _websocket == null) {
        unawaited(_runScheduledReconnect());
      }
    });
  }

  void _scheduleReconnectIfNeeded() {
    if (_shouldReconnect && _websocket == null) {
      _scheduleReconnect();
    }
  }

  Future<void> _runScheduledReconnect() async {
    try {
      await _startConnect();
    } catch (_) {
      // The reconnect loop is intentionally persistent; failures are retried.
    }
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _restoreSubscriptions() async {
    _activeRoomSubscriptions.clear();
    if (_desiredRoomSubscriptions.isEmpty || _websocket == null) {
      return;
    }
    for (final roomId in _desiredRoomSubscriptions.toList()..sort()) {
      try {
        await _subscribeToRoom(roomId, swallowRoomUnavailable: true);
      } on RoomUnavailable {
        continue;
      }
    }
  }

  void _failPendingSubscriptions(Object error) {
    final waiters = _pendingSubscriptions.values.toList();
    _pendingSubscriptions.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }

  int? _roomIdFromData(Map<String, dynamic> data) {
    final value = data['room_id'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }

  void _handleRoomUnavailable(
    int roomId, {
    required String code,
    bool emitRoomDeleted = false,
  }) {
    _desiredRoomSubscriptions.remove(roomId);
    _activeRoomSubscriptions.remove(roomId);
    final waiter = _pendingSubscriptions.remove(roomId);
    final error = RoomUnavailable(roomId, code: code);
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(error);
    }
    if (emitRoomDeleted) {
      _streamController.add({
        'type': 'room-deleted',
        'data': {'room_id': roomId},
      });
    }
  }

  Future<void> _subscribeToRoom(
    int roomId, {
    bool swallowRoomUnavailable = false,
  }) async {
    final existingWaiter = _pendingSubscriptions[roomId];
    if (existingWaiter != null) {
      try {
        await existingWaiter.future.timeout(_subscriptionTimeout);
      } on RoomUnavailable {
        if (!swallowRoomUnavailable) {
          rethrow;
        }
      }
      return;
    }

    final completer = Completer<void>();
    _pendingSubscriptions[roomId] = completer;
    _websocket!.sink.add(
      jsonEncode({
        'type': 'subscribe-room',
        'data': {'room_id': roomId},
      }),
    );

    try {
      await completer.future.timeout(_subscriptionTimeout);
    } on RoomUnavailable {
      if (!swallowRoomUnavailable) {
        rethrow;
      }
    } on TimeoutException {
      _pendingSubscriptions.remove(roomId);
      rethrow;
    }
  }

  Future<void> _closeCurrentConnection() async {
    final subscription = _subscription;
    final websocket = _websocket;
    _subscription = null;
    _websocket = null;
    _activeRoomSubscriptions.clear();
    _failPendingSubscriptions(StateError('WebSocket disconnected'));
    await subscription?.cancel();
    await websocket?.sink.close();
  }

  Stream<Map<String, dynamic>> get stream => _streamController.stream;
  Stream<String> get connectionEvents => _connectionController.stream;

  Stream<Map<String, dynamic>> eventsStream(String type) =>
      stream.where((event) => event['type'] == type);

  Stream<Map<String, dynamic>> messagesStream(roomId) => eventsStream(
    'new-messages',
  ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomDeletedStream(roomId) => eventsStream(
    'room-deleted',
  ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomsChangedStream() =>
      eventsStream('rooms-changed');

  Stream<Map<String, dynamic>> nearbyChangedStream() =>
      eventsStream('nearby-changed');

  Stream<Map<String, dynamic>> roomRequestsChangedStream(roomId) => eventsStream(
    'room-requests-changed',
  ).where((event) => event['data']['room_id'] == roomId);

  Future<void> ensureConnected() async {
    if (_websocket == null) {
      _shouldReconnect = true;
      await _startConnect();
    }
  }

  Future<void> send(payload) async {
    await ensureConnected();
    _websocket!.sink.add(jsonEncode(payload));
  }

  Future<void> subscribeRoom(roomId) async {
    final normalizedRoomId = _roomIdFromData({'room_id': roomId});
    if (normalizedRoomId == null) {
      throw ArgumentError.value(roomId, 'roomId', 'roomId must be an integer');
    }
    _desiredRoomSubscriptions.add(normalizedRoomId);
    await ensureConnected();
    if (_activeRoomSubscriptions.contains(normalizedRoomId)) {
      return;
    }
    await _subscribeToRoom(normalizedRoomId);
  }

  Future<void> unsubscribeRoom(roomId) async {
    final normalizedRoomId = _roomIdFromData({'room_id': roomId});
    if (normalizedRoomId == null) {
      return;
    }
    _desiredRoomSubscriptions.remove(normalizedRoomId);
    _activeRoomSubscriptions.remove(normalizedRoomId);
    final waiter = _pendingSubscriptions.remove(normalizedRoomId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Subscription cancelled'));
    }
    if (_websocket == null) {
      return;
    }
    _websocket!.sink.add(
      jsonEncode({
        'type': 'unsubscribe-room',
        'data': {'room_id': normalizedRoomId},
      }),
    );
  }

  Future<void> close() async {
    _shouldReconnect = false;
    _desiredRoomSubscriptions.clear();
    _cancelReconnectTimer();
    _connectTask = null;
    await _closeCurrentConnection();
  }
}
