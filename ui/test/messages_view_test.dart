import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
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
  _roomSettingsHandlers = Queue<Future<RoomSummary> Function(int roomId, bool pushMuted)>();
  var getMessagesCalls = 0;
  var getRoomsCalls = 0;
  var clearedLocalSession = false;
  final updatedRoomSettings = <Map<String, dynamic>>[];

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

  @override
  Future<List<ChatMessage>> get_messages(room_id, {bool silentErrors = false}) async {
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
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();
  final subscribedRooms = <int>[];
  final unsubscribedRooms = <int>[];
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
  Stream<String> get connectionEvents => _connectionController.stream;

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
}

Widget _buildMessagesApp({
  required FakeHttpService httpService,
  required FakeWebsocketService websocketService,
}) {
  final room = RoomSummary(
    id: 1,
    isGroup: false,
    updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
    participants: const [
      RoomParticipant(id: 1, username: 'me'),
      RoomParticipant(id: 2, username: 'other'),
    ],
  );
  const me = SessionUser(authenticated: true, id: 1, username: 'me');
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

  testWidgets('refreshes room history when a new fetch succeeds', (tester) async {
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
}
