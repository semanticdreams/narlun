import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/location_service.dart';
import 'package:narlun/locator.dart';
import 'package:narlun/me_model.dart';
import 'package:narlun/models.dart';
import 'package:narlun/nearby_users_view.dart';
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
}

class FakeNearbyHttpService extends HttpService {
  FakeNearbyHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  List<NearbyUser> nearbyUsers = const [];
  int roomId = 99;
  bool clearedLocalSession = false;
  Object? checkinError;

  @override
  Future<List<NearbyUser>> checkin(lat, lon) async {
    if (checkinError != null) {
      throw checkinError!;
    }
    return nearbyUsers;
  }

  @override
  Future<int> join_user(user_id) async {
    return roomId;
  }

  @override
  Future<void> clearLocalSession() async {
    clearedLocalSession = true;
  }
}

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.enabled = true,
    this.permission = LocationPermission.whileInUse,
    this.requestPermissionResult = LocationPermission.whileInUse,
    Position? position,
  }) : position =
           position ??
           Position(
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

  bool enabled;
  LocationPermission permission;
  LocationPermission requestPermissionResult;
  Position position;
  int isEnabledCalls = 0;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int getCurrentPositionCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls += 1;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    getCurrentPositionCalls += 1;
    return position;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    isEnabledCalls += 1;
    return enabled;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls += 1;
    return requestPermissionResult;
  }
}

Widget _buildNearbyApp({
  required FakeNearbyHttpService httpService,
  required FakeLocationService locationService,
  required Future<void> Function(int roomId) onUserJoined,
  bool autoCheckin = true,
  String initialRoute = '/nearby',
}) {
  return Provider<HttpService>.value(
    value: httpService,
    child: ChangeNotifierProvider(
      create: (_) => MeModel()
        ..setData(
          const SessionUser(authenticated: true, id: 1, username: 'me'),
        ),
      child: MaterialApp(
        initialRoute: initialRoute,
        routes: {
          '/': (_) => const Scaffold(body: Text('Welcome landing')),
          '/nearby': (_) => NearbyUsersView(
                httpService: httpService,
                dialogService: DialogService(),
                locationService: locationService,
                autoCheckin: autoCheckin,
                onUserJoined: onUserJoined,
              ),
        },
      ),
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

  testWidgets('renders nearby users after a successful location checkin', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..nearbyUsers = [
        NearbyUser(
          id: 2,
          username: 'bob',
          distance: 120,
          lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
          status: 'Nearby',
        ),
      ];
    final locationService = FakeLocationService();
    int? joinedRoomId;

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        onUserJoined: (roomId) async {
          joinedRoomId = roomId;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Tap someone to open a room.'), findsOneWidget);
    final listTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('nearby-user-2')),
    );
    final subtitle = listTile.subtitle as Text;
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);

    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();

    expect(joinedRoomId, 99);
  });

  testWidgets('does not render an empty subtitle when status is missing', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..nearbyUsers = [
        NearbyUser(
          id: 2,
          username: 'bob',
          distance: 120,
          lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
        ),
      ];
    final locationService = FakeLocationService();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        onUserJoined: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    final listTile = tester.widget<ListTile>(
      find.byKey(const ValueKey('nearby-user-2')),
    );
    expect(listTile.subtitle, isNull);
  });

  testWidgets('shows a clear status when location services are disabled', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService();
    final locationService = FakeLocationService(enabled: false);

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        onUserJoined: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Location services are not enabled.'), findsOneWidget);
    expect(find.text('Nobody nearby right now. Pull to refresh again soon.'), findsNothing);
  });

  testWidgets('unauthorized checkin expires the session cleanly', (tester) async {
    final httpService = FakeNearbyHttpService();
    final locationService = FakeLocationService();
    httpService.checkinError = UnauthorizedResponse();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        onUserJoined: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(httpService.clearedLocalSession, isTrue);
    expect(find.text('Welcome landing'), findsOneWidget);
  });

  testWidgets('does not request location when auto checkin is disabled', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService();
    final locationService = FakeLocationService();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        autoCheckin: false,
        onUserJoined: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(locationService.isEnabledCalls, 0);
    expect(locationService.checkPermissionCalls, 0);
    expect(locationService.getCurrentPositionCalls, 0);
  });
}
