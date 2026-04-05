// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/install_prompt_service.dart';
import 'package:narlun/home_tab_storage.dart';
import 'package:narlun/home_view.dart';
import 'package:narlun/http.dart';
import 'package:narlun/location_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/messages_view.dart';
import 'package:narlun/models.dart';
import 'package:narlun/route_utils.dart';
import 'package:narlun/websocket.dart';

class _DummyHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }
}

class _FakeWebsocketService extends WebsocketService {
  _FakeWebsocketService()
    : super(
        baseurl: 'http://example.com/api',
        connector: (uri, {headers}) => throw UnimplementedError(),
      );

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> subscribeRoom(roomId) async {}

  @override
  Future<void> unsubscribeRoom(roomId) async {}
}

class _FakeInstallPromptService extends InstallPromptService {
  @override
  bool get isInstallAvailable => false;

  @override
  bool get isInstalled => false;

  @override
  bool get shouldShowSuggestion => false;

  @override
  void dismissSuggestion() {}

  @override
  Future<InstallPromptOutcome> requestInstall() async {
    return InstallPromptOutcome.unavailable;
  }
}

class FakeNearbyHttpService extends HttpService {
  FakeNearbyHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  int checkinCalls = 0;
  int joinUserCalls = 0;
  List<NearbyItem> nearbyItems = const [];

  @override
  Future<List<NearbyItem>> checkin(lat, lon) async {
    checkinCalls += 1;
    return nearbyItems;
  }

  @override
  Future<int> join_user(user_id) async {
    joinUserCalls += 1;
    return 42;
  }

  @override
  Future<List<ChatMessage>> get_messages(
    room_id, {
    bool silentErrors = false,
  }) async {
    return const [];
  }
}

class FakeLocationService implements LocationService {
  int isEnabledCalls = 0;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls += 1;
    return LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition() async {
    getCurrentPositionCalls += 1;
    return Position(
      longitude: 2,
      latitude: 1,
      timestamp: DateTime.parse('2026-04-04T10:00:00.000Z'),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    isEnabledCalls += 1;
    return true;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls += 1;
    return LocationPermission.whileInUse;
  }
}

void main() {
  setUp(() async {
    await setupLocator(
      reset: true,
      dialogService: DialogService(),
      websocketService: _FakeWebsocketService(),
    );
    clearStoredHomeTabIndexForTests();
  });

  tearDown(() async {
    clearStoredHomeTabIndexForTests();
    await locator.reset();
  });

  testWidgets(
    'home view only requests location after the nearby tab is opened',
    (tester) async {
      final httpService = FakeNearbyHttpService();
      final locationService = FakeLocationService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<HttpService>.value(value: httpService),
            ChangeNotifierProvider<InstallPromptService>(
              create: (_) => _FakeInstallPromptService(),
            ),
            ChangeNotifierProvider(
              create: (_) => MeModel()
                ..setData(
                  const SessionUser(authenticated: true, id: 1, username: 'me'),
                ),
            ),
          ],
          child: MaterialApp(
            home: HomeView(
              initialTabIndex: 1,
              nearbyLocationService: locationService,
              roomsView: const Scaffold(body: Text('Rooms placeholder')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rooms placeholder'), findsOneWidget);
      expect(locationService.isEnabledCalls, 0);
      expect(locationService.checkPermissionCalls, 0);
      expect(locationService.getCurrentPositionCalls, 0);
      expect(httpService.checkinCalls, 0);

      await tester.tap(find.byIcon(Icons.people_outline));
      await tester.pumpAndSettle();

      expect(locationService.isEnabledCalls, 1);
      expect(locationService.checkPermissionCalls, 1);
      expect(locationService.getCurrentPositionCalls, 1);
      expect(httpService.checkinCalls, 1);
    },
  );

  testWidgets('home view remembers the last selected tab', (tester) async {
    writeStoredHomeTabIndex(1);
    final httpService = FakeNearbyHttpService();
    final locationService = FakeLocationService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>(
            create: (_) => _FakeInstallPromptService(),
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: HomeView(
            nearbyLocationService: locationService,
            roomsView: const Scaffold(body: Text('Rooms placeholder')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rooms placeholder'), findsOneWidget);
    expect(locationService.isEnabledCalls, 0);

    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();

    expect(readStoredHomeTabIndex(), 0);
  });

  testWidgets('tapping a nearby user opens the room immediately', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..nearbyItems = [
        NearbyItem(
          type: 'user',
          distance: 120,
          user: NearbyUser(
            id: 2,
            username: 'bob',
            distance: 120,
            lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
            status: 'Nearby',
          ),
        ),
      ];
    final locationService = FakeLocationService();

    await setupLocator(
      reset: true,
      dialogService: DialogService(),
      websocketService: _FakeWebsocketService(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<HttpService>.value(value: httpService),
          ChangeNotifierProvider<InstallPromptService>(
            create: (_) => _FakeInstallPromptService(),
          ),
          ChangeNotifierProvider(
            create: (_) => MeModel()
              ..setData(
                const SessionUser(authenticated: true, id: 1, username: 'me'),
              ),
          ),
        ],
        child: MaterialApp(
          home: HomeView(
            initialTabIndex: 0,
            nearbyLocationService: locationService,
            roomsView: const Scaffold(body: Text('Rooms placeholder')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();

    expect(httpService.joinUserCalls, 1);
    expect(
      ModalRoute.of(tester.element(find.byType(MessagesView)))?.settings.name,
      roomsRouteWithOpenRoom(42),
    );
    expect(find.byType(MessagesView), findsOneWidget);
    expect(find.byKey(const Key('message-input-field')), findsOneWidget);

    Navigator.of(tester.element(find.byType(MessagesView))).pop();
    await tester.pumpAndSettle();

    expect(find.text('bob'), findsOneWidget);
  });
}
