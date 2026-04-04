import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/messages_view.dart';
import 'package:narlun/websocket.dart';

class FakeMe {
  final Map<String, dynamic> data;

  FakeMe(this.data);
}

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

  final Queue<Future<dynamic> Function(int roomId)> _messageHandlers =
      Queue<Future<dynamic> Function(int roomId)>();
  var getMessagesCalls = 0;

  void enqueueMessages(Future<dynamic> Function(int roomId) handler) {
    _messageHandlers.add(handler);
  }

  @override
  Future get_messages(room_id) async {
    getMessagesCalls += 1;
    return _messageHandlers.removeFirst()(room_id as int);
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
}

Widget _buildMessagesApp({
  required FakeHttpService httpService,
  required FakeWebsocketService websocketService,
}) {
  return MaterialApp(
    home: MessagesView(
      room: {
        'id': 1,
        'is_group': false,
        'participants': [
          {'id': 1, 'username': 'me'},
          {'id': 2, 'username': 'other'},
        ],
      },
      me: FakeMe({'id': 1, 'authenticated': true}),
      httpService: httpService,
      websocketService: websocketService,
    ),
  );
}

void main() {
  testWidgets(
    'merges initial history with live messages received during room setup',
    (tester) async {
      final websocketService = FakeWebsocketService();
      final httpService = FakeHttpService(websocketService: websocketService);
      final historyCompleter = Completer<List<dynamic>>();
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
        {
          'id': 'history-1',
          'body': 'History message',
          'sender_id': 2,
          'timestamp': '2026-04-04T10:00:00.000Z',
        },
      ]);
      await tester.pumpAndSettle();

      expect(find.text('History message'), findsOneWidget);
      expect(find.text('Live message'), findsOneWidget);
      expect(websocketService.subscribedRooms, [1]);
    },
  );

  testWidgets('refreshes room history after a reconnect event', (tester) async {
    final websocketService = FakeWebsocketService();
    final httpService = FakeHttpService(websocketService: websocketService);
    httpService.enqueueMessages((_) async => []);
    httpService.enqueueMessages(
      (_) async => [
        {
          'id': 'after-reconnect',
          'body': 'Recovered message',
          'sender_id': 2,
          'timestamp': '2026-04-04T10:00:02.000Z',
        },
      ],
    );

    await tester.pumpWidget(
      _buildMessagesApp(
        httpService: httpService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    websocketService.emitConnection('reconnected');
    await tester.pumpAndSettle();

    expect(httpService.getMessagesCalls, 2);
    expect(find.text('Recovered message'), findsOneWidget);
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
                        room: {
                          'id': 1,
                          'is_group': false,
                          'participants': [
                            {'id': 1, 'username': 'me'},
                            {'id': 2, 'username': 'other'},
                          ],
                        },
                        me: FakeMe({'id': 1, 'authenticated': true}),
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
                          room: {
                            'id': 1,
                            'is_group': false,
                            'participants': [
                              {'id': 1, 'username': 'me'},
                              {'id': 2, 'username': 'other'},
                            ],
                          },
                          me: FakeMe({'id': 1, 'authenticated': true}),
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
}
