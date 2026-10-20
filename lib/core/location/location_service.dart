import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../errors/app_failure.dart';
import 'store_location.dart';

/// One foreground fix on explicit request; no background permission or tracking.
class LocationService {
  LocationService({GeolocatorPlatform? platform})
    : _platform = platform ?? GeolocatorPlatform.instance;
  static LocationService instance = LocationService();
  final GeolocatorPlatform _platform;
  Future<StoreLocation> suggest() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        throw const AppFailure(
          'Location services are disabled. Enable location in device settings, or enter your store coordinates manually.',
        );
      }
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission().timeout(
          const Duration(seconds: 25),
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const AppFailure(
          'Location permission is permanently denied. Allow location in app settings, or enter coordinates manually.',
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        throw const AppFailure(
          'Location permission was denied. You can retry or enter your store coordinates manually.',
        );
      }
      final fix = await _platform.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return StoreLocation(fix.latitude, fix.longitude);
    } on TimeoutException {
      throw const AppFailure(
        'Location timed out. Move somewhere with a clearer signal and retry, or enter coordinates manually.',
      );
    } on UnsupportedError {
      throw const AppFailure(
        'Device location is unavailable here. Use HTTPS or localhost in a supported browser, or enter coordinates manually.',
      );
    } on PermissionDeniedException {
      throw const AppFailure(
        'Location permission was denied. Check app/browser permissions or enter coordinates manually.',
      );
    } on LocationServiceDisabledException {
      throw const AppFailure(
        'Location services are disabled. Enable them or enter coordinates manually.',
      );
    } on MissingPluginException {
      throw const AppFailure(
        'Device location is unavailable on this platform. Enter your store coordinates manually.',
      );
    } on PlatformException {
      throw const AppFailure(
        'Could not obtain device location. Check device/browser settings and retry, or enter coordinates manually.',
      );
    }
  }

  Future<bool> openSettings() async {
    if (kIsWeb) return false;
    try {
      return await _platform.openAppSettings();
    } on UnsupportedError {
      return false;
    }
  }
}
