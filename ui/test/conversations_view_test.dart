import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/conversations_view.dart';
import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class FakeRoomsHttpService extends HttpService {
  FakeRoomsHttpService({required WebsocketService websocketService})
    : super(
        websocketService: websocketService,
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  final _responses = <Object>[
    <RoomSummary>[],
    UnauthorizedResponse(),
  ];
  var getRoomsCalls = 0;
  var clearedLocalSession = false;

  @override
  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) async {
    getRoomsCalls += 1;
    final next = _responses.removeAt(0);
    if (next is List<RoomSummary>) {
      return next;
    }
    throw next;
  }

  @override
  Future<void> clearLocalSession() async {
    clearedLocalSession = true;
  }
}

class FakeRoomsWebsocketService extends WebsocketService {
  FakeRoomsWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );

  final StreamController<Map<String, dynamic>> _roomsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();

  @override
  Future<void> ensureConnected() async {}

  @override
  Stream<Map<String, dynamic>> roomsChangedStream() =>
      _roomsChangedController.stream;

  @override
  Stream<String> get connectionEvents => _connectionController.stream;

  void emitRoomsChanged() {
    _roomsChangedController.add({'type': 'rooms-changed', 'data': {}});
  }
}

void main() {
  setUp(() async {
    await setupLocator(reset: true, dialogService: DialogService());
  });

  tearDown(() async {
    await locator.reset();
  });

  testWidgets('unauthorized room refresh expires the session cleanly', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(websocketService: websocketService);

    await tester.pumpWidget(
      Provider<HttpService>.value(
        value: httpService,
        child: ChangeNotifierProvider(
          create: (_) => MeModel()
            ..setData(
              const SessionUser(authenticated: true, id: 1, username: 'me'),
            ),
          child: MaterialApp(
            initialRoute: '/rooms',
            routes: {
              '/': (_) => const Scaffold(body: Text('Welcome landing')),
              '/rooms': (_) => ConversationsView(
                    httpService: httpService,
                    websocketService: websocketService,
                  ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ConversationsView)) as dynamic;
    await state.update_rooms(silentErrors: true);
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(find.text('Welcome landing'), findsOneWidget);
  });
}
