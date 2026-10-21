import 'dart:math' as math;

import '../utils/geohash_utils.dart';
import 'store_location.dart';

class GeohashBound {
  const GeohashBound(this.start, this.end);
  final String start, end;
  bool contains(String hash) =>
      hash.compareTo(start) >= 0 && hash.compareTo(end) <= 0;
}

/// Spherical distances use a mean Earth radius of 6,371,000 metres.
/// Bounds cover the *whole spherical cap's bounding rectangle*, including poles
/// and antimeridian crossings. Precision adapts until at most 32 cells cover it;
/// it is unrelated to the six-character precision used to store locations.
class NearbyGeometry {
  static const radiusMetres = 5000.0;
  static const earthRadiusMetres = 6371000.0;
  static double distance(StoreLocation a, StoreLocation b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        (math.pow(math.sin(dLat / 2), 2) +
                math.cos(lat1) *
                    math.cos(lat2) *
                    math.pow(math.sin(dLng / 2), 2))
            .clamp(0.0, 1.0);
    return 2 * earthRadiusMetres * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static List<GeohashBound> bounds(StoreLocation center) {
    const angle = radiusMetres / earthRadiusMetres;
    final lat = center.latitude * math.pi / 180;
    // Padding affects coverage only, never the exact distance predicate.
    final south = math.max(-90.0, (lat - angle) * 180 / math.pi - 1e-10);
    final north = math.min(90.0, (lat + angle) * 180 / math.pi + 1e-10);
    final polar = south <= -90 || north >= 90;
    final delta = polar
        ? 180.0
        : math.asin(math.sin(angle) / math.cos(lat)) * 180 / math.pi + 1e-10;
    final west = center.longitude - delta, east = center.longitude + delta;
    final intervals = polar
        ? <(double, double)>[(-180, 180)]
        : west < -180
        ? <(double, double)>[(west + 360, 180), (-180, east)]
        : east > 180
        ? <(double, double)>[(west, 180), (-180, east - 360)]
        : <(double, double)>[(west, east)];
    for (var precision = 6; precision >= 1; precision--) {
      final lngCells = 1 << ((precision * 5 + 1) ~/ 2);
      final latCells = 1 << (precision * 5 ~/ 2);
      int row(double v) =>
          (((v + 90) / 180 * latCells).floor()).clamp(0, latCells - 1);
      int col(double v) =>
          (((v + 180) / 360 * lngCells).floor()).clamp(0, lngCells - 1);
      final firstRow = row(south), lastRow = row(north);
      final count =
          intervals.fold<int>(0, (n, i) => n + col(i.$2) - col(i.$1) + 1) *
          (lastRow - firstRow + 1);
      if (count > 32 && precision > 1) continue;
      final prefixes = <String>{};
      for (final interval in intervals) {
        for (var x = col(interval.$1); x <= col(interval.$2); x++) {
          for (var y = firstRow; y <= lastRow; y++) {
            prefixes.add(
              GeohashUtils.encode(
                (y + .5) * 180 / latCells - 90,
                (x + .5) * 360 / lngCells - 180,
                precision: precision,
              ),
            );
          }
        }
      }
      return (prefixes.toList()..sort())
          .map((p) => GeohashBound(p, '$p~'))
          .toList();
    }
    throw StateError('No geohash coverage');
  }
}
