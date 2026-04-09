// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:geolocator/geolocator.dart';

import 'frontend_error_reporter.dart';
import 'location_service.dart';

class BrowserLocationService implements LocationService {
  static const Duration _positionCacheMaxAge = Duration(minutes: 1);
  static const Duration _positionRequestTimeout = Duration(seconds: 30);

  int _nextDiagnosticOperationId = 0;
  Position? _lastKnownPosition;
  DateTime? _lastKnownPositionAt;
  StreamSubscription<html.Geoposition>? _watchSubscription;
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
    final operationId = _allocateDiagnosticOperationId();
    logFrontendDiagnostic(
      'location_get_current_position_started',
      'Started resolving the current browser position.',
      details: {'operation_id': operationId, ..._diagnosticStateDetails()},
    );
    final cachedPosition = _freshCachedPosition;
    if (cachedPosition != null) {
      unawaited(_ensureWatchActive());
      logFrontendDiagnostic(
        'location_reuse_cached_position',
        'Reused a recent browser location.',
        details: {
          'operation_id': operationId,
          'latitude': cachedPosition.latitude,
          'longitude': cachedPosition.longitude,
          'cached_age_ms': _lastKnownPositionAgeMs(),
          ..._diagnosticStateDetails(),
        },
      );
      return cachedPosition;
    }

    final position = await _requestSinglePosition(
      timeout: _positionRequestTimeout,
      parentOperationId: operationId,
    );
    unawaited(_ensureWatchActive());
    logFrontendDiagnostic(
      'location_get_current_position',
      'Fetched current browser position.',
      details: {
        'operation_id': operationId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        ..._diagnosticStateDetails(),
      },
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
      final position = await getCurrentPosition();
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
      logFrontendDiagnostic(
        'location_watch_already_active',
        'Browser geolocation watch was already active.',
        details: _diagnosticStateDetails(),
      );
      return;
    }

    logFrontendDiagnostic(
      'location_watch_started',
      'Started persistent browser geolocation watch.',
      details: {
        'maximum_age_ms': _positionCacheMaxAge.inMilliseconds,
        ..._diagnosticStateDetails(),
      },
    );
    _watchSubscription = html.window.navigator.geolocation
        .watchPosition(
          enableHighAccuracy: false,
          maximumAge: _positionCacheMaxAge,
        )
        .listen(
          (geoPosition) {
            final position = _toPosition(geoPosition);
            _storePosition(position);
            logFrontendDiagnostic(
              'location_watch_update',
              'Received browser geolocation watch update.',
              details: {
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracy': position.accuracy,
                ..._diagnosticStateDetails(),
              },
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            final rawErrorCode = error is html.PositionError
                ? error.code
                : null;
            final rawErrorMessage = error is html.PositionError
                ? error.message
                : null;
            final mappedError = error is html.PositionError
                ? _mapPositionError(error)
                : error;
            if (mappedError is PermissionDeniedException) {
              _grantedThisSession = false;
              _clearCachedPosition();
              unawaited(_stopWatch());
            }
            logFrontendDiagnostic(
              'location_watch_failed',
              'Browser geolocation watch failed.',
              details: {
                'error': mappedError.toString(),
                'raw_error_code': rawErrorCode,
                'raw_error_message': rawErrorMessage,
                ..._diagnosticStateDetails(),
              },
            );
          },
          cancelOnError: false,
        );
  }

  Future<Position> _requestSinglePosition({
    required Duration timeout,
    int? parentOperationId,
  }) async {
    final operationId = _allocateDiagnosticOperationId();
    final startedAt = DateTime.now();
    logFrontendDiagnostic(
      'location_single_position_started',
      'Started a one-shot browser geolocation request.',
      details: {
        'operation_id': operationId,
        'parent_operation_id': parentOperationId,
        'timeout_ms': timeout.inMilliseconds,
        'maximum_age_ms': _positionCacheMaxAge.inMilliseconds,
        ..._diagnosticStateDetails(),
      },
    );
    try {
      final geoPosition = await html.window.navigator.geolocation
          .getCurrentPosition(
            enableHighAccuracy: false,
            timeout: timeout,
            maximumAge: _positionCacheMaxAge,
          );
      final position = _toPosition(geoPosition);
      _storePosition(position);
      logFrontendDiagnostic(
        'location_single_position_completed',
        'Completed a one-shot browser geolocation request.',
        details: {
          'operation_id': operationId,
          'parent_operation_id': parentOperationId,
          'duration_ms': DateTime.now().difference(startedAt).inMilliseconds,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          ..._diagnosticStateDetails(),
        },
      );
      return position;
    } catch (error) {
      final rawErrorCode = error is html.PositionError ? error.code : null;
      final rawErrorMessage = error is html.PositionError
          ? error.message
          : null;
      final mappedError = error is html.PositionError
          ? _mapPositionError(error)
          : error;
      logFrontendDiagnostic(
        'location_single_position_failed',
        'One-shot browser geolocation request failed.',
        details: {
          'operation_id': operationId,
          'parent_operation_id': parentOperationId,
          'duration_ms': DateTime.now().difference(startedAt).inMilliseconds,
          'error': mappedError.toString(),
          'raw_error_code': rawErrorCode,
          'raw_error_message': rawErrorMessage,
          ..._diagnosticStateDetails(),
        },
      );
      if (error is html.PositionError) {
        throw mappedError;
      }
      rethrow;
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
    _lastKnownPositionAt = position.timestamp;
    _grantedThisSession = true;
  }

  int _allocateDiagnosticOperationId() {
    _nextDiagnosticOperationId += 1;
    return _nextDiagnosticOperationId;
  }

  Map<String, Object?> _diagnosticStateDetails() {
    final document = html.document;
    return {
      'watch_active': _watchSubscription != null,
      'has_cached_position': _lastKnownPosition != null,
      'cached_position_age_ms': _lastKnownPositionAgeMs(),
      'granted_this_session': _grantedThisSession,
      'document_visibility': document.visibilityState,
      'document_hidden': document.hidden,
      'navigator_online': html.window.navigator.onLine,
      'route_path': html.window.location.pathname,
    };
  }

  int? _lastKnownPositionAgeMs() {
    return _ageMs(_lastKnownPositionAt);
  }

  int? _ageMs(DateTime? timestamp) {
    if (timestamp == null) {
      return null;
    }
    return DateTime.now().difference(timestamp).inMilliseconds;
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
