// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:geolocator/geolocator.dart';

import 'frontend_error_reporter.dart';
import 'location_service.dart';

class BrowserLocationService implements LocationService {
  static const Duration _positionCacheMaxAge = Duration(seconds: 8);
  static const Duration _positionRequestTimeout = Duration(seconds: 12);
  static const Duration _positionRefreshWait = Duration(seconds: 2);

  Position? _lastKnownPosition;
  DateTime? _lastKnownPositionAt;
  StreamSubscription<html.Geoposition>? _watchSubscription;
  Completer<Position>? _nextPositionCompleter;
  DateTime? _nextPositionAfter;
  bool _grantedThisSession = false;

  @override
  Future<LocationPermission> checkPermission() async {
    final permission = await _queryPermission();
    final resolvedPermission =
        permission == LocationPermission.denied && _grantedThisSession
        ? LocationPermission.whileInUse
        : permission;
    logFrontendDiagnostic(
      'location_check_permission',
      'Checked browser geolocation permission.',
      details: {
        'permission': resolvedPermission.name,
        'granted_this_session': _grantedThisSession,
        'has_cached_position': _lastKnownPosition != null,
        'watch_active': _watchSubscription != null,
      },
    );
    return resolvedPermission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    final cachedPosition = _freshCachedPosition;
    if (cachedPosition != null) {
      logFrontendDiagnostic(
        'location_reuse_cached_position',
        'Reused a recent browser location.',
        details: {
          'latitude': cachedPosition.latitude,
          'longitude': cachedPosition.longitude,
        },
      );
      return cachedPosition;
    }

    await _ensureWatchActive();
    final stalePosition = _lastKnownPosition;
    final stalePositionAt = _lastKnownPositionAt;
    Position position;
    if (stalePosition != null && stalePositionAt != null) {
      try {
        position = await _awaitNextPosition(
          after: stalePositionAt,
          timeout: _positionRefreshWait,
        );
      } on TimeoutException {
        position = stalePosition;
        logFrontendDiagnostic(
          'location_reuse_stale_position',
          'Reused the last known browser location after waiting for a refresh.',
          details: {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'cached_age_ms': DateTime.now()
                .difference(stalePositionAt)
                .inMilliseconds,
          },
        );
      }
    } else {
      position = await _awaitNextPosition();
    }
    logFrontendDiagnostic(
      'location_get_current_position',
      'Fetched current browser position.',
      details: {'latitude': position.latitude, 'longitude': position.longitude},
    );
    return position;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return true;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    final existingPermission = await checkPermission();
    if (existingPermission == LocationPermission.deniedForever ||
        existingPermission == LocationPermission.whileInUse ||
        existingPermission == LocationPermission.always) {
      return existingPermission;
    }

    try {
      await _ensureWatchActive();
      final position = _lastKnownPosition ?? await _awaitNextPosition();
      _storePosition(position);
      logFrontendDiagnostic(
        'location_request_permission',
        'Browser geolocation permission granted.',
        details: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
      return LocationPermission.whileInUse;
    } catch (error) {
      final permission = await _queryPermission();
      logFrontendDiagnostic(
        'location_request_permission_failed',
        'Browser geolocation permission request failed.',
        details: {'error': error.toString(), 'permission': permission.name},
      );
      return permission;
    }
  }

  Future<LocationPermission> _queryPermission() async {
    final permissions = html.window.navigator.permissions;
    if (permissions == null) {
      return _grantedThisSession
          ? LocationPermission.whileInUse
          : LocationPermission.denied;
    }

    try {
      final status = await permissions.query({'name': 'geolocation'});
      switch (status.state) {
        case 'granted':
          return LocationPermission.whileInUse;
        case 'denied':
          return LocationPermission.deniedForever;
        case 'prompt':
        default:
          return LocationPermission.denied;
      }
    } catch (error) {
      logFrontendDiagnostic(
        'location_query_permission_failed',
        'Browser geolocation permission query failed.',
        details: {'error': error.toString()},
      );
      return _grantedThisSession
          ? LocationPermission.whileInUse
          : LocationPermission.denied;
    }
  }

  Position? get _freshCachedPosition {
    final position = _lastKnownPosition;
    final acquiredAt = _lastKnownPositionAt;
    if (position == null || acquiredAt == null) {
      return null;
    }
    if (DateTime.now().difference(acquiredAt) > _positionCacheMaxAge) {
      return null;
    }
    return position;
  }

  Future<void> _ensureWatchActive() async {
    if (_watchSubscription != null) {
      return;
    }

    logFrontendDiagnostic(
      'location_watch_started',
      'Started persistent browser geolocation watch.',
    );
    _watchSubscription = html.window.navigator.geolocation
        .watchPosition(
          enableHighAccuracy: false,
          timeout: _positionRequestTimeout,
          maximumAge: _positionCacheMaxAge,
        )
        .listen(
          (geoPosition) {
            final position = _toPosition(geoPosition);
            _storePosition(position);
            final completer = _nextPositionCompleter;
            if (completer != null && !completer.isCompleted) {
              final after = _nextPositionAfter;
              final acquiredAt = _lastKnownPositionAt;
              if (after == null ||
                  (acquiredAt != null && acquiredAt.isAfter(after))) {
                completer.complete(position);
                _nextPositionCompleter = null;
                _nextPositionAfter = null;
              }
            }
            logFrontendDiagnostic(
              'location_watch_update',
              'Received browser geolocation watch update.',
              details: {
                'latitude': position.latitude,
                'longitude': position.longitude,
              },
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            final mappedError = error is html.PositionError
                ? _mapPositionError(error)
                : error;
            if (mappedError is PermissionDeniedException) {
              _grantedThisSession = false;
              _clearCachedPosition();
              unawaited(_stopWatch());
            }
            final completer = _nextPositionCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.completeError(mappedError, stackTrace);
              _nextPositionCompleter = null;
              _nextPositionAfter = null;
            }
            logFrontendDiagnostic(
              'location_watch_failed',
              'Browser geolocation watch failed.',
              details: {'error': mappedError.toString()},
            );
          },
          cancelOnError: false,
        );
  }

  Future<Position> _awaitNextPosition({
    DateTime? after,
    Duration timeout = _positionRequestTimeout,
  }) async {
    if (_lastKnownPosition != null &&
        (_lastKnownPositionAt != null &&
            (after == null || _lastKnownPositionAt!.isAfter(after)))) {
      return _lastKnownPosition!;
    }
    final existingCompleter = _nextPositionCompleter;
    if (existingCompleter != null &&
        (after == _nextPositionAfter ||
            (after != null &&
                _nextPositionAfter != null &&
                after == _nextPositionAfter))) {
      return existingCompleter.future.timeout(timeout);
    }

    final completer = Completer<Position>();
    _nextPositionCompleter = completer;
    _nextPositionAfter = after;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_nextPositionCompleter, completer)) {
        _nextPositionCompleter = null;
        _nextPositionAfter = null;
      }
      throw TimeoutException('Browser geolocation timed out.');
    }
  }

  Future<void> _stopWatch() async {
    final subscription = _watchSubscription;
    _watchSubscription = null;
    await subscription?.cancel();
  }

  void _clearCachedPosition() {
    _lastKnownPosition = null;
    _lastKnownPositionAt = null;
  }

  void _storePosition(Position position) {
    _lastKnownPosition = position;
    _lastKnownPositionAt = DateTime.now();
    _grantedThisSession = true;
  }

  Position _toPosition(html.Geoposition geoPosition) {
    final coords = geoPosition.coords;
    if (coords == null) {
      throw StateError('Browser geolocation returned no coordinates.');
    }

    return Position(
      latitude: _toDouble(coords.latitude),
      longitude: _toDouble(coords.longitude),
      timestamp: geoPosition.timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(geoPosition.timestamp!)
          : DateTime.now(),
      altitude: _toDouble(coords.altitude),
      altitudeAccuracy: _toDouble(coords.altitudeAccuracy),
      accuracy: _toDouble(coords.accuracy),
      heading: _toDouble(coords.heading),
      headingAccuracy: 0.0,
      floor: null,
      speed: _toDouble(coords.speed),
      speedAccuracy: 0.0,
      isMocked: false,
    );
  }

  Object _mapPositionError(html.PositionError error) {
    switch (error.code) {
      case 1:
        return PermissionDeniedException(error.message);
      case 2:
        return PositionUpdateException(error.message);
      case 3:
        return TimeoutException(error.message);
      default:
        return StateError(error.message ?? 'Browser geolocation failed.');
    }
  }

  double _toDouble(num? value) {
    return value?.toDouble() ?? 0.0;
  }
}

final BrowserLocationService _browserLocationService = BrowserLocationService();

LocationService createLocationService() {
  return _browserLocationService;
}
