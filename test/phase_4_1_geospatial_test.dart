import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/core/utils/geohash_utils.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';

import 'support/fakes.dart';
import 'support/nearby_fakes.dart';

const _earthRadius = 6371000.0;
final _epoch = DateTime.utc(2026, 10, 21);

class _FixedClock extends NearbyClock {
  @override
  DateTime now() => _epoch;
}

// Rotate a 3-D unit vector in its local tangent plane. This remains defined at
// both poles and uses neither the production Haversine nor its cap rectangle.
StoreLocation _project(StoreLocation center, double metres, double bearing) {
  final lat = center.latitude * math.pi / 180;
  final lng = center.longitude * math.pi / 180;
  final angle = metres / _earthRadius;
  final azimuth = bearing * math.pi / 180;
  final north = math.cos(azimuth) * math.sin(angle);
  final east = math.sin(azimuth) * math.sin(angle);
  final radial = math.cos(angle);
  final x =
      math.cos(lat) * math.cos(lng) * radial -
      math.sin(lat) * math.cos(lng) * north -
      math.sin(lng) * east;
  final y =
      math.cos(lat) * math.sin(lng) * radial -
      math.sin(lat) * math.sin(lng) * north +
      math.cos(lng) * east;
  final z = math.sin(lat) * radial + math.cos(lat) * north;
  return StoreLocation(
    math.atan2(z, math.sqrt(x * x + y * y)) * 180 / math.pi,
    math.atan2(y, x) * 180 / math.pi,
  );
}

NearbyDocument _offer(
  String id,
  StoreLocation point, {
  Map<String, dynamic> overrides = const {},
}) => NearbyDocument(id, {
  'vendorId': 'vendor',
  'title': id,
  'description': 'Independent geospatial regression fixture',
  'oldPrice': 100,
  'newPrice': 50,
  'imageUrl': '',
  'latitude': point.latitude,
  'longitude': point.longitude,
  'geohash': point.geohash,
  'createdAt': Timestamp.fromDate(_epoch.subtract(const Duration(hours: 1))),
  'expiryTime': Timestamp.fromDate(_epoch.add(const Duration(hours: 1))),
  'status': 'active',
  'locationConfirmedAt': Timestamp.fromDate(
    _epoch.subtract(const Duration(hours: 2)),
  ),
  ...overrides,
});

void main() {
  test('cap coverage survives polar transitions, dateline and cell edges', () {
    const polarTransition = 90 - 5000 / _earthRadius * 180 / math.pi;
    final latitudes = [
      -90.0,
      -polarTransition - 1e-8,
      -polarTransition + 1e-8,
      -80.0,
      -45.0,
      -1e-12,
      0.0,
      1e-12,
      13.0276441,
      45.0,
      80.0,
      polarTransition - 1e-8,
      polarTransition + 1e-8,
      90.0,
    ];
    final longitudes = [
      -180.0,
      -179.999999,
      -90.0,
      0.0,
      90.0,
      179.999999,
      180.0,
    ];
    for (final latitude in latitudes) {
      for (final longitude in longitudes) {
        final center = StoreLocation(latitude, longitude);
        final bounds = NearbyGeometry.bounds(center);
        expect(bounds.length, inInclusiveRange(1, 32));
        expect(bounds.map((b) => b.start).toSet().length, bounds.length);
        for (final bound in bounds) {
          expect(
            bound.start,
            matches(RegExp(r'^[0-9bcdefghjkmnpqrstuvwxyz]{1,6}$')),
          );
          expect(bound.end, '${bound.start}~');
        }
        for (var bearing = 0; bearing < 360; bearing += 5) {
          for (final metres in [0.0, 2500.0, 5000.0]) {
            final target = _project(center, metres, bearing.toDouble());
            expect(
              bounds.any((bound) => bound.contains(target.geohash)),
              isTrue,
              reason:
                  'center=($latitude,$longitude), bearing=$bearing, '
                  'metres=$metres, target=${target.geohash}',
            );
          }
        }
      }
    }
  });

  test('six-character cell corners on either side of binary splits are covered', () {
    // Precision-6 longitude/latitude cell sizes are 360/32768 and 180/32768.
    // The small perturbations exercise both sides of each exact cell boundary.
    for (final row in [0, 1, 16383, 16384, 16385, 32767, 32768]) {
      for (final col in [0, 1, 16383, 16384, 16385, 32767, 32768]) {
        for (final epsilon in [-1e-11, 0.0, 1e-11]) {
          final lat = (-90 + row * 180 / 32768 + epsilon).clamp(-90.0, 90.0);
          final lng = (-180 + col * 360 / 32768 + epsilon).clamp(-180.0, 180.0);
          final center = StoreLocation(lat, lng);
          final bounds = NearbyGeometry.bounds(center);
          for (final bearing in [
            0.0,
            45.0,
            90.0,
            135.0,
            180.0,
            225.0,
            270.0,
            315.0,
          ]) {
            final target = _project(center, 5000, bearing);
            expect(
              bounds.any((b) => b.contains(target.geohash)),
              isTrue,
              reason: 'row=$row, col=$col, epsilon=$epsilon, bearing=$bearing',
            );
          }
        }
      }
    }
  });

  test(
    'distance handles pole, dateline and antipodal coordinates finitely',
    () {
      for (final center in [
        StoreLocation(-90, -180),
        StoreLocation(-89.99, 179.99),
        StoreLocation(0, 180),
        StoreLocation(89.99, -179.99),
        StoreLocation(90, 180),
      ]) {
        for (final bearing in [0.0, 65.0, 90.0, 180.0, 270.0]) {
          for (final metres in [0.0, 4999.999, 5000.0, 5000.001, 10000.0]) {
            final target = _project(center, metres, bearing);
            final distance = NearbyGeometry.distance(center, target);
            expect(distance.isFinite, isTrue);
            expect(distance, closeTo(metres, 1e-6));
            expect(
              NearbyGeometry.distance(target, center),
              closeTo(distance, 1e-6),
            );
          }
        }
      }
      expect(
        NearbyGeometry.distance(StoreLocation(0, -180), StoreLocation(0, 180)),
        closeTo(0, 1e-8),
      );
      expect(
        NearbyGeometry.distance(StoreLocation(0, 0), StoreLocation(0, 180)),
        closeTo(math.pi * _earthRadius, 1e-6),
      );
    },
  );

  test(
    'invalid coordinates and precision fail before hashing or searching',
    () {
      for (final invalid in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -90.000001,
        90.000001,
      ]) {
        expect(GeohashUtils.isValidLocation(invalid, 0), isFalse);
        expect(() => StoreLocation(invalid, 0), throwsArgumentError);
        expect(() => GeohashUtils.encode(invalid, 0), throwsArgumentError);
      }
      for (final invalid in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -180.000001,
        180.000001,
      ]) {
        expect(GeohashUtils.isValidLocation(0, invalid), isFalse);
        expect(() => StoreLocation(0, invalid), throwsArgumentError);
        expect(() => GeohashUtils.encode(0, invalid), throwsArgumentError);
      }
      expect(GeohashUtils.isValidLocation(null, 0), isFalse);
      expect(GeohashUtils.isValidLocation(0, null), isFalse);
      for (final precision in [-1, 0, 13]) {
        expect(
          () => GeohashUtils.encode(0, 0, precision: precision),
          throwsArgumentError,
        );
      }
      for (final lat in [-90.0, 0.0, 90.0]) {
        for (final lng in [-180.0, 0.0, 180.0]) {
          expect(StoreLocation(lat, lng).geohash.length, 6);
        }
      }
    },
  );

  test(
    'raw 5 km inclusion distinguishes points separated by one millimetre',
    () async {
      final source = TestNearbySource();
      final center = StoreLocation(0, 0);
      final search = NearbyOfferRepository(
        source: source,
        clock: _FixedClock(),
      ).search(center);
      List<NearbyOffer> result = [];
      final sub = search.stream.listen((value) => result = value);
      addTearDown(sub.cancel);
      source.seed([
        _offer(
          'inside',
          StoreLocation(4999.999 * 180 / (_earthRadius * math.pi), 0),
        ),
        _offer('edge', StoreLocation(0.044966080295936524, 0)),
        _offer(
          'outside',
          StoreLocation(5000.001 * 180 / (_earthRadius * math.pi), 0),
        ),
      ]);
      await settleSession();
      expect(result.map((v) => v.offer.id), ['inside', 'edge']);
      expect(result.last.distanceMetres, lessThanOrEqualTo(5000));
      expect(result.last.distanceMetres, closeTo(5000, 1e-8));
    },
  );

  test(
    'polar coarse candidates and dateline candidates still use exact distance',
    () async {
      for (final center in [
        StoreLocation(90, 180),
        StoreLocation(0, 179.999),
      ]) {
        final source = TestNearbySource();
        final search = NearbyOfferRepository(
          source: source,
          clock: _FixedClock(),
        ).search(center);
        List<NearbyOffer> result = [];
        final sub = search.stream.listen((value) => result = value);
        try {
          final inside = _project(center, 4999, 90);
          final outside = _project(center, 5001, 90);
          expect(
            source.probes.any((p) => p.bound.contains(outside.geohash)),
            isTrue,
          );
          source.seed([_offer('inside', inside), _offer('outside', outside)]);
          await settleSession();
          expect(result.map((v) => v.offer.id), ['inside']);
        } finally {
          await sub.cancel();
        }
      }
    },
  );

  test('decoder rejects invalid hashes/coordinates while preserving flat schema', () async {
    final source = TestNearbySource();
    final center = StoreLocation(0, 0);
    final search = NearbyOfferRepository(
      source: source,
      clock: _FixedClock(),
    ).search(center);
    List<NearbyOffer> result = [];
    final sub = search.stream.listen((value) => result = value);
    addTearDown(sub.cancel);
    source.seed([]);
    final malformed = <NearbyDocument>[
      for (final hash in [
        null,
        '',
        's0000',
        's000000',
        'S00000',
        's0000!',
        's00001',
        123,
      ])
        _offer('hash-$hash', center, overrides: {'geohash': hash}),
      for (final lat in [
        null,
        '0',
        double.nan,
        double.infinity,
        -90.001,
        90.001,
      ])
        _offer('lat-$lat', center, overrides: {'latitude': lat}),
      for (final lng in [
        null,
        '0',
        double.nan,
        double.negativeInfinity,
        -180.001,
        180.001,
      ])
        _offer('lng-$lng', center, overrides: {'longitude': lng}),
      _offer('bad-expiry', center, overrides: {'expiryTime': 'tomorrow'}),
      _offer(
        'bad-confirmation',
        center,
        overrides: {'locationConfirmedAt': 'reviewed'},
      ),
    ];
    // Inject directly: malformed hashes may never match a real Firestore query,
    // but the boundary decoder must remain safe for all untrusted snapshots.
    source.probes.first.add([
      _offer('valid-flat-schema', center, overrides: {'category': null}),
      ...malformed,
    ]);
    await settleSession();
    expect(result.map((v) => v.offer.id), ['valid-flat-schema']);
    expect(result.single.offer.category, 'other');
    expect(result.single.offer.latitude, 0);
    expect(
      result.single.offer.expiryTime.toUtc(),
      _epoch.add(const Duration(hours: 1)),
    );
    expect(result.single.offer.toFirestore().containsKey('expiresAt'), isFalse);
    expect(source.vendorStreams, isEmpty);
  });
}
