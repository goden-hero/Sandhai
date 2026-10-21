import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/customer/nearby_feed_controller.dart';

import 'support/fakes.dart';
import 'support/nearby_fakes.dart';

final epoch = DateTime.utc(2026, 10, 20);
NearbyDocument offer(
  String id, {
  double lat = 0,
  double lng = 0,
  DateTime? expiry,
  Map<String, dynamic> extra = const {},
}) => NearbyDocument(id, {
  'vendorId': 'vendor',
  'title': id,
  'description': 'Fixture',
  'category': 'groceries',
  'oldPrice': 100.0,
  'newPrice': 50.0,
  'imageUrl': '',
  'latitude': lat,
  'longitude': lng,
  'geohash': StoreLocation(lat, lng).geohash,
  'createdAt': Timestamp.fromDate(epoch.subtract(const Duration(hours: 1))),
  'locationConfirmedAt': Timestamp.fromDate(
    epoch.subtract(const Duration(hours: 2)),
  ),
  'expiryTime': Timestamp.fromDate(
    expiry ?? epoch.add(const Duration(hours: 1)),
  ),
  'status': 'active',
  ...extra,
});

class FixedClock extends NearbyClock {
  FixedClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

// Independent great-circle destination formula, not the implementation's bounds
// or distance calculation. Distances are specified in metres before projection.
StoreLocation destination(StoreLocation c, double metres, double bearing) {
  final delta = metres / 6371000, b = bearing * math.pi / 180;
  final a = c.latitude * math.pi / 180, o = c.longitude * math.pi / 180;
  final y = math.asin(
    math.sin(a) * math.cos(delta) + math.cos(a) * math.sin(delta) * math.cos(b),
  );
  final x =
      o +
      math.atan2(
        math.sin(b) * math.sin(delta) * math.cos(a),
        math.cos(delta) - math.sin(a) * math.sin(y),
      );
  return StoreLocation(
    y * 180 / math.pi,
    (x * 180 / math.pi + 540) % 360 - 180,
  );
}

void main() {
  test('acknowledged snapshots survive cache/pending transitions and cancel while quiet', () async {
    var active = 0;
    final raw = StreamController<NearbySnapshot>();
    final values = <NearbyChanges>[];
    final stream = acknowledgedNearbyChanges(
      trackSubscription(raw.stream, (delta) => active += delta),
    );
    final subscription = stream.listen(values.add);
    final a = offer('a');
    raw.add(NearbySnapshot([a], fromCache: true));
    await settleSession();
    expect(values.single.confirmed, isFalse);
    expect(values.single.upserts, isEmpty);
    raw.add(NearbySnapshot([a]));
    await settleSession();
    expect(values.last.upserts.single.id, 'a');
    raw.add(
      NearbySnapshot([
        offer('a', extra: {'title': 'Changed'}),
      ], pending: true),
    );
    raw.add(
      NearbySnapshot([
        offer('a', extra: {'title': 'Changed'}),
      ]),
    );
    await settleSession();
    expect(values.last.upserts.single.data['title'], 'Changed');
    raw.add(const NearbySnapshot([]));
    await settleSession();
    expect(values.last.removed, ['a']);
    // No next event is delivered to unblock cancellation.
    await subscription.cancel().timeout(const Duration(seconds: 1));
    expect(active, 0);
    await raw.close();
  });
  test(
    'radius-derived coverage across boundaries, bearings, dateline and poles',
    () {
      for (final center in [
        StoreLocation(0, 0),
        StoreLocation(13.0276441, 77.6129353),
        StoreLocation(55, 179.999),
        StoreLocation(-89.99, -179.99),
        StoreLocation(90, 180),
      ]) {
        final bounds = NearbyGeometry.bounds(center);
        expect(bounds.length, inInclusiveRange(1, 32));
        for (var bearing = 0; bearing < 360; bearing += 3) {
          for (final metres in [0.0, 2495.0, 4990.0, 5000.0]) {
            final p = destination(center, metres, bearing.toDouble());
            expect(
              bounds.any((b) => b.contains(p.geohash)),
              isTrue,
              reason: '${center.latitude} $bearing $metres ${p.geohash}',
            );
          }
        }
      }
    },
  );
  test('independent 4.99/5.00/5.01 km fixtures: include/include/exclude without rounding', () async {
    final source = TestNearbySource(), clock = FixedClock(epoch);
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    List<NearbyOffer> result = [];
    final sub = search.stream.listen((v) => result = v);
    // Northward radians -> degrees computed independently with Python decimal:
    // metres * 180 / (6371000 * pi), stored to double precision.
    source.seed([
      offer('4990', lat: 0.044876148135344655),
      offer('5000', lat: 0.044966080295936524),
      offer('5010', lat: 0.045056012456528396),
    ]);
    await settleSession();
    expect(result.map((v) => v.offer.id), ['4990', '5000']);
    expect(result.last.distanceMetres, lessThanOrEqualTo(5000));
    expect(result.last.distanceMetres, closeTo(5000, 1e-9));
    await sub.cancel();
    expect(source.active, 0);
  });
  test('dedup, updates, removals, inactive/expired and malformed legacy records', () async {
    final source = TestNearbySource();
    final search = NearbyOfferRepository(
      source: source,
      clock: FixedClock(epoch),
    ).search(StoreLocation(0, 0));
    List<NearbyOffer> result = [];
    final sub = search.stream.listen((v) => result = v);
    source.seed([
      offer('b'),
      offer('a'),
      offer('expired', expiry: epoch),
      offer('draft', extra: {'status': 'draft'}),
      offer('nan', extra: {'latitude': double.nan}),
      offer('broken', extra: {'expiryTime': 'tomorrow'}),
      offer('hash', extra: {'geohash': 's00001'}),
      offer(
        'bad uid',
        extra: {'vendorId': 'bad/id', 'locationConfirmedAt': null},
      ),
      offer('badprice', extra: {'newPrice': double.infinity}),
      offer('badimage', extra: {'imageSize': 'large'}),
    ]);
    await settleSession();
    expect(result.map((v) => v.offer.id), ['a', 'b']);
    // Deliberately overlapping callbacks exercise dedup independent of planner.
    source.probes.first.add([
      offer('a', extra: {'title': 'Latest'}),
    ]);
    await settleSession();
    expect(result.where((v) => v.offer.id == 'a').length, 1);
    expect(result.first.offer.title, 'Latest');
    source.probes.first.add([offer('a', lat: 1)]);
    await settleSession();
    expect(result.map((v) => v.offer.id), ['b']);
    source.probes
        .firstWhere((p) => p.bound.contains(StoreLocation(0, 0).geohash))
        .add([], ['b']);
    await settleSession();
    expect(result, isEmpty);
    await sub.cancel();
  });
  test('new-bound update survives old-bound removal; deleted overlap cannot resurrect', () async {
    final source = TestNearbySource();
    final search = NearbyOfferRepository(
      source: source,
      clock: FixedClock(epoch),
    ).search(StoreLocation(0, 0));
    List<NearbyOffer> result = [];
    final sub = search.stream.listen((v) => result = v);
    source.seed([offer('move', lat: -.001, lng: -.001)]);
    await settleSession();
    final old = source.probes.firstWhere(
      (p) => p.bound.contains(StoreLocation(-.001, -.001).geohash),
    );
    final next = source.probes.firstWhere(
      (p) => p.bound.contains(StoreLocation(.001, .001).geohash),
    );
    expect(identical(old, next), isFalse);
    next.add([offer('move', lat: .001, lng: .001)]);
    old.add([], ['move']);
    await settleSession();
    expect(result.single.offer.latitude, .001);
    next.add([], ['move']);
    await settleSession();
    expect(result, isEmpty);
    await sub.cancel();
  });
  test('legacy locations require confirmation before publication and matching snapshot', () async {
    final source = TestNearbySource();
    final search = NearbyOfferRepository(
      source: source,
      clock: FixedClock(epoch),
    ).search(StoreLocation(0, 0));
    List<NearbyOffer>? result;
    final sub = search.stream.listen((v) => result = v);
    source.seed([
      offer('legacy', extra: {'locationConfirmedAt': null, 'category': null}),
    ]);
    await settleSession();
    expect(result, isEmpty);
    expect(source.vendorStreams, isEmpty);
    final d = offer('legacy').data..remove('locationConfirmedAt');
    source.seed([NearbyDocument('legacy', d)]);
    await settleSession();
    source.vendorStreams['vendor']!.add({
      'latitude': 0.0,
      'longitude': 0.0,
      'geohash': StoreLocation(0, 0).geohash,
      'locationConfirmedAt': Timestamp.fromDate(
        epoch.subtract(const Duration(hours: 2)),
      ),
    });
    await settleSession();
    expect(result!.single.offer.id, 'legacy');
    source.vendorStreams['vendor']!.add({
      'latitude': 0.0,
      'longitude': 0.0,
      'geohash': StoreLocation(0, 0).geohash,
      'locationConfirmedAt': Timestamp.fromDate(epoch),
    });
    await settleSession();
    expect(result, isEmpty);
    await sub.cancel();
  });
  test(
    'expiry fires without a new query event, and resume rechecks wall clock',
    () {
      fakeAsync((async) {
        final source = TestNearbySource(), clock = FixedClock(epoch);
        final search = NearbyOfferRepository(
          source: source,
          clock: clock,
        ).search(StoreLocation(0, 0));
        List<NearbyOffer> result = [];
        final sub = search.stream.listen((v) => result = v);
        source.seed([
          offer('short', expiry: epoch.add(const Duration(seconds: 2))),
          offer('long'),
        ]);
        async.flushMicrotasks();
        expect(result.length, 2);
        clock.value = epoch.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        expect(result.map((v) => v.offer.id), ['long']);
        clock.value = epoch.add(const Duration(hours: 3));
        search.recheck();
        async.flushMicrotasks();
        expect(result, isEmpty);
        sub.cancel();
        async.flushMicrotasks();
        expect(async.nonPeriodicTimerCount, 0);
      });
    },
  );
  test('a query failure is an error, cancels all bounds, and never becomes empty success', () async {
    final source = TestNearbySource();
    final errors = <Object>[];
    final search = NearbyOfferRepository(
      source: source,
      clock: FixedClock(epoch),
    ).search(StoreLocation(0, 0));
    final sub = search.stream.listen(
      (v) => fail('No successful result expected'),
      onError: errors.add,
    );
    source.probes.first.stream.addError(const AppFailure('permission-denied'));
    await settleSession();
    expect(errors.length, 1);
    expect(source.active, 0);
    await sub.cancel();
  });
  test('initial unconfirmed server results time out visibly', () {
    fakeAsync((async) {
      final source = TestNearbySource();
      final errors = <Object>[];
      final search = NearbyOfferRepository(
        source: source,
        clock: FixedClock(epoch),
      ).search(StoreLocation(0, 0));
      search.stream.listen(
        (_) => fail('Not an empty success'),
        onError: errors.add,
      );
      async.elapse(const Duration(seconds: 25));
      async.flushMicrotasks();
      expect(errors.single.toString(), contains('server did not confirm'));
      expect(source.active, 0);
    });
  });
  test('location changes, query retry, account switching and dispose cancel old work', () async {
    final accounts = TestAccounts(),
        source = TestNearbySource(),
        location = TestCustomerLocation();
    final auth = AuthService(repository: accounts)..start();
    await settleSession();
    await auth.registerCustomer(
      displayName: 'Customer A',
      email: 'customer-a@test.com',
      password: 'password',
    );
    await settleSession();
    final controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(
        source: source,
        clock: FixedClock(epoch),
      ),
      location: location,
    );
    final first = controller.locate();
    await settleSession();
    source.seed([offer('a')]);
    await first;
    expect(controller.offers.single.offer.id, 'a');
    final count = source.active;
    final obsolete = source.probes.first;
    final refresh = controller.refresh();
    await settleSession();
    expect(source.active, count);
    source.seed([]);
    await refresh;
    source.probes.last.stream.addError(const AppFailure('denied'));
    await settleSession();
    expect(controller.phase, NearbyPhase.queryError);
    final retry = controller.refresh();
    await settleSession();
    source.seed([offer('b')]);
    await retry;
    expect(controller.offers.single.offer.id, 'b');
    obsolete.staleCallback!(NearbyChanges([offer('stale')], []));
    await settleSession();
    expect(controller.offers.single.offer.id, 'b');
    location.result = StoreLocation(1, 1);
    final moved = controller.locate();
    await settleSession();
    source.seed([offer('new center', lat: 1, lng: 1)]);
    await moved;
    expect(controller.center!.latitude, 1);
    expect(controller.offers.single.offer.id, 'new center');
    expect(source.active, lessThanOrEqualTo(32));
    location.gate = Completer();
    final locating = controller.locate();
    await settleSession();
    expect(source.active, 0);
    await auth.signOut();
    await settleSession();
    location.gate!.complete(StoreLocation(1, 1));
    await locating;
    expect(controller.center, isNull);
    expect(controller.offers, isEmpty);
    expect(source.active, 0);
    await auth.registerCustomer(
      displayName: 'Customer B',
      email: 'customer-b@test.com',
      password: 'password',
    );
    await settleSession();
    expect(controller.phase, NearbyPhase.locationRequired);
    controller.dispose();
    obsolete.staleCallback!(NearbyChanges([offer('after dispose')], []));
    expect(controller.offers, isEmpty);
    auth.dispose();
  });
}
