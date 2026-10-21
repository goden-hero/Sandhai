/// Deterministic Geohash Utility for 5KM Sandhai Hyperlocal Clearance Marketplace.
///
/// Converts geographic coordinates (latitude, longitude) into base32 geohashes
/// for spatial indexing and 5KM geofenced offer discovery in Cloud Firestore.
class GeohashUtils {
  static const String _base32Chars = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Stored coordinate precision; query bounds use a separate adaptive precision.
  /// Precision 6 corresponds to a bounding box of roughly 1.2 km x 0.6 km,
  /// Radius coverage is calculated by NearbyGeometry, never by nine such cells.
  static const int defaultPrecision = 6;

  /// Encodes latitude and longitude into a deterministic base32 geohash.
  ///
  /// Throws [ArgumentError] if coordinates or precision are out of valid bounds.
  static String encode(
    double latitude,
    double longitude, {
    int precision = defaultPrecision,
  }) {
    if (!latitude.isFinite || latitude < -90.0 || latitude > 90.0) {
      throw ArgumentError(
        'Latitude must be between -90.0 and 90.0 degrees, got: $latitude',
      );
    }
    if (!longitude.isFinite || longitude < -180.0 || longitude > 180.0) {
      throw ArgumentError(
        'Longitude must be between -180.0 and 180.0 degrees, got: $longitude',
      );
    }
    if (precision <= 0 || precision > 12) {
      throw ArgumentError(
        'Geohash precision must be between 1 and 12 characters, got: $precision',
      );
    }

    double minLat = -90.0;
    double maxLat = 90.0;
    double minLng = -180.0;
    double maxLng = 180.0;

    final buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (minLng + maxLng) / 2.0;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2.0;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32Chars[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  /// Checks if latitude and longitude are valid non-null coordinates.
  ///
  /// Rejects missing/nonfinite/out-of-bound values. Confirmation is separate;
  /// an explicitly reviewed (0,0) position is valid.
  static bool isValidLocation(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }
}
