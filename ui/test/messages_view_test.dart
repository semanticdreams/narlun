import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/leave_room_notice.dart';
import 'package:narlun/leave_room_notice_storage.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/messages_view.dart';
import 'package:narlun/models.dart';
import 'package:narlun/push_notifications_service.dart';
import 'package:narlun/room_details_view.dart';
import 'package:narlun/room_messages_cache.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class FakeHttpService extends HttpService {
  FakeHttpService({required WebsocketService websocketService})
    : super(
        websocketService: websocketService,
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  final Queue<Future<List<ChatMessage>> Function(int roomId)> _messageHandlers =
      Queue<Future<List<ChatMessage>> Function(int roomId)>();
  final Queue<Future<List<RoomSummary>> Function()> _roomHandlers =
      Queue<Future<List<RoomSummary>> Function()>();
  final Queue<
    Future<RoomSummary> Function(int roomId, bool? pushMuted, String? name)
  >
  _roomSettingsHandlers =
      Queue<
        Future<RoomSummary> Function(int roomId, bool? pushMuted, String? name)
      >();
  final Queue<Future<List<RoomJoinRequest>> Function(int roomId)>
  _roomRequestHandlers =
      Queue<Future<List<RoomJoinRequest>> Function(int roomId)>();
  final Queue<Future<void> Function(int roomId)> _leaveRoomHandlers =
      Queue<Future<void> Function(int roomId)>();
  final Queue<Future<ChatMessage> Function(int roomId, String body)>
  _sendMessageHandlers =
      Queue<Future<ChatMessage> Function(int roomId, String body)>();
  var getMessagesCalls = 0;
  var getRoomsCalls = 0;
  var getRoomRequestsCalls = 0;
  var clearedLocalSession = false;
  final updatedRoomSettings = <Map<String, dynamic>>[];
  final approvedRoomRequests = <Map<String, dynamic>>[];
  final rejectedRoomRequests = <Map<String, dynamic>>[];
  final leftRooms = <int>[];
  final sentMessages = <Map<String, dynamic>>[];
  final markedDeliveries = <Map<String, dynamic>>[];
  final markedReads = <Map<String, dynamic>>[];

  void enqueueMessages(Future<List<ChatMessage>> Function(int roomId) handler) {
    _messageHandlers.add(handler);
  }

  void enqueueRooms(Future<List<RoomSummary>> Function() handler) {
    _roomHandlers.add(handler);
  }

  void enqueueRoomSettings(
    Future<RoomSummary> Function(int roomId, bool? pushMuted, String? name)
    handler,
  ) {
    _roomSettingsHandlers.add(handler);
  }

  void enqueueRoomRequests(
    Future<List<RoomJoinRequest>> Function(int roomId) handler,
  ) {
    _roomRequestHandlers.add(handler);
  }

  void enqueueLeaveRoom(Future<void> Function(int roomId) handler) {
    _leaveRoomHandlers.add(handler);
  }

  void enqueueSendMessage(
    Future<ChatMessage> Function(int roomId, String body) handler,
  ) {
    _sendMessageHandlers.add(handler);
  }

  @override
  Future<List<ChatMessage>> get_messages(
    room_id, {
    bool silentErrors = false,
  }) async {
    getMessagesCalls += 1;
    return _messageHandlers.removeFirst()(room_id as int);
  }

  @override
  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) async {
    getRoomsCalls += 1;
    if (_roomHandlers.isEmpty) {
      return [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ];
    }
    return _roomHandlers.removeFirst()();
  }

  @override
  Future<void> clearLocalSession() async {
    clearedLocalSession = true;
  }

  @override
  Future<RoomSummary> update_room_settings(
    room_id, {
    bool? pushMuted,
    String? name,
  }) async {
    updatedRoomSettings.add({
      'room_id': room_id,
      if (pushMuted != null) 'push_muted': pushMuted,
      if (name != null) 'name': name,
    });
    if (_roomSettingsHandlers.isNotEmpty) {
      return _roomSettingsHandlers.removeFirst()(
        room_id as int,
        pushMuted,
        name,
      );
    }
    return RoomSummary(
      id: room_id as int,
      name: name,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'other'),
      ],
      pushMuted: pushMuted ?? false,
    );
  }

  @override
  Future<List<RoomJoinRequest>> get_room_requests(
    room_id, {
    bool silentErrors = false,
  }) async {
    getRoomRequestsCalls += 1;
    if (_roomRequestHandlers.isEmpty) {
      return const [];
    }
    return _roomRequestHandlers.removeFirst()(room_id as int);
  }

  @override
  Future<RoomSummary> approve_room_request(room_id, user_id) async {
    approvedRoomRequests.add({'room_id': room_id, 'user_id': user_id});
    return RoomSummary(
      id: room_id as int,
      name: 'Updated room',
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: [
        const RoomParticipant(id: 1, username: 'me'),
        const RoomParticipant(id: 2, username: 'other'),
        RoomParticipant(id: user_id as int, username: 'requester'),
      ],
    );
  }

  @override
  Future<void> reject_room_request(room_id, user_id) async {
    rejectedRoomRequests.add({'room_id': room_id, 'user_id': user_id});
  }

  @override
  Future<void> leave_room(room_id) async {
    leftRooms.add(room_id as int);
    if (_leaveRoomHandlers.isNotEmpty) {
      await _leaveRoomHandlers.removeFirst()(room_id);
    }
  }

  @override
  Future<ChatMessage> send_message(
    room_id,
    message_body, {
    ChatMessageKind kind = ChatMessageKind.text,
    String? whatsappInviteUrl,
  }) async {
    sentMessages.add({
      'room_id': room_id,
      'body': message_body,
      'kind': chatMessageKindToJson(kind),
      if (whatsappInviteUrl != null) 'whatsapp_invite_url': whatsappInviteUrl,
    });
    if (_sendMessageHandlers.isNotEmpty) {
      return _sendMessageHandlers.removeFirst()(
        room_id as int,
        message_body as String,
      );
    }
    return ChatMessage(
      id: 'local-${sentMessages.length}',
      body: message_body as String,
      senderId: 1,
      senderUsername: 'me',
      timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
      readByUsers: const [RoomParticipant(id: 1, username: 'me')],
    );
  }

  @override
  Future<void> mark_room_read(
    room_id, {
    String? messageId,
    bool silentErrors = true,
  }) async {
    markedReads.add({
      'room_id': room_id,
      'message_id': messageId,
      'silent_errors': silentErrors,
    });
  }

  @override
  Future<void> mark_room_delivered(
    room_id, {
    String? messageId,
    bool silentErrors = true,
  }) async {
    markedDeliveries.add({
      'room_id': room_id,
      'message_id': messageId,
      'silent_errors': silentErrors,
    });
  }
}

class FakeWebsocketService extends WebsocketService {
  FakeWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );

  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomRequestsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomDeliveredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomReadController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();
  final subscribedRooms = <int>[];
  final unsubscribedRooms = <int>[];
  final typingStates = <Map<String, dynamic>>[];
  var ensureConnectedCalls = 0;
  Object? subscribeError;

  @override
  Future<void> ensureConnected() async {
    ensureConnectedCalls += 1;
  }

  @override
  Future<void> subscribeRoom(roomId) async {
    if (subscribeError != null) {
      throw subscribeError!;
    }
    subscribedRooms.add(roomId as int);
  }

  @override
  Future<void> unsubscribeRoom(roomId) async {
    unsubscribedRooms.add(roomId as int);
  }

  @override
  Stream<Map<String, dynamic>> messagesStream(roomId) => _messagesController
      .stream
      .where((event) => event['data']['room_id'] == roomId);

  @override
  Stream<Map<String, dynamic>> roomDeletedStream(roomId) =>
      _roomDeletedController.stream.where(
        (event) => event['data']['room_id'] == roomId,
      );

  @override
  Stream<Map<String, dynamic>> roomsChangedStream() =>
      _roomsChangedController.stream;

  @override
  Stream<Map<String, dynamic>> roomRequestsChangedStream(roomId) =>
      _roomRequestsChangedController.stream.where(
        (event) => event['data']['room_id'] == roomId,
      );

  @override
  Stream<Map<String, dynamic>> typingStateStream(roomId) =>
      _typingStateController.stream.where(
        (event) => event['data']['room_id'] == roomId,
      );

  @override
  Stream<Map<String, dynamic>> roomDeliveredStream(roomId) =>
      _roomDeliveredController.stream.where(
        (event) => event['data']['room_id'] == roomId,
      );

  @override
  Stream<Map<String, dynamic>> roomReadStream(roomId) => _roomReadController
      .stream
      .where((event) => event['data']['room_id'] == roomId);

  @override
  Stream<String> get connectionEvents => _connectionController.stream;

  @override
  Future<void> sendTypingState(roomId, {required bool isTyping}) async {
    typingStates.add({'room_id': roomId, 'is_typing': isTyping});
  }

  void emitMessage(int roomId, List<dynamic> messages) {
    _messagesController.add({
      'type': 'new-messages',
      'data': {'room_id': roomId, 'messages': messages},
    });
  }

  void emitRoomDeleted(int roomId) {
    _roomDeletedController.add({
      'type': 'room-deleted',
      'data': {'room_id': roomId},
    });
  }

  void emitConnection(String event) {
    _connectionController.add(event);
  }

  void emitRoomsChanged() {
    _roomsChangedController.add({'type': 'rooms-changed', 'data': {}});
  }

  void emitRoomRequestsChanged(int roomId) {
    _roomRequestsChangedController.add({
      'type': 'room-requests-changed',
      'data': {'room_id': roomId},
    });
  }

  void emitTypingState({
    required int roomId,
    required int userId,
    required bool isTyping,
    String username = 'Someone',
  }) {
    _typingStateController.add({
      'type': 'typing-state',
      'data': {
        'room_id': roomId,
        'user_id': userId,
        'is_typing': isTyping,
        'user': {'id': userId, 'username': username},
      },
    });
  }

  void emitRoomRead({
    required int roomId,
    required int userId,
    required String messageId,
    String username = 'Someone',
  }) {
    _roomReadController.add({
      'type': 'room-read',
      'data': {
        'room_id': roomId,
        'user_id': userId,
        'message_id': messageId,
        'user': {'id': userId, 'username': username},
      },
    });
  }

  void emitRoomDelivered({
    required int roomId,
    required int userId,
    required String messageId,
    String username = 'Someone',
  }) {
    _roomDeliveredController.add({
      'type': 'room-delivered',
      'data': {
        'room_id': roomId,
        'user_id': userId,
        'message_id': messageId,
        'user': {'id': userId, 'username': username},
      },
    });
  }
}

class FakePushNotificationsService extends PushNotificationsService {
  FakePushNotificationsService({this.prompt = false});

  bool prompt;
  int enableCalls = 0;
  int dismissCalls = 0;

  @override
  bool get isBusy => false;

  @override
  bool get isConfigured => true;

  @override
  bool get isSubscribed => false;

  @override
  bool get isSupported => true;

  @override
  bool get shouldShowPrompt => prompt;

  @override
  PushPermissionState get permissionState => PushPermissionState.defaultState;

  @override
  String? get statusMessage => null;

  @override
  Future<void> disableNotifications() async {}

  @override
  void dismissPrompt() {
    dismissCalls += 1;
    prompt = false;
    notifyListeners();
  }

  @override
  Future<void> enableNotifications() async {
    enableCalls += 1;
  }

  @override
  Future<void> syncSession(SessionUser? user) async {}
}

Widget _buildMessagesApp({
  required FakeHttpService httpService,
  required FakeWebsocketService websocketService,
  RoomSummary? room,
  RoomMessagesCache? roomMessagesCache,
  PushNotificationsService? pushNotificationsService,
  Future<bool> Function(String url)? externalLinkOpener,
  SessionUser me = const SessionUser(
    authenticated: true,
    id: 1,
    username: 'me',
  ),
}) {
  room ??= RoomSummary(
    id: 1,
    updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
    participants: const [
      RoomParticipant(id: 1, username: 'me'),
      RoomParticipant(id: 2, username: 'other'),
    ],
  );
  final content = MessagesView(
    room: room,
    me: me,
    httpService: httpService,
    roomMessagesCache: roomMessagesCache,
    websocketService: websocketService,
    externalLinkOpener: externalLinkOpener,
  );
  final provider = Provider<RoomMessagesCache>.value(
    value: roomMessagesCache ?? RoomMessagesCache(),
    child: ChangeNotifierProvider<PushNotificationsService?>.value(
      value: pushNotificationsService,
      child: content,
    ),
  );
  return MaterialApp(home: provider);
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
    clearLeaveRoomInfoStorageForTests();
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets(
    'merges initial history with live messages received during room setup',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final historyCompleter = Completer<List<ChatMessage>>();
      httpService.enqueueMessages((_) => historyCompleter.future);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pump();

      websocketService.emitMessage(1, [
        {
          'id': 'live-1',
          'body': 'Live message',
          'sender_id': 2,
          'timestamp': '2026-04-04T10:00:01.000Z',
        },
      ]);
      await tester.pump();

      historyCompleter.complete([
        ChatMessage(
          id: 'history-1',
          body: 'History message',
          senderId: 2,
          timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('History message'), findsOneWidget);
      expect(find.text('Live message'), findsOneWidget);
      expect(websocketService.subscribedRooms, [1]);
    },
  );

  testWidgets('shows loading state before the first room history response', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    final historyCompleter = Completer<List<ChatMessage>>();
    httpService.enqueueMessages((_) => historyCompleter.future);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);

    historyCompleter.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('room subtitle shows the full member count', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          name: 'Solo room',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        room: RoomSummary(
          id: 1,
          name: 'Solo room',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 member'), findsOneWidget);
    expect(find.text('Just you'), findsNothing);
    expect(find.text('1 other member'), findsNothing);
  });

  testWidgets('shows a dismissible notification prompt when entering a room', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    final pushNotificationsService = FakePushNotificationsService(prompt: true);
    httpService.enqueueMessages((_) async => const []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        pushNotificationsService: pushNotificationsService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn On Notifications'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(pushNotificationsService.enableCalls, 1);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(pushNotificationsService.dismissCalls, 1);
    expect(find.text('Turn On Notifications'), findsNothing);
  });

  testWidgets('refreshes room history when a new fetch succeeds', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:01.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueMessages(
      (_) async => [
        ChatMessage(
          id: 'after-reconnect',
          body: 'Recovered message',
          senderId: 2,
          timestamp: DateTime.parse('2026-04-04T10:00:02.000Z'),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MessagesView)) as dynamic;
    await state.updateMessages(silentErrors: true);
    await tester.pumpAndSettle();

    expect(find.text('Recovered message'), findsOneWidget);
  });

  testWidgets(
    'revisiting messages keeps cached history visible without refreshing again',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final roomMessagesCache = RoomMessagesCache();
      httpService.enqueueMessages(
        (_) async => [
          ChatMessage(
            id: 'history-1',
            body: 'First history',
            senderId: 2,
            timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
          ),
        ],
      );

      await tester.pumpWidget(
        Provider<RoomMessagesCache>.value(
          value: roomMessagesCache,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MessagesView(
                          room: RoomSummary(
                            id: 1,
                            updatedAt: DateTime.parse(
                              '2026-04-04T10:00:00.000Z',
                            ),
                            participants: const [
                              RoomParticipant(id: 1, username: 'me'),
                              RoomParticipant(id: 2, username: 'other'),
                            ],
                          ),
                          me: const SessionUser(
                            authenticated: true,
                            id: 1,
                            username: 'me',
                          ),
                          httpService: httpService,
                          roomMessagesCache: roomMessagesCache,
                          websocketService: websocketService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open room'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(find.text('First history'), findsOneWidget);
      expect(httpService.getMessagesCalls, 1);

      Navigator.of(tester.element(find.byType(MessagesView))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(find.text('First history'), findsOneWidget);
      expect(find.text('New history'), findsNothing);
      expect(httpService.getMessagesCalls, 1);

      Navigator.of(tester.element(find.byType(MessagesView))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(httpService.getMessagesCalls, 1);
      expect(find.text('First history'), findsOneWidget);
      expect(find.text('New history'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'revisiting an empty room keeps the empty state visible without reloading',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final roomMessagesCache = RoomMessagesCache();
      httpService.enqueueMessages((_) async => const []);

      await tester.pumpWidget(
        Provider<RoomMessagesCache>.value(
          value: roomMessagesCache,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MessagesView(
                          room: RoomSummary(
                            id: 1,
                            updatedAt: DateTime.parse(
                              '2026-04-04T10:00:00.000Z',
                            ),
                            participants: const [
                              RoomParticipant(id: 1, username: 'me'),
                              RoomParticipant(id: 2, username: 'other'),
                            ],
                          ),
                          me: const SessionUser(
                            authenticated: true,
                            id: 1,
                            username: 'me',
                          ),
                          httpService: httpService,
                          roomMessagesCache: roomMessagesCache,
                          websocketService: websocketService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open room'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
      expect(httpService.getMessagesCalls, 1);

      Navigator.of(tester.element(find.byType(MessagesView))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(httpService.getMessagesCalls, 1);
    },
  );

  testWidgets('refreshes the room title when membership changes', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:01.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
            RoomParticipant(id: 3, username: 'charlie'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('other'), findsWidgets);

    websocketService.emitConnection('reconnected');
    await tester.pumpAndSettle();

    expect(find.text('other, charlie'), findsOneWidget);
  });

  testWidgets('pops the room screen when the room is deleted', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MessagesView(
                        room: RoomSummary(
                          id: 1,
                          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
                          participants: const [
                            RoomParticipant(id: 1, username: 'me'),
                            RoomParticipant(id: 2, username: 'other'),
                          ],
                        ),
                        me: const SessionUser(
                          authenticated: true,
                          id: 1,
                          username: 'me',
                        ),
                        httpService: httpService,
                        websocketService: websocketService,
                      ),
                    ),
                  );
                },
                child: const Text('Open room'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open room'));
    await tester.pumpAndSettle();
    expect(find.text('other'), findsOneWidget);

    websocketService.emitRoomDeleted(1);
    await tester.pumpAndSettle();

    expect(find.text('Open room'), findsOneWidget);
    expect(find.text('This room is no longer available.'), findsOneWidget);
    expect(websocketService.unsubscribedRooms, [1]);
  });

  testWidgets(
    'pops the room screen when room subscription is denied during setup',
    (tester) async {
      final websocketService = FakeWebsocketService()
        ..subscribeError = RoomUnavailable(1, code: 'room-access-denied');
      final httpService = FakeHttpService(websocketService: websocketService);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MessagesView(
                          room: RoomSummary(
                            id: 1,
                            updatedAt: DateTime.parse(
                              '2026-04-04T10:00:00.000Z',
                            ),
                            participants: const [
                              RoomParticipant(id: 1, username: 'me'),
                              RoomParticipant(id: 2, username: 'other'),
                            ],
                          ),
                          me: const SessionUser(
                            authenticated: true,
                            id: 1,
                            username: 'me',
                          ),
                          httpService: httpService,
                          websocketService: websocketService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open room'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      expect(find.text('Open room'), findsOneWidget);
      expect(find.text('This room is no longer available.'), findsOneWidget);
      expect(websocketService.subscribedRooms, isEmpty);
      expect(websocketService.unsubscribedRooms, [1]);
    },
  );

  testWidgets('expires the session when room refresh returns unauthorized', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueMessages((_) async => throw UnauthorizedResponse());

    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: httpService,
        child: ChangeNotifierProvider(
          create: (_) => MeModel()
            ..setData(
              const SessionUser(authenticated: true, id: 1, username: 'me'),
            ),
          child: MaterialApp(
            initialRoute: '/room',
            routes: {
              '/': (_) => const Scaffold(body: Text('Welcome landing')),
              '/room': (_) => MessagesView(
                room: RoomSummary(
                  id: 1,
                  updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
                  participants: const [
                    RoomParticipant(id: 1, username: 'me'),
                    RoomParticipant(id: 2, username: 'other'),
                  ],
                ),
                me: const SessionUser(
                  authenticated: true,
                  id: 1,
                  username: 'me',
                ),
                httpService: httpService,
                websocketService: websocketService,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(MessagesView)) as dynamic;
    await state.updateMessages(silentErrors: true);
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(find.text('Welcome landing'), findsOneWidget);
  });

  testWidgets('opens room details from the room title', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        room: RoomSummary(
          id: 1,
          name: 'Coffee crew',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-open-button')));
    await tester.pumpAndSettle();

    expect(find.text('Room details'), findsOneWidget);
    expect(find.byKey(const Key('room-details-name-input')), findsOneWidget);
    expect(find.text('other'), findsWidgets);
  });

  testWidgets('toggles room push notifications from the room menu', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRoomSettings((roomId, pushMuted, name) async {
      return RoomSummary(
        id: roomId,
        name: name,
        updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
        participants: const [
          RoomParticipant(id: 1, username: 'me'),
          RoomParticipant(id: 2, username: 'other'),
        ],
        pushMuted: pushMuted ?? false,
      );
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute notifications'));
    await tester.pumpAndSettle();

    expect(httpService.updatedRoomSettings, [
      {'room_id': 1, 'push_muted': true},
    ]);
    expect(find.text('Notifications muted for this room.'), findsOneWidget);
  });

  testWidgets('toggles room push notifications from room details', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRoomSettings((roomId, pushMuted, name) async {
      return RoomSummary(
        id: roomId,
        name: name,
        updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
        participants: const [
          RoomParticipant(id: 1, username: 'me'),
          RoomParticipant(id: 2, username: 'other'),
        ],
        pushMuted: pushMuted ?? false,
      );
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-open-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute notifications'));
    await tester.pumpAndSettle();

    expect(httpService.updatedRoomSettings, [
      {'room_id': 1, 'push_muted': true},
    ]);
    expect(find.text('Notifications muted for this room.'), findsOneWidget);
  });

  testWidgets('autosaves room name edits from room details', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRoomSettings((roomId, pushMuted, name) async {
      return RoomSummary(
        id: roomId,
        name: name,
        updatedAt: DateTime.parse('2026-04-04T10:00:02.000Z'),
        participants: const [
          RoomParticipant(id: 1, username: 'me'),
          RoomParticipant(id: 2, username: 'other'),
        ],
        pushMuted: pushMuted ?? false,
      );
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        room: RoomSummary(
          id: 1,
          name: 'Coffee crew',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-details-open-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('room-details-name-input')),
      'Night walk',
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(httpService.updatedRoomSettings, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(httpService.updatedRoomSettings, [
      {'room_id': 1, 'name': 'Night walk'},
    ]);
    expect(find.text('Night walk'), findsWidgets);
  });

  testWidgets('remote room renames overwrite the local room name draft', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          name: 'Remote rename',
          updatedAt: DateTime.parse('2026-04-04T10:00:03.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoomDetailsView(
          room: RoomSummary(
            id: 1,
            name: 'Coffee crew',
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
          me: const SessionUser(authenticated: true, id: 1, username: 'me'),
          httpService: httpService,
          websocketService: websocketService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('room-details-name-input')),
      'Local draft',
    );
    websocketService.emitRoomsChanged();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('room-details-name-input')))
          .controller
          ?.text,
      'Remote rename',
    );
    expect(httpService.updatedRoomSettings, isEmpty);
  });

  testWidgets('leaves the room from the room menu after confirmation', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          name: 'Coffee crew',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MessagesView(
                        room: RoomSummary(
                          id: 1,
                          name: 'Coffee crew',
                          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
                          participants: const [
                            RoomParticipant(id: 1, username: 'me'),
                            RoomParticipant(id: 2, username: 'other'),
                          ],
                        ),
                        me: const SessionUser(
                          authenticated: true,
                          id: 1,
                          username: 'me',
                        ),
                        httpService: httpService,
                        websocketService: websocketService,
                      ),
                    ),
                  );
                },
                child: const Text('Open room'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open room'));
    await tester.pumpAndSettle();

    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const Key('room-menu-button')),
        )
        .onSelected
        ?.call('leave-room');
    await tester.pumpAndSettle();

    expect(find.text('Leave room?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();

    expect(httpService.leftRooms, [1]);
    expect(find.text('Open room'), findsOneWidget);
  });

  testWidgets(
    'leave room does not double-pop when room-deleted arrives during the request',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final leaveCompleter = Completer<void>();
      httpService.enqueueLeaveRoom((_) => leaveCompleter.future);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MessagesView(
                          room: RoomSummary(
                            id: 1,
                            name: 'Solo room',
                            updatedAt: DateTime.parse(
                              '2026-04-04T10:00:00.000Z',
                            ),
                            participants: const [
                              RoomParticipant(id: 1, username: 'me'),
                            ],
                          ),
                          me: const SessionUser(
                            authenticated: true,
                            id: 1,
                            username: 'me',
                          ),
                          httpService: httpService,
                          websocketService: websocketService,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open room'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open room'));
      await tester.pumpAndSettle();

      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('room-menu-button')),
          )
          .onSelected
          ?.call('leave-room');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pump();

      websocketService.emitRoomDeleted(1);
      await tester.pumpAndSettle();

      leaveCompleter.complete();
      await tester.pumpAndSettle();

      expect(httpService.leftRooms, [1]);
      expect(find.text('Open room'), findsOneWidget);
      expect(find.byType(MessagesView), findsNothing);
    },
  );

  test('leave room notice storage is scoped per user', () {
    expect(hasSeenLeaveRoomInfo(1), isFalse);
    expect(hasSeenLeaveRoomInfo(2), isFalse);

    markLeaveRoomInfoSeen(1);

    expect(hasSeenLeaveRoomInfo(1), isTrue);
    expect(hasSeenLeaveRoomInfo(2), isFalse);
  });

  test('leave room notice copy becomes brief after the first explanation', () {
    expect(
      describeLeaveRoomDialogBody(showNearbyHint: true),
      'You will leave this room. If another member is nearby, it may show up in Nearby again and you can request to rejoin.',
    );
    expect(
      describeLeaveRoomDialogBody(showNearbyHint: false),
      'You will leave this room.',
    );
  });

  testWidgets('shows pending join requests and approves them from the room', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRoomRequests((_) async {
      return [
        RoomJoinRequest(
          user: NearbyUser(
            id: 7,
            username: 'newcomer',
            distance: 0,
            lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
            status: 'Let me in',
          ),
          createdAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          expiresAt: DateTime.parse('2026-04-11T10:00:00.000Z'),
        ),
      ];
    });
    httpService.enqueueRoomRequests((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending join requests'), findsOneWidget);
    expect(find.text('newcomer'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(httpService.approvedRoomRequests, [
      {'room_id': 1, 'user_id': 7},
    ]);
    expect(find.text('Pending join requests'), findsNothing);
  });

  testWidgets(
    'refreshes the room title when another participant updates profile',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:01.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'renamed'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('other'), findsWidgets);

      websocketService.emitRoomsChanged();
      await tester.pumpAndSettle();

      expect(find.text('renamed'), findsOneWidget);
      expect(find.text('other'), findsNothing);
    },
  );

  testWidgets(
    'refreshes pending join request details when requester updates profile',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueMessages((_) async => []);
      httpService.enqueueRoomRequests((_) async {
        return [
          RoomJoinRequest(
            user: NearbyUser(
              id: 7,
              username: 'newcomer',
              distance: 0,
              lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
              status: 'Old status',
            ),
            createdAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            expiresAt: DateTime.parse('2026-04-11T10:00:00.000Z'),
          ),
        ];
      });
      httpService.enqueueRoomRequests((_) async {
        return [
          RoomJoinRequest(
            user: NearbyUser(
              id: 7,
              username: 'renamed newcomer',
              distance: 0,
              lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
              status: 'Updated status',
            ),
            createdAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            expiresAt: DateTime.parse('2026-04-11T10:00:00.000Z'),
          ),
        ];
      });

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('newcomer'), findsOneWidget);
      expect(find.text('Old status'), findsOneWidget);

      websocketService.emitRoomRequestsChanged(1);
      await tester.pumpAndSettle();

      expect(find.text('renamed newcomer'), findsOneWidget);
      expect(find.text('Updated status'), findsOneWidget);
      expect(find.text('newcomer'), findsNothing);
      expect(find.text('Old status'), findsNothing);
    },
  );

  testWidgets('group chat shows author labels for received message clusters', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    final groupRoom = RoomSummary(
      id: 1,
      name: 'Coffee crew',
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'Bob'),
        RoomParticipant(id: 3, username: 'Charlie'),
      ],
    );
    httpService.enqueueRooms(() async => [groupRoom]);
    httpService.enqueueMessages(
      (_) async => [
        ChatMessage(
          id: 'm1',
          body: 'First from Bob',
          senderId: 2,
          senderUsername: 'Bob',
          timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
        ),
        ChatMessage(
          id: 'm2',
          body: 'Second from Bob',
          senderId: 2,
          senderUsername: 'Bob',
          timestamp: DateTime.parse('2026-04-04T10:01:00.000Z'),
        ),
        ChatMessage(
          id: 'm3',
          body: 'From Charlie',
          senderId: 3,
          senderUsername: 'Charlie',
          timestamp: DateTime.parse('2026-04-04T10:06:00.000Z'),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        room: groupRoom,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('First from Bob'), findsOneWidget);
    expect(find.text('Second from Bob'), findsOneWidget);
    expect(find.text('From Charlie'), findsOneWidget);
  });

  testWidgets('composer publishes typing state changes', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          name: 'Coffee crew',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'Bob'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('message-input-field')),
      'typing now',
    );
    await tester.pump();

    expect(websocketService.typingStates.last, {
      'room_id': 1,
      'is_typing': true,
    });

    await tester.enterText(find.byKey(const Key('message-input-field')), '');
    await tester.pump();

    expect(websocketService.typingStates.last, {
      'room_id': 1,
      'is_typing': false,
    });
  });

  testWidgets('composer toggles between emoji panel and keyboard button', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-emoji-panel')), findsNothing);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('message-emoji-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-emoji-panel')), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);

    await tester.tap(find.byKey(const Key('message-emoji-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-emoji-panel')), findsNothing);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
  });

  testWidgets('emoji picker inserts emoji into the composer', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('message-input-field')), 'Hi ');
    await tester.pump();

    await tester.tap(find.byKey(const Key('message-emoji-toggle-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-emoji-option-0')));
    await tester.pump();

    final input = tester.widget<TextField>(
      find.byKey(const Key('message-input-field')),
    );
    expect(input.controller!.text, 'Hi 😀');
  });

  testWidgets('composer can add a WhatsApp group message from the add menu', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueSendMessage((roomId, body) async {
      return ChatMessage(
        id: 'wa-1',
        kind: ChatMessageKind.whatsappGroup,
        body: '',
        senderId: 1,
        senderUsername: 'me',
        timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
        readByUsers: const [RoomParticipant(id: 1, username: 'me')],
        whatsappGroup: const WhatsappGroupMessageData(
          inviteUrl: 'https://chat.whatsapp.com/InviteToken123',
        ),
      );
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-add-whatsapp-group')));
    await tester.pumpAndSettle();

    expect(find.text('Add WhatsApp group'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('whatsapp-group-link-field')),
      'https://example.com/not-whatsapp',
    );
    await tester.tap(find.byKey(const Key('whatsapp-group-add-submit-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid WhatsApp invite link from chat.whatsapp.com.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('whatsapp-group-link-field')),
      'chat.whatsapp.com/InviteToken123',
    );
    await tester.tap(find.byKey(const Key('whatsapp-group-add-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Add WhatsApp group'), findsNothing);
    expect(httpService.sentMessages.last, {
      'room_id': 1,
      'body': '',
      'kind': 'whatsapp_group',
      'whatsapp_invite_url': 'https://chat.whatsapp.com/InviteToken123',
    });
    expect(
      find.byKey(const Key('whatsapp-group-join-button-wa-1')),
      findsOneWidget,
    );
  });

  testWidgets('whatsapp group message button opens the invite link', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    final openedUrls = <String>[];
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages(
      (_) async => [
        ChatMessage(
          id: 'wa-1',
          kind: ChatMessageKind.whatsappGroup,
          body: '',
          senderId: 2,
          senderUsername: 'other',
          timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
          whatsappGroup: const WhatsappGroupMessageData(
            inviteUrl: 'https://chat.whatsapp.com/InviteToken123',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        externalLinkOpener: (url) async {
          openedUrls.add(url);
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('whatsapp-group-join-button-wa-1')));
    await tester.pumpAndSettle();

    expect(openedUrls, ['https://chat.whatsapp.com/InviteToken123']);
  });

  testWidgets('paste button fills the WhatsApp invite field from clipboard', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{
              'text': 'chat.whatsapp.com/InviteToken123',
            };
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('message-add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('message-add-whatsapp-group')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('whatsapp-group-paste-button')));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(
      find.byKey(const Key('whatsapp-group-link-field')),
    );
    expect(input.controller!.text, 'chat.whatsapp.com/InviteToken123');
  });

  testWidgets(
    'whatsapp add screen cannot be dismissed while submit is in flight',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final sendCompleter = Completer<ChatMessage>();
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);
      httpService.enqueueSendMessage((roomId, body) => sendCompleter.future);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('message-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-add-whatsapp-group')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('whatsapp-group-link-field')),
        'chat.whatsapp.com/InviteToken123',
      );
      await tester.tap(
        find.byKey(const Key('whatsapp-group-add-submit-button')),
      );
      await tester.pump();

      expect(find.text('Adding...'), findsOneWidget);

      await Navigator.of(
        tester.element(find.text('Add WhatsApp group')),
      ).maybePop();
      await tester.pump();

      expect(find.text('Add WhatsApp group'), findsOneWidget);

      sendCompleter.complete(
        ChatMessage(
          id: 'wa-1',
          kind: ChatMessageKind.whatsappGroup,
          body: '',
          senderId: 1,
          senderUsername: 'me',
          timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
          readByUsers: const [RoomParticipant(id: 1, username: 'me')],
          whatsappGroup: const WhatsappGroupMessageData(
            inviteUrl: 'https://chat.whatsapp.com/InviteToken123',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add WhatsApp group'), findsNothing);
    },
  );

  testWidgets(
    'text send validation errors stay visible and restore the composer',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);
      httpService.enqueueSendMessage((roomId, body) async {
        throw InvalidUsage(status: 400, message: 'Too long', code: 1999);
      });

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('message-input-field')),
        'Hello now',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('Too long'), findsOneWidget);
      final input = tester.widget<TextField>(
        find.byKey(const Key('message-input-field')),
      );
      expect(input.controller!.text, 'Hello now');
    },
  );

  testWidgets(
    'updates outgoing receipt icon when another member reads the latest message',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages(
        (_) async => [
          ChatMessage(
            id: 'own-1',
            body: 'My message',
            senderId: 1,
            senderUsername: 'me',
            timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
            readByUsers: const [RoomParticipant(id: 1, username: 'me')],
          ),
        ],
      );

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Seen'), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      var statusIcon = tester.widget<Icon>(
        find.byKey(const Key('message-status-icon')),
      );
      expect(statusIcon.icon, Icons.done_rounded);
      expect(statusIcon.color, const Color(0xFF7A7E80));

      websocketService.emitRoomRead(
        roomId: 1,
        userId: 2,
        messageId: 'own-1',
        username: 'other',
      );
      await tester.pumpAndSettle();

      expect(find.text('Seen'), findsNothing);
      statusIcon = tester.widget<Icon>(
        find.byKey(const Key('message-status-icon')),
      );
      expect(statusIcon.icon, Icons.done_all_rounded);
      expect(statusIcon.color, const Color(0xFF1D8F8C));
    },
  );

  testWidgets(
    'sending a message transitions from pending to sent and delivered',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final sendCompleter = Completer<ChatMessage>();
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);
      httpService.enqueueSendMessage((roomId, body) => sendCompleter.future);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('message-input-field')),
        'Hello now',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send-button')));
      await tester.pump();

      expect(find.text('Hello now'), findsOneWidget);
      expect(httpService.sentMessages, [
        {'room_id': 1, 'body': 'Hello now', 'kind': 'text'},
      ]);
      var statusIcon = tester.widget<Icon>(
        find.byKey(const Key('message-status-icon')),
      );
      expect(statusIcon.icon, Icons.schedule_rounded);
      expect(statusIcon.color, const Color(0xFF7A7E80));

      sendCompleter.complete(
        ChatMessage(
          id: 'sent-1',
          body: 'Hello now',
          senderId: 1,
          senderUsername: 'me',
          timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
          readByUsers: const [RoomParticipant(id: 1, username: 'me')],
        ),
      );
      await tester.pumpAndSettle();

      statusIcon = tester.widget<Icon>(
        find.byKey(const Key('message-status-icon')),
      );
      expect(statusIcon.icon, Icons.done_rounded);
      expect(statusIcon.color, const Color(0xFF7A7E80));

      websocketService.emitRoomDelivered(
        roomId: 1,
        userId: 2,
        messageId: 'sent-1',
        username: 'other',
      );
      await tester.pumpAndSettle();

      statusIcon = tester.widget<Icon>(
        find.byKey(const Key('message-status-icon')),
      );
      expect(statusIcon.icon, Icons.done_all_rounded);
      expect(statusIcon.color, const Color(0xFF7A7E80));

      await tester.pump(const Duration(milliseconds: 220));
      expect(httpService.markedReads.last['message_id'], 'sent-1');
    },
  );

  testWidgets(
    'older same-body own messages do not replace a new pending message',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final sendCompleter = Completer<ChatMessage>();
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);
      httpService.enqueueSendMessage((roomId, body) => sendCompleter.future);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('message-input-field')),
        'Same body',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('message-send-button')));
      await tester.pump();

      websocketService.emitMessage(1, [
        {
          'id': 'old-own-1',
          'body': 'Same body',
          'sender_id': 1,
          'timestamp': '2026-04-04T10:00:00.000Z',
          'read_by_users': [
            {'id': 1, 'username': 'me'},
          ],
        },
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Same body'), findsNWidgets(2));
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    },
  );

  testWidgets(
    'composer send button uses primary color and matches input height',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'other'),
            ],
          ),
        ],
      );
      httpService.enqueueMessages((_) async => []);

      await tester.pumpWidget(
        _buildMessagesApp(
          httpService: httpService,
          websocketService: websocketService,
        ),
      );
      await tester.pumpAndSettle();

      final theme = Theme.of(
        tester.element(find.byKey(const Key('message-send-button'))),
      );
      final sendShell = tester.widget<DecoratedBox>(
        find.byKey(const Key('message-send-shell')),
      );
      final inputHeight = tester
          .getSize(find.byKey(const Key('message-input-shell')))
          .height;
      final sendHeight = tester
          .getSize(find.byKey(const Key('message-send-shell')))
          .height;

      expect(
        (sendShell.decoration as BoxDecoration).color,
        theme.colorScheme.primary,
      );
      expect(sendHeight, inputHeight);
    },
  );

  testWidgets('outgoing message uses single check until someone reads it', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages(
      (_) async => [
        ChatMessage(
          id: 'own-1',
          body: 'Waiting to be seen',
          senderId: 1,
          senderUsername: 'me',
          timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
          readByUsers: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    var statusIcon = tester.widget<Icon>(
      find.byKey(const Key('message-status-icon')),
    );
    expect(statusIcon.icon, Icons.done_rounded);
    expect(statusIcon.color, const Color(0xFF7A7E80));

    websocketService.emitRoomRead(
      roomId: 1,
      userId: 2,
      messageId: 'own-1',
      username: 'other',
    );
    await tester.pumpAndSettle();

    statusIcon = tester.widget<Icon>(
      find.byKey(const Key('message-status-icon')),
    );
    expect(statusIcon.icon, Icons.done_all_rounded);
    expect(statusIcon.color, const Color(0xFF1D8F8C));
    expect(find.text('Seen'), findsNothing);
  });

  testWidgets('outgoing message uses double gray check after delivery', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'other'),
          ],
        ),
      ],
    );
    httpService.enqueueMessages(
      (_) async => [
        ChatMessage(
          id: 'own-1',
          body: 'Delivered',
          senderId: 1,
          senderUsername: 'me',
          timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
          readByUsers: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    websocketService.emitRoomDelivered(
      roomId: 1,
      userId: 2,
      messageId: 'own-1',
      username: 'other',
    );
    await tester.pumpAndSettle();

    final statusIcon = tester.widget<Icon>(
      find.byKey(const Key('message-status-icon')),
    );
    expect(statusIcon.icon, Icons.done_all_rounded);
    expect(statusIcon.color, const Color(0xFF7A7E80));
  });

  testWidgets('solo outgoing message turns blue after send confirmation', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    final sendCompleter = Completer<ChatMessage>();
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ],
    );
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueSendMessage((roomId, body) => sendCompleter.future);

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
        room: RoomSummary(
          id: 1,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [RoomParticipant(id: 1, username: 'me')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('message-input-field')),
      'Solo note',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('message-send-button')));
    await tester.pump();

    sendCompleter.complete(
      ChatMessage(
        id: 'solo-1',
        body: 'Solo note',
        senderId: 1,
        senderUsername: 'me',
        timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
        readByUsers: const [RoomParticipant(id: 1, username: 'me')],
      ),
    );
    await tester.pumpAndSettle();

    final statusIcon = tester.widget<Icon>(
      find.byKey(const Key('message-status-icon')),
    );
    expect(statusIcon.icon, Icons.done_all_rounded);
    expect(statusIcon.color, const Color(0xFF1D8F8C));
  });
}
