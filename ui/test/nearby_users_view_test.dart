// ignore_for_file: non_constant_identifier_names

import 'dart:async';

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
import 'package:narlun/nearby_feed_model.dart';
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

  final StreamController<Map<String, dynamic>> _nearbyChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _roomsChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionController =
      StreamController<String>.broadcast();

  @override
  Future<void> ensureConnected() async {}

  @override
  Stream<Map<String, dynamic>> nearbyChangedStream() =>
      _nearbyChangedController.stream;

  @override
  Stream<Map<String, dynamic>> roomsChangedStream() =>
      _roomsChangedController.stream;

  @override
  Stream<String> get connectionEvents => _connectionController.stream;

  void emitNearbyChanged() {
    _nearbyChangedController.add({'type': 'nearby-changed', 'data': {}});
  }
}

class FakeNearbyHttpService extends HttpService {
  FakeNearbyHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  List<NearbyItem> nearbyItems = const [];
  Object? checkinError;
  Future<List<NearbyItem>> Function()? checkinHandler;
  int requestRoomJoinCalls = 0;
  int checkinCalls = 0;
  bool clearedLocalSession = false;

  @override
  Future<List<NearbyItem>> checkin(lat, lon) async {
    checkinCalls += 1;
    if (checkinError != null) {
      throw checkinError!;
    }
    if (checkinHandler != null) {
      return checkinHandler!();
    }
    return nearbyItems;
  }

  @override
  Future<RoomSummary> request_room_join(room_id) async {
    requestRoomJoinCalls += 1;
    return RoomSummary(
      id: room_id as int,
      name: 'Writers room',
      updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
      participants: const [
        RoomParticipant(id: 2, username: 'bob'),
        RoomParticipant(id: 3, username: 'cara'),
      ],
    );
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

  @override
  Future<LocationPermission> checkPermission() async {
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    return position;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return enabled;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    return requestPermissionResult;
  }
}

NearbyItem _nearbyRoomItem({
  required int id,
  required String name,
  int? distance = 120,
  bool joinRequested = false,
  String? lastMessageBody,
  int memberCount = 2,
}) {
  final participants = List.generate(
    memberCount,
    (index) => RoomParticipant(id: index + 2, username: 'user-${index + 2}'),
  );
  return NearbyItem(
    type: 'room',
    distance: distance,
    room: NearbyRoom(
      distance: distance,
      joinRequested: joinRequested,
      room: RoomSummary(
        id: id,
        name: name,
        updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
        participants: participants,
        lastMessage: lastMessageBody == null
            ? null
            : MessagePreview(body: lastMessageBody),
      ),
    ),
  );
}

Widget _buildNearbyApp({
  required FakeNearbyHttpService httpService,
  required FakeLocationService locationService,
  required _FakeWebsocketService websocketService,
  NearbyFeedModel? nearbyFeedModel,
  MeModel? meModel,
  bool autoCheckin = true,
  Duration backgroundRefreshInterval =
      NearbyUsersView.defaultBackgroundRefreshInterval,
  VoidCallback? onOpenRooms,
}) {
  return Provider<HttpService>.value(
    value: httpService,
    child: ChangeNotifierProvider<MeModel>.value(
      value:
          meModel ??
          (MeModel()..setData(
            const SessionUser(authenticated: true, id: 1, username: 'me'),
          )),
      child: MaterialApp(
        home: Scaffold(
          body: NearbyUsersView(
            httpService: httpService,
            dialogService: DialogService(),
            locationService: locationService,
            websocketService: websocketService,
            nearbyFeedModel: nearbyFeedModel,
            autoCheckin: autoCheckin,
            backgroundRefreshInterval: backgroundRefreshInterval,
            onOpenRooms: onOpenRooms,
          ),
        ),
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

  testWidgets('renders nearby rooms after a successful location checkin', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..nearbyItems = [
        _nearbyRoomItem(
          id: 7,
          name: 'Writers room',
          lastMessageBody: 'hello from room',
        ),
      ];
    final locationService = FakeLocationService();
    final websocketService = _FakeWebsocketService();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Writers room'), findsOneWidget);
    expect(find.text('hello from room'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    expect(find.text('Tap rooms to request access.'), findsOneWidget);
  });

  testWidgets('requesting a nearby room marks it as requested inline', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..nearbyItems = [_nearbyRoomItem(id: 7, name: 'Writers room')];
    final locationService = FakeLocationService();
    final websocketService = _FakeWebsocketService();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Writers room'));
    await tester.pumpAndSettle();

    expect(httpService.requestRoomJoinCalls, 1);
    expect(find.text('Join request sent.'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
  });

  testWidgets('empty nearby results keep the rooms-only empty state copy', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()..nearbyItems = const [];
    final locationService = FakeLocationService();
    final websocketService = _FakeWebsocketService();
    var openedRooms = 0;

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        websocketService: websocketService,
        onOpenRooms: () {
          openedRooms += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pull to refresh to check again.'), findsOneWidget);
    expect(find.text('No rooms yet'), findsOneWidget);
    expect(find.text('Create a new room from Rooms.'), findsOneWidget);
    expect(find.text('Go to rooms'), findsOneWidget);

    await tester.tap(find.text('Go to rooms'));
    await tester.pumpAndSettle();

    expect(openedRooms, 1);
  });

  testWidgets('refresh failures do not show the no rooms empty state', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService()
      ..checkinError = ServerError(500);
    final locationService = FakeLocationService();
    final websocketService = _FakeWebsocketService();

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        websocketService: websocketService,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not refresh nearby activity. Try again later.'),
      findsOneWidget,
    );
    expect(find.text('No rooms yet'), findsNothing);
    expect(find.text('Go to rooms'), findsNothing);
  });

  testWidgets('nearby-changed refreshes room details only after one minute', (
    tester,
  ) async {
    final httpService = FakeNearbyHttpService();
    final locationService = FakeLocationService();
    final websocketService = _FakeWebsocketService();
    var currentTime = DateTime.parse('2026-04-04T10:00:00.000Z');
    var refreshCount = 0;
    httpService.checkinHandler = () async {
      refreshCount += 1;
      if (refreshCount == 1) {
        return [_nearbyRoomItem(id: 7, name: 'Old room name')];
      }
      return [_nearbyRoomItem(id: 7, name: 'Updated room name')];
    };
    final nearbyFeedModel = NearbyFeedModel(
      httpService: httpService,
      locationService: locationService,
      now: () => currentTime,
    );

    await tester.pumpWidget(
      _buildNearbyApp(
        httpService: httpService,
        locationService: locationService,
        websocketService: websocketService,
        nearbyFeedModel: nearbyFeedModel,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Old room name'), findsOneWidget);

    websocketService.emitNearbyChanged();
    await tester.pumpAndSettle();

    expect(find.text('Old room name'), findsOneWidget);
    expect(find.text('Updated room name'), findsNothing);

    currentTime = currentTime.add(const Duration(minutes: 1, seconds: 1));
    websocketService.emitNearbyChanged();
    await tester.pumpAndSettle();

    expect(find.text('Updated room name'), findsOneWidget);
  });

  testWidgets(
    'standalone nearby view clears cached rooms when session resets',
    (tester) async {
      final httpService = FakeNearbyHttpService()
        ..nearbyItems = [_nearbyRoomItem(id: 7, name: 'Writers room')];
      final locationService = FakeLocationService();
      final websocketService = _FakeWebsocketService();
      final meModel = MeModel()
        ..setData(
          const SessionUser(authenticated: true, id: 1, username: 'me'),
        );

      await tester.pumpWidget(
        _buildNearbyApp(
          httpService: httpService,
          locationService: locationService,
          websocketService: websocketService,
          meModel: meModel,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Writers room'), findsOneWidget);

      meModel.reset();
      await tester.pumpAndSettle();

      expect(find.text('Writers room'), findsNothing);
      expect(find.text('Checking your location...'), findsOneWidget);
    },
  );
}
