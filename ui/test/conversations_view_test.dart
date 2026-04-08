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
import 'package:narlun/messages_view.dart';
import 'package:narlun/models.dart';
import 'package:narlun/push_notifications_service.dart';
import 'package:narlun/rooms_feed_model.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class FakeRoomsHttpService extends HttpService {
  FakeRoomsHttpService({
    required WebsocketService websocketService,
    List<Object>? initialResponses,
  }) : super(
         websocketService: websocketService,
         dialogService: DialogService(),
         client: _DummyHttpClient(),
       ) {
    _responses.addAll(
      initialResponses ?? <Object>[<RoomSummary>[], UnauthorizedResponse()],
    );
  }

  final _responses = <Object>[];
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

class _RouteSpyObserver extends NavigatorObserver {
  final List<String?> pushedRouteNames = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRouteNames.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

class FakeInstallPromptService extends InstallPromptService {
  FakeInstallPromptService({this.available = false, this.suggest = false});

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
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
    );
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

  testWidgets('deep-linked rooms keep the room route name when opened', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final room = RoomSummary(
      id: 42,
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 1, username: 'me'),
        RoomParticipant(id: 2, username: 'bob'),
      ],
    );
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
      initialResponses: [
        <RoomSummary>[room],
      ],
    );
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();
    final routeObserver = _RouteSpyObserver();

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
          navigatorObservers: [routeObserver],
          home: ConversationsView(
            httpService: httpService,
            websocketService: websocketService,
            initialRoomIdToOpen: 42,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MessagesView), findsOneWidget);
    expect(routeObserver.pushedRouteNames, contains('/rooms?open_room=42'));
  });

  testWidgets('does not show the notification prompt on the rooms screen', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
    );
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
  });

  testWidgets('shows a nearby empty state action when there are no rooms', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
    );
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();
    var openNearbyCalls = 0;
    var createRoomCalls = 0;

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
            onCreateRoom: () {
              createRoomCalls += 1;
            },
            onOpenNearby: () {
              openNearbyCalls += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No rooms yet'), findsOneWidget);
    expect(find.text('Create room'), findsOneWidget);
    expect(find.text('Browse nearby'), findsOneWidget);

    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();

    expect(createRoomCalls, 1);

    await tester.tap(find.text('Browse nearby'));
    await tester.pumpAndSettle();

    expect(openNearbyCalls, 1);
  });

  testWidgets(
    'revisiting empty rooms keeps the empty state visible without reloading',
    (tester) async {
      final websocketService = FakeRoomsWebsocketService();
      final httpService = FakeRoomsHttpService(
        websocketService: websocketService,
        initialResponses: [
          <RoomSummary>[],
          <RoomSummary>[
            RoomSummary(
              id: 5,
              updatedAt: DateTime.parse('2026-04-04T10:01:00.000Z'),
              participants: const [
                RoomParticipant(id: 1, username: 'me'),
                RoomParticipant(id: 2, username: 'bob'),
              ],
            ),
          ],
        ],
      );
      final installPromptService = FakeInstallPromptService();
      final pushNotificationsService = FakePushNotificationsService();
      var now = DateTime.parse('2026-04-04T10:00:00.000Z');
      final roomsFeedModel =
          RoomsFeedModel(httpService: httpService, now: () => now)..syncSession(
            const SessionUser(authenticated: true, id: 1, username: 'me'),
          );

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
            home: _RoomsRemountHarness(
              child: ConversationsView(
                httpService: httpService,
                websocketService: websocketService,
                showChrome: false,
                roomsFeedModel: roomsFeedModel,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No rooms yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(httpService.getRoomsCalls, 1);

      await tester.tap(find.text('Hide screen'));
      await tester.pumpAndSettle();
      now = now.add(
        RoomsFeedModel.refreshStaleAfter + const Duration(seconds: 1),
      );

      await tester.tap(find.text('Show screen'));
      await tester.pump();

      expect(find.text('No rooms yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle();

      expect(httpService.getRoomsCalls, 2);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('No rooms yet'), findsNothing);
    },
  );

  testWidgets('opens a requested room after the rooms list loads', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
    );
    httpService
      .._responses.clear()
      ..queueRoomsResponse([
        RoomSummary(
          id: 7,
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

  testWidgets('shows pending join request count in the room list', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
    );
    httpService
      .._responses.clear()
      ..queueRoomsResponse([
        RoomSummary(
          id: 9,
          name: 'Coffee crew',
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          pendingJoinRequestCount: 2,
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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 requests'), findsOneWidget);
  });

  testWidgets(
    'refreshes room titles when another participant updates profile',
    (tester) async {
      final websocketService = FakeRoomsWebsocketService();
      final httpService = FakeRoomsHttpService(
        websocketService: websocketService,
      );
      httpService
        .._responses.clear()
        ..queueRoomsResponse([
          RoomSummary(
            id: 5,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'bob'),
            ],
          ),
        ])
        ..queueRoomsResponse([
          RoomSummary(
            id: 5,
            updatedAt: DateTime.parse('2026-04-04T10:01:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'robert'),
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);

      websocketService.emitRoomsChanged();
      await tester.pumpAndSettle();

      expect(find.text('robert'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
    },
  );

  testWidgets(
    'revisiting rooms keeps cached data visible and refreshes stale summaries in the background',
    (tester) async {
      final websocketService = FakeRoomsWebsocketService();
      final httpService = FakeRoomsHttpService(
        websocketService: websocketService,
        initialResponses: [
          [
            RoomSummary(
              id: 5,
              updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
              participants: const [
                RoomParticipant(id: 1, username: 'me'),
                RoomParticipant(id: 2, username: 'bob'),
              ],
            ),
          ],
          [
            RoomSummary(
              id: 5,
              updatedAt: DateTime.parse('2026-04-04T10:01:00.000Z'),
              participants: const [
                RoomParticipant(id: 1, username: 'me'),
                RoomParticipant(id: 2, username: 'robert'),
              ],
            ),
          ],
        ],
      );
      final installPromptService = FakeInstallPromptService();
      final pushNotificationsService = FakePushNotificationsService();
      var now = DateTime.parse('2026-04-04T10:00:00.000Z');
      final roomsFeedModel =
          RoomsFeedModel(httpService: httpService, now: () => now)..syncSession(
            const SessionUser(authenticated: true, id: 1, username: 'me'),
          );

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
            home: _RoomsRemountHarness(
              child: ConversationsView(
                httpService: httpService,
                websocketService: websocketService,
                showChrome: false,
                roomsFeedModel: roomsFeedModel,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(httpService.getRoomsCalls, 1);

      await tester.tap(find.text('Hide screen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show screen'));
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('robert'), findsNothing);
      expect(httpService.getRoomsCalls, 1);

      await tester.tap(find.text('Hide screen'));
      await tester.pumpAndSettle();
      now = now.add(
        RoomsFeedModel.refreshStaleAfter + const Duration(seconds: 1),
      );

      await tester.tap(find.text('Show screen'));
      await tester.pump();

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('robert'), findsNothing);

      await tester.pumpAndSettle();

      expect(httpService.getRoomsCalls, 2);
      expect(find.text('robert'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
    },
  );

  testWidgets('standalone rooms view clears cached data when session resets', (
    tester,
  ) async {
    final websocketService = FakeRoomsWebsocketService();
    final httpService = FakeRoomsHttpService(
      websocketService: websocketService,
      initialResponses: [
        [
          RoomSummary(
            id: 5,
            updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
            participants: const [
              RoomParticipant(id: 1, username: 'me'),
              RoomParticipant(id: 2, username: 'bob'),
            ],
          ),
        ],
      ],
    );
    final installPromptService = FakeInstallPromptService();
    final pushNotificationsService = FakePushNotificationsService();
    final meModel = MeModel()
      ..setData(const SessionUser(authenticated: true, id: 1, username: 'me'));

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
          ChangeNotifierProvider<MeModel>.value(value: meModel),
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

    expect(find.text('bob'), findsOneWidget);

    meModel.reset();
    await tester.pumpAndSettle();

    expect(find.text('bob'), findsNothing);
    expect(find.text('No rooms yet'), findsOneWidget);
  });
}

class _RoomsRemountHarness extends StatefulWidget {
  const _RoomsRemountHarness({required this.child});

  final Widget child;

  @override
  State<_RoomsRemountHarness> createState() => _RoomsRemountHarnessState();
}

class _RoomsRemountHarnessState extends State<_RoomsRemountHarness> {
  var _showScreen = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          FilledButton(
            onPressed: () {
              setState(() {
                _showScreen = !_showScreen;
              });
            },
            child: Text(_showScreen ? 'Hide screen' : 'Show screen'),
          ),
          Expanded(
            child: _showScreen ? widget.child : const Text('Rooms hidden'),
          ),
        ],
      ),
    );
  }
}
