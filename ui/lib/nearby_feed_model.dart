import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'http.dart';
import 'location_service.dart';
import 'models.dart';

class NearbyLocationProblem implements Exception {
  NearbyLocationProblem(this.description);

  final String description;

  @override
  String toString() => 'NearbyLocationProblem($description)';
}

class NearbyFeedModel extends ChangeNotifier {
  NearbyFeedModel({
    required this.httpService,
    required this.locationService,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const refreshStaleAfter = Duration(minutes: 1);
  static const minLocationRefreshInterval = Duration(minutes: 1);
  static const minAutomaticRefreshInterval = Duration(minutes: 1);

  final HttpService httpService;
  final LocationService locationService;
  final DateTime Function() _now;

  final List<NearbyItem> _nearbyItems = [];
  bool _loading = false;
  String _statusMessage = 'Checking your location...';
  DateTime? _lastRefreshAttemptAt;
  DateTime? _lastNearbyRequestAt;
  DateTime? _lastLocationRequestAt;
  Position? _lastResolvedPosition;
  bool _hasAttemptedRefresh = false;
  int? _sessionUserId;
  int _sessionVersion = 0;
  Future<void>? _refreshTask;

  List<NearbyItem> get nearbyItems => List.unmodifiable(_nearbyItems);
  bool get loading => _loading;
  String get statusMessage => _statusMessage;
  bool get hasCachedData => _nearbyItems.isNotEmpty;

  void syncSession(SessionUser? user) {
    final nextUserId = user?.authenticated == true && user?.id != null
        ? user!.id
        : null;
    if (_sessionUserId == nextUserId) {
      return;
    }
    _sessionUserId = nextUserId;
    _sessionVersion += 1;
    _refreshTask = null;
    _nearbyItems.clear();
    _loading = false;
    _statusMessage = 'Checking your location...';
    _lastRefreshAttemptAt = null;
    _lastNearbyRequestAt = null;
    _lastLocationRequestAt = null;
    _lastResolvedPosition = null;
    _hasAttemptedRefresh = false;
    notifyListeners();
  }

  Future<void> ensureWarm() async {
    if (_sessionUserId == null) {
      return;
    }
    if (_nearbyItems.isEmpty) {
      await refresh();
      return;
    }
    if (_shouldRefreshBecauseStale) {
      unawaited(refresh(userInitiated: false));
    }
  }

  bool get _shouldRefreshBecauseStale {
    final lastRefreshAttemptAt = _lastRefreshAttemptAt;
    if (lastRefreshAttemptAt == null) {
      return true;
    }
    return _now().difference(lastRefreshAttemptAt) >= refreshStaleAfter;
  }

  Future<void> refresh({bool userInitiated = true}) async {
    if (_sessionUserId == null) {
      return;
    }
    if (_refreshTask != null) {
      return _refreshTask!;
    }
    final refreshSessionVersion = _sessionVersion;
    final refreshSessionUserId = _sessionUserId;
    final task = _runRefresh(
      refreshSessionVersion: refreshSessionVersion,
      refreshSessionUserId: refreshSessionUserId,
      userInitiated: userInitiated,
    );
    _refreshTask = task;
    try {
      await task;
    } finally {
      if (identical(_refreshTask, task)) {
        _refreshTask = null;
      }
    }
  }

  Future<void> _runRefresh({
    required int refreshSessionVersion,
    required int? refreshSessionUserId,
    required bool userInitiated,
  }) async {
    final now = _now();
    if (!userInitiated && !_shouldRequestNearby(now)) {
      return;
    }

    final isInitialLoad = !_hasAttemptedRefresh;
    _hasAttemptedRefresh = true;
    final showLoading = userInitiated || isInitialLoad;
    _lastRefreshAttemptAt = now;
    if (showLoading) {
      _setLoading(
        true,
        status: _nearbyItems.isEmpty
            ? 'Checking your location...'
            : 'Refreshing nearby activity...',
      );
    }

    if (!(await locationService.isLocationServiceEnabled())) {
      _setLocationProblem('Location services are not enabled.');
    }

    var permission = await locationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await locationService.requestPermission();
      if (permission == LocationPermission.denied) {
        _setLocationProblem('Location access was denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _setLocationProblem(
        'Location access is permanently denied in this browser.',
      );
    }

    try {
      final loc = await _resolvePosition(now: _now());
      _lastNearbyRequestAt = _now();
      final resp = await httpService.checkin(loc.latitude, loc.longitude);
      if (!_isCurrentRefresh(
        refreshSessionVersion: refreshSessionVersion,
        refreshSessionUserId: refreshSessionUserId,
      )) {
        return;
      }
      _nearbyItems
        ..clear()
        ..addAll(resp);
      _setLoading(
        false,
        status: _nearbyItems.isEmpty
            ? 'Nobody nearby right now. Pull to refresh again soon.'
            : 'Tap people to open a room, or rooms to request access.',
      );
    } catch (_) {
      if (!_isCurrentRefresh(
        refreshSessionVersion: refreshSessionVersion,
        refreshSessionUserId: refreshSessionUserId,
      )) {
        return;
      }
      if (_nearbyItems.isEmpty) {
        _setLoading(
          false,
          status: 'Could not refresh nearby activity. Pull to try again.',
        );
      } else {
        _setLoading(
          false,
          status: 'Showing saved nearby activity while we reconnect.',
        );
      }
      rethrow;
    }
  }

  bool _isCurrentRefresh({
    required int refreshSessionVersion,
    required int? refreshSessionUserId,
  }) {
    return _sessionVersion == refreshSessionVersion &&
        _sessionUserId == refreshSessionUserId;
  }

  bool _shouldRequestNearby(DateTime now) {
    final lastNearbyRequestAt = _lastNearbyRequestAt;
    if (lastNearbyRequestAt == null) {
      return true;
    }
    return now.difference(lastNearbyRequestAt) >= minAutomaticRefreshInterval;
  }

  Future<Position> _resolvePosition({required DateTime now}) async {
    final lastResolvedPosition = _lastResolvedPosition;
    final lastLocationRequestAt = _lastLocationRequestAt;
    if (lastResolvedPosition != null &&
        lastLocationRequestAt != null &&
        now.difference(lastLocationRequestAt) < minLocationRefreshInterval) {
      return lastResolvedPosition;
    }

    final position = await locationService.getCurrentPosition();
    _lastResolvedPosition = position;
    _lastLocationRequestAt = _now();
    return position;
  }

  void markRoomJoinRequested(int roomId) {
    var changed = false;
    for (var i = 0; i < _nearbyItems.length; i += 1) {
      final item = _nearbyItems[i];
      if (item.type == 'room' && item.room?.room.id == roomId) {
        _nearbyItems[i] = NearbyItem(
          type: 'room',
          distance: item.distance,
          room: item.room?.copyWith(joinRequested: true),
        );
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _setLocationProblem(String description) {
    _setLoading(
      false,
      status: _nearbyItems.isEmpty
          ? description
          : 'Showing saved nearby activity. Update location access to refresh.',
    );
    throw NearbyLocationProblem(description);
  }

  void _setLoading(bool loading, {required String status}) {
    _loading = loading;
    _statusMessage = status;
    notifyListeners();
  }
}
