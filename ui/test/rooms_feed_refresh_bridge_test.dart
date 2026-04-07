// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/rooms_feed_model.dart';
import 'package:narlun/rooms_feed_refresh_bridge.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class _FakeRoomsHttpService extends HttpService {
  _FakeRoomsHttpService({
    required WebsocketService websocketService,
    required List<List<RoomSummary>> responses,
  }) : super(
         websocketService: websocketService,
         dialogService: DialogService(),
         client: _DummyHttpClient(),
       ) {
    _responses.addAll(responses);
  }

  final Queue<List<RoomSummary>> _responses = Queue<List<RoomSummary>>();
  int getRoomsCalls = 0;

  @override
  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) async {
    getRoomsCalls += 1;
    return _responses.removeFirst();
  }
}

class _FakeWebsocketService extends WebsocketService {
  _FakeWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );

  final StreamController<Map<String, dynamic>> _roomsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionEventsController =
      StreamController<String>.broadcast();

  @override
  Stream<Map<String, dynamic>> roomsChangedStream() =>
      _roomsChangedController.stream;

  @override
  Stream<String> get connectionEvents => _connectionEventsController.stream;

  void emitRoomsChanged() {
    _roomsChangedController.add({'type': 'rooms-changed', 'data': {}});
  }

  void emitConnection(String event) {
    _connectionEventsController.add(event);
  }
}

void main() {
  setUp(() async {
    await setupLocator(
      reset: true,
      dialogService: DialogService(),
      websocketService: _FakeWebsocketService(),
    );
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets(
    'refreshes cached room summaries when rooms change outside the rooms screen',
    (tester) async {
      final websocketService =
          locator<WebsocketService>() as _FakeWebsocketService;
      final httpService = _FakeRoomsHttpService(
        websocketService: websocketService,
        responses: [
          [
            RoomSummary(
              id: 7,
              updatedAt: DateTime.parse('2026-04-07T12:00:00.000Z'),
              participants: const [
                RoomParticipant(id: 1, username: 'me'),
                RoomParticipant(id: 2, username: 'bob'),
              ],
              lastMessage: const MessagePreview(
                body: 'before',
                senderId: 2,
                senderUsername: 'bob',
              ),
            ),
          ],
          [
            RoomSummary(
              id: 7,
              updatedAt: DateTime.parse('2026-04-07T12:01:00.000Z'),
              participants: const [
                RoomParticipant(id: 1, username: 'me'),
                RoomParticipant(id: 2, username: 'bob'),
              ],
              lastMessage: const MessagePreview(
                body: 'after',
                senderId: 2,
                senderUsername: 'bob',
              ),
            ),
          ],
        ],
      );
      final roomsFeedModel = RoomsFeedModel(httpService: httpService)
        ..syncSession(
          const SessionUser(authenticated: true, id: 1, username: 'me'),
        );

      await roomsFeedModel.refresh();
      expect(roomsFeedModel.rooms.single.lastMessage?.body, 'before');
      expect(httpService.getRoomsCalls, 1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MeModel>(
              create: (_) => MeModel(
                data: const SessionUser(
                  authenticated: true,
                  id: 1,
                  username: 'me',
                ),
              ),
            ),
            ChangeNotifierProvider<RoomsFeedModel>.value(value: roomsFeedModel),
          ],
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: RoomsFeedRefreshBridge(child: SizedBox()),
          ),
        ),
      );

      websocketService.emitRoomsChanged();
      await tester.pump();
      await tester.pump();

      expect(httpService.getRoomsCalls, 2);
      expect(roomsFeedModel.rooms.single.lastMessage?.body, 'after');
    },
  );

  testWidgets('does not cold-load rooms from background refresh events', (
    tester,
  ) async {
    final websocketService =
        locator<WebsocketService>() as _FakeWebsocketService;
    final httpService = _FakeRoomsHttpService(
      websocketService: websocketService,
      responses: const [],
    );
    final roomsFeedModel = RoomsFeedModel(httpService: httpService)
      ..syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeModel>(
            create: (_) => MeModel(
              data: const SessionUser(
                authenticated: true,
                id: 1,
                username: 'me',
              ),
            ),
          ),
          ChangeNotifierProvider<RoomsFeedModel>.value(value: roomsFeedModel),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: RoomsFeedRefreshBridge(child: SizedBox()),
        ),
      ),
    );

    websocketService.emitRoomsChanged();
    websocketService.emitConnection('reconnected');
    await tester.pump();

    expect(httpService.getRoomsCalls, 0);
    expect(roomsFeedModel.rooms, isEmpty);
  });
}
