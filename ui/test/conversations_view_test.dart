// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/conversations_view.dart';
import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/push_notifications_service.dart';
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

  void queueRoomsResponse(Object response) {
    _responses.add(response);
  }

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
  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> subscribeRoom(roomId) async {}

  @override
  Future<void> unsubscribeRoom(roomId) async {}

  @override
  Stream<Map<String, dynamic>> roomsChangedStream() =>
      _roomsChangedController.stream;

  @override
  Stream<Map<String, dynamic>> messagesStream(roomId) =>
      _messagesController.stream;

  @override
  Stream<Map<String, dynamic>> roomDeletedStream(roomId) =>
      _roomDeletedController.stream;

  @override
  Stream<String> get connectionEvents => _connectionController.stream;

  void emitRoomsChanged() {
    _roomsChangedController.add({'type': 'rooms-changed', 'data': {}});
  }
}

class FakeInstallPromptService extends InstallPromptService {
  FakeInstallPromptService({
    this.available = false,
    this.suggest = false,
  });

  bool available;
  bool suggest;
  int requestInstallCalls = 0;
  int dismissCalls = 0;

  @override
  bool get isInstallAvailable => available;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => suggest;

  @override
  void dismissSuggestion() {
    dismissCalls += 1;
    suggest = false;
    notifyListeners();
  }

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    requestInstallCalls += 1;
    available = false;
    suggest = false;
    notifyListeners();
    return InstallPromptOutcome.accepted;
  }
}

class FakePushNotificationsService extends PushNotificationsService {
  FakePushNotificationsService({
    this.prompt = false,
    this.supported = true,
    this.configured = true,
  });

  bool prompt;
  final bool supported;
  final bool configured;
  int enableCalls = 0;
  int dismissCalls = 0;

  @override
  bool get isBusy => false;

  @override
  bool get isConfigured => configured;

  @override
  bool get isSubscribed => false;

  @override
  bool get isSupported => supported;

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
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
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
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(ConversationsView)) as dynamic;
    await state.updateRooms(silentErrors: true);
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(find.text('Welcome landing'), findsOneWidget);
  });

  testWidgets('shows a dismissible install suggestion on the rooms screen', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(websocketService: websocketService);
    final installPromptService = FakeInstallPromptService(
      available: true,
      suggest: true,
    );
    final pushNotificationsService = FakePushNotificationsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: ConversationsView(
            httpService: httpService,
            websocketService: websocketService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install Narlun'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('Install Narlun'), findsOneWidget);
    expect(find.text('Install app'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(installPromptService.dismissCalls, 1);
    expect(find.text('Install Narlun'), findsNothing);
  });

  testWidgets('shows a dismissible notification prompt on the rooms screen', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(websocketService: websocketService);
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService(prompt: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: ConversationsView(
            httpService: httpService,
            websocketService: websocketService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Turn On Notifications'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('Turn On Notifications'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(pushNotificationsService.dismissCalls, 1);
    expect(find.text('Turn On Notifications'), findsNothing);
  });

  testWidgets('shows a nearby empty state action when there are no rooms', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(websocketService: websocketService);
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();
    var openNearbyCalls = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: ConversationsView(
            httpService: httpService,
            websocketService: websocketService,
            onOpenNearby: () {
              openNearbyCalls += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No rooms yet'), findsOneWidget);
    expect(find.text('Find people nearby'), findsOneWidget);

    await tester.tap(find.text('Find people nearby'));
    await tester.pumpAndSettle();

    expect(openNearbyCalls, 1);
  });

  testWidgets('opens a requested room after the rooms list loads', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(websocketService: websocketService);
    httpService
      .._responses.clear()
      ..queueRoomsResponse([
        RoomSummary(
          id: 7,
          isGroup: false,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 2, username: 'bob'),
          ],
        ),
      ]);
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>.value(
            value: installPromptService,
          ),
          ChangeNotifierProvider<PushNotificationsService>.value(
            value: pushNotificationsService,
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: ConversationsView(
            httpService: httpService,
            websocketService: websocketService,
            initialRoomIdToOpen: 7,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('bob'), findsWidgets);
  });
}
