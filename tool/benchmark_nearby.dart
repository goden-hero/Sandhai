// Deterministic local query/read-volume simulation. No Firebase SDK, network,
// emulator, or billing measurements. Run: dart run tool/benchmark_nearby.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';

void main() {
  const sizes = [100, 1000, 10000, 100000];
  final rows = <Map<String, Object>>[];
  for (final scenario in [
    'city-square-20km',
    'dense-single-store',
    'polar-band',
  ]) {
    final center = scenario == 'polar-band'
        ? StoreLocation(90, 0)
        : StoreLocation(13.0276441, 77.6129353);
    final bounds = NearbyGeometry.bounds(center);
    for (final size in sizes) {
      final random = math.Random(41021);
      var candidates = 0, included = 0, matches = 0;
      final watch = Stopwatch()..start();
      for (var i = 0; i < size; i++) {
        final point = switch (scenario) {
          'dense-single-store' => center,
          'polar-band' => StoreLocation(
            80 + 10 * random.nextDouble(),
            -180 + 360 * random.nextDouble(),
          ),
          _ => StoreLocation(
            center.latitude + (random.nextDouble() - .5) * 20000 / 111195,
            center.longitude +
                (random.nextDouble() - .5) *
                    20000 /
                    (111195 * math.cos(center.latitude * math.pi / 180)),
          ),
        };
        final hash = point.geohash;
        final count = bounds.where((bound) => bound.contains(hash)).length;
        matches += count;
        if (count > 0) candidates++;
        if (NearbyGeometry.distance(center, point) <=
            NearbyGeometry.radiusMetres) {
          included++;
          if (count == 0) throw StateError('Coverage gap in $scenario: $i');
        }
      }
      watch.stop();
      rows.add({
        'scenario': scenario,
        'generatedActiveDocuments': size,
        'offerQueryTargets': bounds.length,
        'queryPrefixPrecision': bounds.first.start.length,
        'simulatedInitialOfferDocuments': matches,
        'uniqueCandidates': candidates,
        'duplicateCandidateMatches': matches - candidates,
        'includedWithin5000m': included,
        'falsePositiveCandidates': candidates - included,
        // Before the Phase 4.1 fix, one missing-marker record per distinct
        // vendor opens one extra listener, including excluded candidates.
        'preFixLegacyVendorTargetWorstCase': candidates,
        'relevantLegacyVendorTargetWorstCase': included,
        'localSimulationMicroseconds': watch.elapsedMicroseconds,
      });
    }
  }
  // ignore: avoid_print
  print(
    const JsonEncoder.withIndent('  ').convert({
      'measurement': 'deterministic local geometry simulation',
      'seed': 41021,
      'assumptions': [
        'All generated documents have active status and canonical stored hashes.',
        'City-square points span a 20 km square; polar points span 80–90 N.',
        'Dense-store points share one coordinate; IDs are distinct.',
        'Each matching document counts once per disjoint prefix target.',
        'Expiry, schema and server billing rules are not modeled.',
        'Cloud latency, index readiness, billed reads and SDK memory are unmeasured.',
      ],
      'rows': rows,
    }),
  );
}
