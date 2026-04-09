import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'client_identity_default.dart'
    if (dart.library.html) 'client_identity_browser.dart'
    as client_identity;
import 'frontend_error_reporter.dart';
import 'frontend_runtime_info.dart';
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
  Map<String, Object?>? _desiredLiveView;

  void _log(String kind, String message, {Map<String, Object?>? details}) {
    logFrontendDiagnostic(
      'websocket_$kind',
      message,
      details: {
        'base_url': baseurl,
        'has_connected': _hasConnected,
        'desired_room_count': _desiredRoomSubscriptions.length,
        'active_room_count': _activeRoomSubscriptions.length,
        ...?details,
      },
    );
  }

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
      clientSessionId: getOrCreateClientSessionId(),
    );
    _log(
      'connect_started',
      'Starting websocket connection.',
      details: {'uri': wsUri.toString()},
    );

    late final WebSocketChannel channel;
    try {
      channel = _connector(wsUri, headers: await _buildHeaders());
      await channel.ready;
    } catch (error) {
      if (_isUnauthorizedWebSocketError(error)) {
        _log(
          'connect_unauthorized',
          'Websocket connection was unauthorized.',
          details: {'error': error.toString()},
        );
        _handleUnauthorizedDisconnect();
        return;
      }
      _log(
        'connect_failed',
        'Websocket connection failed.',
        details: {'error': error.toString()},
      );
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
    _log(
      event,
      event == 'connected'
          ? 'Websocket connection established.'
          : 'Websocket connection re-established.',
    );
    _connectionController.add(event);
  }

  void _handleEvent(dynamic rawEvent) {
    Map<String, dynamic> event;
    try {
      event = jsonDecode(rawEvent) as Map<String, dynamic>;
    } catch (_) {
      _log(
        'event_parse_failed',
        'Dropped a websocket event because it was not valid JSON.',
      );
      return;
    }

    final type = event['type'];
    final data = event['data'];
    if (type == 'subscribed-room' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      if (roomId != null) {
        _activeRoomSubscriptions.add(roomId);
        _pendingSubscriptions.remove(roomId)?.complete();
        _log(
          'subscribed_room',
          'Websocket room subscription confirmed.',
          details: {'room_id': roomId},
        );
      }
    } else if (type == 'unsubscribed-room' && data is Map<String, dynamic>) {
      final roomId = _roomIdFromData(data);
      if (roomId != null) {
        _activeRoomSubscriptions.remove(roomId);
        _log(
          'unsubscribed_room',
          'Websocket room subscription removed.',
          details: {'room_id': roomId},
        );
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
      _log(
        'server_error',
        'Received a websocket error event from the server.',
        details: {'code': code, 'room_id': roomId},
      );
    } else if (type == 'signout') {
      _desiredRoomSubscriptions.clear();
      _activeRoomSubscriptions.clear();
      _shouldReconnect = false;
      _cancelReconnectTimer();
      unawaited(_closeCurrentConnection());
      _connectionController.add('signed-out');
      _log('signed_out', 'Websocket session was signed out by the server.');
    } else if (type != 'new-messages') {
      _log(
        'event_received',
        'Received a websocket event.',
        details: {
          'type': '$type',
          'room_id': data is Map<String, dynamic>
              ? _roomIdFromData(data)
              : null,
        },
      );
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
    _log(
      'disconnected',
      'Websocket connection closed.',
      details: {'should_reconnect': _shouldReconnect},
    );
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
    _log('unauthorized_disconnect', 'Websocket session became unauthorized.');
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
    _log(
      'reconnect_scheduled',
      'Scheduled a websocket reconnect attempt.',
      details: {'delay_ms': delay.inMilliseconds},
    );
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
      await _syncLiveView();
      return;
    }
    for (final roomId in _desiredRoomSubscriptions.toList()..sort()) {
      try {
        await _subscribeToRoom(roomId, swallowRoomUnavailable: true);
      } on RoomUnavailable {
        continue;
      }
    }
    await _syncLiveView();
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
    _log(
      'room_unavailable',
      'Websocket room became unavailable.',
      details: {'room_id': roomId, 'code': code},
    );
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
    _log(
      'subscribe_requested',
      'Requested a websocket room subscription.',
      details: {'room_id': roomId},
    );
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
      _log(
        'subscribe_timed_out',
        'Timed out waiting for websocket room subscription.',
        details: {'room_id': roomId},
      );
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

  Stream<Map<String, dynamic>> roomRequestsChangedStream(roomId) =>
      eventsStream(
        'room-requests-changed',
      ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> typingStateStream(roomId) => eventsStream(
    'typing-state',
  ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomReadStream(roomId) => eventsStream(
    'room-read',
  ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> roomDeliveredStream(roomId) => eventsStream(
    'room-delivered',
  ).where((event) => event['data']['room_id'] == roomId);

  Stream<Map<String, dynamic>> sharedRoomUpdatedStream(roomId) => eventsStream(
    'shared-room-updated',
  ).where((event) => event['data']['room_id'] == roomId);

  Future<void> ensureConnected() async {
    if (_websocket == null) {
      _shouldReconnect = true;
      await _startConnect();
    }
  }

  void updateLiveViewForRoute(String? routeName) {
    final nextLiveView = _liveViewForRoute(routeName);
    if (_sameLiveView(_desiredLiveView, nextLiveView)) {
      return;
    }
    _desiredLiveView = nextLiveView;
    _log(
      'live_view_changed',
      'Updated desired live view from navigation.',
      details: {'route': routeName, 'live_view': nextLiveView},
    );
    unawaited(_syncLiveView());
  }

  Future<void> _syncLiveView() async {
    final websocket = _websocket;
    if (websocket == null) {
      return;
    }
    websocket.sink.add(
      jsonEncode({
        'type': 'set-live-view',
        'data': _desiredLiveView ?? const {'view': 'none'},
      }),
    );
  }

  Map<String, Object?>? _liveViewForRoute(String? routeName) {
    if (routeName == null || routeName.isEmpty) {
      return null;
    }
    final uri = Uri.parse(routeName);
    if (uri.path == '/nearby') {
      return const {'view': 'nearby'};
    }
    if (uri.path == '/rooms') {
      final roomId = int.tryParse(uri.queryParameters['open_room'] ?? '');
      if (roomId != null) {
        return {'view': 'room', 'room_id': roomId};
      }
      return const {'view': 'rooms'};
    }
    return null;
  }

  bool _sameLiveView(Map<String, Object?>? left, Map<String, Object?>? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left['view'] == right['view'] && left['room_id'] == right['room_id'];
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
    _log(
      'unsubscribe_requested',
      'Requested a websocket room unsubscription.',
      details: {'room_id': normalizedRoomId},
    );
    _websocket!.sink.add(
      jsonEncode({
        'type': 'unsubscribe-room',
        'data': {'room_id': normalizedRoomId},
      }),
    );
  }

  Future<void> sendTypingState(roomId, {required bool isTyping}) async {
    final normalizedRoomId = _roomIdFromData({'room_id': roomId});
    if (normalizedRoomId == null) {
      throw ArgumentError.value(roomId, 'roomId', 'roomId must be an integer');
    }
    await send({
      'type': 'typing-state',
      'data': {'room_id': normalizedRoomId, 'is_typing': isTyping},
    });
  }

  Future<void> close() async {
    _shouldReconnect = false;
    _desiredRoomSubscriptions.clear();
    _desiredLiveView = null;
    _cancelReconnectTimer();
    _connectTask = null;
    await _closeCurrentConnection();
  }
}

class LiveViewNavigatorObserver extends NavigatorObserver {
  LiveViewNavigatorObserver(this.websocketService);

  final WebsocketService websocketService;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    websocketService.updateLiveViewForRoute(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    websocketService.updateLiveViewForRoute(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    websocketService.updateLiveViewForRoute(previousRoute?.settings.name);
    super.didPop(route, previousRoute);
  }
}
