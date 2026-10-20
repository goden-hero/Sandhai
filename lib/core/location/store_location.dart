import '../utils/geohash_utils.dart';

/// A vendor-reviewed store position. Device fixes are suggestions, never consent.
class StoreLocation {
  StoreLocation(this.latitude, this.longitude) {
    if (!GeohashUtils.isValidLocation(latitude, longitude)) {
      throw ArgumentError(
        'Enter finite latitude (-90–90) and longitude (-180–180).',
      );
    }
  }
  final double latitude, longitude;
  String get geohash => GeohashUtils.encode(latitude, longitude);
}
