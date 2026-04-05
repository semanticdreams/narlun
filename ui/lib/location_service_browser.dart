// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:geolocator/geolocator.dart';

import 'frontend_error_reporter.dart';
import 'location_service.dart';

class BrowserLocationService implements LocationService {
  Position? _requestedPosition;

  @override
  Future<LocationPermission> checkPermission() async {
    final permission = await _queryPermission();
    logFrontendDiagnostic(
      'location_check_permission',
      'Checked browser geolocation permission.',
      details: {'permission': permission.name},
    );
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    if (_requestedPosition != null) {
      final position = _requestedPosition!;
      _requestedPosition = null;
      logFrontendDiagnostic(
        'location_reuse_requested_position',
        'Reused the position collected during permission request.',
      );
      return position;
    }

    final position = await _requestBrowserPosition();
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
    try {
      _requestedPosition = await _requestBrowserPosition();
      logFrontendDiagnostic(
        'location_request_permission',
        'Browser geolocation permission granted.',
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
      return LocationPermission.denied;
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
      return LocationPermission.denied;
    }
  }

  Future<Position> _requestBrowserPosition() async {
    try {
      final geoPosition = await html.window.navigator.geolocation
          .getCurrentPosition();
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
    } on html.PositionError catch (error) {
      throw _mapPositionError(error);
    }
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

LocationService createLocationService() {
  return BrowserLocationService();
}
