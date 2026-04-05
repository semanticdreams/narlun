import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
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
  final Queue<Future<RoomSummary> Function(int roomId, bool pushMuted)>
  _roomSettingsHandlers =
      Queue<Future<RoomSummary> Function(int roomId, bool pushMuted)>();
  final Queue<Future<List<RoomJoinRequest>> Function(int roomId)>
  _roomRequestHandlers =
      Queue<Future<List<RoomJoinRequest>> Function(int roomId)>();
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
  final markedReads = <Map<String, dynamic>>[];

  void enqueueMessages(Future<List<ChatMessage>> Function(int roomId) handler) {
    _messageHandlers.add(handler);
  }

  void enqueueRooms(Future<List<RoomSummary>> Function() handler) {
    _roomHandlers.add(handler);
  }

  void enqueueRoomSettings(
    Future<RoomSummary> Function(int roomId, bool pushMuted) handler,
  ) {
    _roomSettingsHandlers.add(handler);
  }

  void enqueueRoomRequests(
    Future<List<RoomJoinRequest>> Function(int roomId) handler,
  ) {
    _roomRequestHandlers.add(handler);
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
          isGroup: false,
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
    required bool pushMuted,
  }) async {
    updatedRoomSettings.add({'room_id': room_id, 'push_muted': pushMuted});
    if (_roomSettingsHandlers.isNotEmpty) {
      return _roomSettingsHandlers.removeFirst()(room_id as int, pushMuted);
    }
    return RoomSummary(
      id: room_id as int,
      isGroup: false,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'other'),
      ],
      pushMuted: pushMuted,
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
      isGroup: true,
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
  }

  @override
  Future<ChatMessage> send_message(room_id, message_body) async {
    sentMessages.add({'room_id': room_id, 'body': message_body});
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
}

Widget _buildMessagesApp({
  required FakeHttpService httpService,
  required FakeWebsocketService websocketService,
  RoomSummary? room,
  SessionUser me = const SessionUser(
    authenticated: true,
    id: 1,
    username: 'me',
  ),
}) {
  room ??= RoomSummary(
    id: 1,
    isGroup: false,
    updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
    participants: const [
      RoomParticipant(id: 1, username: 'me'),
      RoomParticipant(id: 2, username: 'other'),
    ],
  );
  return MaterialApp(
    home: MessagesView(
      room: room,
      me: me,
      httpService: httpService,
      websocketService: websocketService,
    ),
  );
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

  testWidgets('refreshes room history when a new fetch succeeds', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          isGroup: false,
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
          isGroup: false,
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
    await state.update_messages(silentErrors: true);
    await tester.pumpAndSettle();

    expect(find.text('Recovered message'), findsOneWidget);
  });

  testWidgets('refreshes the room title when membership changes', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          isGroup: false,
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
          isGroup: true,
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
                          isGroup: false,
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
                            isGroup: false,
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
                  isGroup: false,
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
    await state.update_messages(silentErrors: true);
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(find.text('Welcome landing'), findsOneWidget);
  });

  testWidgets('toggles room push notifications from the room menu', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueRoomSettings((roomId, pushMuted) async {
      return RoomSummary(
        id: roomId,
        isGroup: false,
        updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
        participants: const [
          RoomParticipant(id: 1, username: 'me'),
          RoomParticipant(id: 2, username: 'other'),
        ],
        pushMuted: pushMuted,
      );
    });

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute notifications'));
    await tester.pumpAndSettle();

    expect(httpService.updatedRoomSettings, [
      {'room_id': 1, 'push_muted': true},
    ]);
    expect(find.text('Notifications muted for this room.'), findsOneWidget);
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
          isGroup: true,
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
                          isGroup: true,
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
        .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
        .onSelected
        ?.call('leave-room');
    await tester.pumpAndSettle();

    expect(find.text('Leave room?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();

    expect(httpService.leftRooms, [1]);
    expect(find.text('Open room'), findsOneWidget);
  });

  test('leave room notice storage is scoped per user', () {
    expect(hasSeenLeaveRoomInfo(1), isFalse);
    expect(hasSeenLeaveRoomInfo(2), isFalse);

    markLeaveRoomInfoSeen(1);

    expect(hasSeenLeaveRoomInfo(1), isTrue);
    expect(hasSeenLeaveRoomInfo(2), isFalse);
  });

  test('leave room notice copy becomes brief after the first explanation', () {
    expect(
      describeLeaveRoomDialogBody(isDirectRoom: false, showNearbyHint: true),
      'You will leave this room. If another member is nearby, it may show up in Nearby again and you can request to rejoin.',
    );
    expect(
      describeLeaveRoomDialogBody(isDirectRoom: false, showNearbyHint: false),
      'You will leave this room.',
    );
    expect(
      describeLeaveRoomDialogBody(isDirectRoom: true, showNearbyHint: true),
      'You will leave this conversation. You can start a new one later.',
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
            isGroup: false,
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
            isGroup: false,
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
      isGroup: true,
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
          isGroup: true,
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
          isGroup: false,
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
          isGroup: false,
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

  testWidgets(
    'updates seen label when another member reads the latest message',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            isGroup: false,
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

      websocketService.emitRoomRead(
        roomId: 1,
        userId: 2,
        messageId: 'own-1',
        username: 'other',
      );
      await tester.pumpAndSettle();

      expect(find.text('Seen'), findsOneWidget);
    },
  );

  testWidgets('sending a message renders it immediately and marks it read', (
    tester,
  ) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueRooms(
      () async => [
        RoomSummary(
          id: 1,
          isGroup: false,
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
        id: 'sent-1',
        body: body,
        senderId: 1,
        senderUsername: 'me',
        timestamp: DateTime.parse('2026-04-04T10:00:10.000Z'),
        readByUsers: const [RoomParticipant(id: 1, username: 'me')],
      );
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
    await tester.pump();

    expect(find.text('Hello now'), findsOneWidget);
    expect(httpService.sentMessages, [
      {'room_id': 1, 'body': 'Hello now'},
    ]);

    await tester.pump(const Duration(milliseconds: 220));
    expect(httpService.markedReads.last['message_id'], 'sent-1');
  });

  testWidgets(
    'composer send button uses primary color and matches input height',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      httpService.enqueueRooms(
        () async => [
          RoomSummary(
            id: 1,
            isGroup: false,
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
          isGroup: false,
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

    expect(find.byIcon(Icons.done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);

    websocketService.emitRoomRead(
      roomId: 1,
      userId: 2,
      messageId: 'own-1',
      username: 'other',
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });
}
