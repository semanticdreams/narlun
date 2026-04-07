// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:narlun/dialog_service.dart';
import 'package:narlun/http.dart';
import 'package:narlun/location_service.dart';
import 'package:narlun/models.dart';
import 'package:narlun/nearby_feed_model.dart';
import 'package:narlun/rooms_feed_model.dart';
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

class _CompletingNearbyHttpService extends HttpService {
  _CompletingNearbyHttpService(this.checkinCompleter)
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  final Completer<List<NearbyItem>> checkinCompleter;

  @override
  Future<List<NearbyItem>> checkin(lat, lon) {
    return checkinCompleter.future;
  }
}

class _CountingNearbyHttpService extends HttpService {
  _CountingNearbyHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  int checkinCalls = 0;

  @override
  Future<List<NearbyItem>> checkin(lat, lon) async {
    checkinCalls += 1;
    return const [];
  }
}

class _CompletingRoomsHttpService extends HttpService {
  _CompletingRoomsHttpService(this.roomsCompleter)
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  final Completer<List<RoomSummary>> roomsCompleter;

  @override
  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) {
    return roomsCompleter.future;
  }
}

class _CountingRoomsHttpService extends HttpService {
  _CountingRoomsHttpService()
    : super(
        websocketService: _FakeWebsocketService(),
        dialogService: DialogService(),
        client: _DummyHttpClient(),
      );

  int getRoomsCalls = 0;

  @override
  Future<List<RoomSummary>> get_rooms({bool silentErrors = false}) async {
    getRoomsCalls += 1;
    return const [];
  }
}

class _StaticLocationService implements LocationService {
  const _StaticLocationService();

  @override
  Future<LocationPermission> checkPermission() async {
    return LocationPermission.whileInUse;
  }

  @override
  Future<Position> getCurrentPosition() async {
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
    return true;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    return LocationPermission.whileInUse;
  }
}

class _CountingLocationService implements LocationService {
  _CountingLocationService();

  int getCurrentPositionCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async {
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
    return true;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    return LocationPermission.whileInUse;
  }
}

void main() {
  test(
    'nearby feed ignores stale refresh results after a session change',
    () async {
      final checkinCompleter = Completer<List<NearbyItem>>();
      final model = NearbyFeedModel(
        httpService: _CompletingNearbyHttpService(checkinCompleter),
        locationService: const _StaticLocationService(),
      );

      model.syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );
      final refreshFuture = model.refresh();
      model.syncSession(
        const SessionUser(authenticated: true, id: 2, username: 'other'),
      );

      checkinCompleter.complete([
        NearbyItem(
          type: 'user',
          distance: 120,
          user: NearbyUser(
            id: 3,
            username: 'bob',
            distance: 120,
            lastSeen: DateTime.parse('2026-04-04T10:00:00.000Z'),
          ),
        ),
      ]);

      await refreshFuture;

      expect(model.nearbyItems, isEmpty);
      expect(model.loading, isFalse);
      expect(model.statusMessage, 'Checking your location...');
    },
  );

  test(
    'rooms feed ignores stale refresh results after a session change',
    () async {
      final roomsCompleter = Completer<List<RoomSummary>>();
      final model = RoomsFeedModel(
        httpService: _CompletingRoomsHttpService(roomsCompleter),
      );

      model.syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );
      final refreshFuture = model.refresh();
      model.syncSession(
        const SessionUser(authenticated: true, id: 2, username: 'other'),
      );

      roomsCompleter.complete([
        RoomSummary(
          id: 5,
          updatedAt: DateTime.parse('2026-04-04T10:00:00.000Z'),
          participants: const [
            RoomParticipant(id: 1, username: 'me'),
            RoomParticipant(id: 3, username: 'bob'),
          ],
        ),
      ]);

      await refreshFuture;

      expect(model.rooms, isEmpty);
      expect(model.isLoadingInitial, isFalse);
      expect(model.errorMessage, isNull);
    },
  );

  test(
    'rooms feed treats an empty successful refresh as cached data',
    () async {
      final httpService = _CountingRoomsHttpService();
      var now = DateTime.parse('2026-04-04T10:00:00.000Z');
      final model = RoomsFeedModel(httpService: httpService, now: () => now);

      model.syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );

      await model.refresh();

      expect(model.rooms, isEmpty);
      expect(model.hasCachedData, isTrue);
      expect(model.isLoadingInitial, isFalse);
      expect(model.errorMessage, isNull);

      await model.ensureWarm();

      expect(httpService.getRoomsCalls, 1);
      expect(model.hasCachedData, isTrue);
      expect(model.isLoadingInitial, isFalse);

      now = now.add(
        RoomsFeedModel.refreshStaleAfter + const Duration(seconds: 1),
      );
      await model.ensureWarm();

      expect(httpService.getRoomsCalls, 2);
      expect(model.hasCachedData, isTrue);
      expect(model.isLoadingInitial, isFalse);
    },
  );

  test(
    'nearby feed throttles automatic refreshes to once per minute',
    () async {
      final httpService = _CountingNearbyHttpService();
      var now = DateTime.parse('2026-04-04T10:00:00.000Z');
      final model = NearbyFeedModel(
        httpService: httpService,
        locationService: _CountingLocationService(),
        now: () => now,
      );

      model.syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );

      await model.refresh(userInitiated: false);
      await model.refresh(userInitiated: false);

      expect(httpService.checkinCalls, 1);

      now = now.add(const Duration(minutes: 1, seconds: 1));
      await model.refresh(userInitiated: false);

      expect(httpService.checkinCalls, 2);
    },
  );

  test(
    'manual nearby refresh bypasses nearby throttling but reuses location for one minute',
    () async {
      final httpService = _CountingNearbyHttpService();
      final locationService = _CountingLocationService();
      var now = DateTime.parse('2026-04-04T10:00:00.000Z');
      final model = NearbyFeedModel(
        httpService: httpService,
        locationService: locationService,
        now: () => now,
      );

      model.syncSession(
        const SessionUser(authenticated: true, id: 1, username: 'me'),
      );

      await model.refresh(userInitiated: true);
      await model.refresh(userInitiated: true);

      expect(httpService.checkinCalls, 2);
      expect(locationService.getCurrentPositionCalls, 1);

      now = now.add(const Duration(minutes: 1, seconds: 1));
      await model.refresh(userInitiated: true);

      expect(httpService.checkinCalls, 3);
      expect(locationService.getCurrentPositionCalls, 2);
    },
  );
}
