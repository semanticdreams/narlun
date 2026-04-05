import 'package:geolocator/geolocator.dart';

import 'location_service_default.dart'
    if (dart.library.html) 'location_service_browser.dart'
    as impl;

abstract class LocationService {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition();
}

LocationService createLocationService() {
  return impl.createLocationService();
}
