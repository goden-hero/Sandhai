// Local repository instrumentation, not a cloud/emulator performance test.
// Timing is diagnostic only; assertions cover counts and listener lifecycle.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';

final _epoch = DateTime.utc(2026, 10, 21);

class _Clock extends NearbyClock {
  DateTime value = _epoch;
  @override
  DateTime now() => value;
}

class _Target {
  _Target(this.bound);
  final GeohashBound bound;
  bool active = false;
  late final controller = StreamController<NearbyChanges>(
    sync: true,
    onListen: () => active = true,
    onCancel: () => active = false,
  );
}

class _VendorTarget {
  _VendorTarget({this.cancellationGate});
  final Completer<void>? cancellationGate;
  bool active = false;
  bool cancellationRequested = false;
  late final controller = StreamController<Map<String, dynamic>?>(
    sync: true,
    onListen: () => active = true,
    onCancel: () async {
      cancellationRequested = true;
      if (cancellationGate != null) await cancellationGate!.future;
      active = false;
    },
  );
}

class _Source implements NearbyQuerySource {
  final targets = <_Target>[];
  final vendors = <String, _VendorTarget>{};
  Completer<void>? vendorCancellationGate;
  int initialDocuments = 0;
  int get activeOffers => targets.where((t) => t.active).length;
  int get activeVendors => vendors.values.where((t) => t.active).length;

  @override
  Stream<NearbyChanges> watch(GeohashBound bound) {
    final target = _Target(bound);
    targets.add(target);
    return target.controller.stream;
  }

  @override
  Stream<Map<String, dynamic>?> watchVendor(String uid) {
    final target = _VendorTarget(cancellationGate: vendorCancellationGate);
    vendors[uid] = target;
    return target.controller.stream;
  }

  void seed(List<NearbyDocument> documents) {
    final partitions = <_Target, List<NearbyDocument>>{
      for (final target in targets.where((t) => t.active)) target: [],
    };
    for (final document in documents) {
      for (final partition in partitions.entries) {
        if (partition.key.bound.contains(document.data['geohash'] as String)) {
          partition.value.add(document);
          initialDocuments++;
        }
      }
    }
    for (final partition in partitions.entries) {
      partition.key.controller.add(NearbyChanges(partition.value, const []));
    }
  }

  Future<void> close() async {
    await Future.wait([
      for (final target in targets) target.controller.close(),
      for (final target in vendors.values) target.controller.close(),
    ]);
  }
}

NearbyDocument _offer(
  String id, {
  String vendor = 'store',
  bool legacy = false,
  double lat = 0,
  double lng = 0,
  DateTime? expiry,
  Map<String, dynamic> extra = const {},
}) => NearbyDocument(id, {
  'vendorId': vendor,
  'title': id,
  'description': 'Deterministic local fixture',
  'category': 'groceries',
  'oldPrice': 100.0,
  'newPrice': 50.0,
  'imageUrl': '',
  'latitude': lat,
  'longitude': lng,
  'geohash': StoreLocation(lat, lng).geohash,
  'createdAt': Timestamp.fromDate(_epoch.subtract(const Duration(hours: 1))),
  if (!legacy)
    'locationConfirmedAt': Timestamp.fromDate(
      _epoch.subtract(const Duration(hours: 2)),
    ),
  'expiryTime': Timestamp.fromDate(
    expiry ?? _epoch.add(const Duration(hours: 1)),
  ),
  'status': 'active',
  ...extra,
});

Map<String, dynamic> _vendor() => {
  'latitude': 0.0,
  'longitude': 0.0,
  'geohash': StoreLocation(0, 0).geohash,
  'locationConfirmedAt': Timestamp.fromDate(
    _epoch.subtract(const Duration(hours: 2)),
  ),
};

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void _cleanup(
  _Source source,
  StreamSubscription<List<NearbyOffer>> subscription,
) {
  addTearDown(() async {
    await subscription.cancel();
    await source.close();
  });
}

void main() {
  for (final size in [100, 1000, 10000, 100000]) {
    test(
      'dense $size: query count stays bounded, candidate count does not',
      () async {
        final source = _Source(), clock = _Clock();
        final search = NearbyOfferRepository(
          source: source,
          clock: clock,
        ).search(StoreLocation(0, 0));
        var result = <NearbyOffer>[];
        final subscription = search.stream.listen((value) => result = value);
        _cleanup(source, subscription);
        final documents = [for (var i = 0; i < size; i++) _offer('offer-$i')];
        final initial = Stopwatch()..start();
        source.seed(documents);
        await _flush();
        initial.stop();
        expect(result.length, size);
        expect(source.targets.length, inInclusiveRange(1, 32));
        expect(source.initialDocuments, size, reason: 'Prefixes are disjoint.');
        expect(
          source.activeVendors,
          0,
          reason: 'Markers need no vendor reads.',
        );
        final recheck = Stopwatch()..start();
        search.recheck();
        await _flush();
        recheck.stop();
        final update = Stopwatch()..start();
        final target = source.targets.singleWhere(
          (t) => t.bound.contains(documents.first.data['geohash'] as String),
        );
        target.controller.add(
          NearbyChanges([
            _offer('offer-0', extra: {'title': 'One changed record'}),
          ], const []),
        );
        await _flush();
        update.stop();
        expect(result.first.offer.title, 'One changed record');
        await subscription.cancel();
        expect(source.activeOffers, 0);
        expect(source.activeVendors, 0);
        // Deliberately no wall-clock thresholds: CI/debug hosts vary.
        // ignore: avoid_print
        print(
          jsonEncode({
            'measurement': 'local repository instrumentation; cloud unmeasured',
            'documents': size,
            'offerQueryTargets': source.targets.length,
            'initialCandidateDocuments': source.initialDocuments,
            'initialMicroseconds': initial.elapsedMicroseconds,
            'expiryRecheckMicroseconds': recheck.elapsedMicroseconds,
            'singleRecordUpdateMicroseconds': update.elapsedMicroseconds,
            'activeListenersAfterCancel':
                source.activeOffers + source.activeVendors,
          }),
        );
      },
    );
  }

  test('only potentially visible legacy rows open vendor listeners', () async {
    final source = _Source(), clock = _Clock();
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    var result = <NearbyOffer>[];
    final subscription = search.stream.listen((value) => result = value);
    _cleanup(source, subscription);
    source.seed([
      _offer('confirmed'),
      _offer('legacy', vendor: 'relevant', legacy: true),
      _offer('expired', vendor: 'expired', legacy: true, expiry: _epoch),
      _offer('outside', vendor: 'outside', legacy: true, lat: .04, lng: .04),
      _offer('null', vendor: 'null', extra: {'locationConfirmedAt': null}),
      _offer(
        'malformed',
        vendor: 'malformed',
        legacy: true,
        extra: {'title': 3},
      ),
    ]);
    await _flush();
    expect(source.vendors.keys, ['relevant']);
    expect(source.activeVendors, 1);
    source.vendors['relevant']!.controller.add(_vendor());
    await _flush();
    expect(result.map((v) => v.offer.id).toSet(), {'confirmed', 'legacy'});
    await subscription.cancel();
    expect(source.activeOffers + source.activeVendors, 0);
  });

  test('legacy vendor listeners end when their last offer expires', () async {
    final source = _Source(), clock = _Clock();
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    var result = <NearbyOffer>[];
    final subscription = search.stream.listen((value) => result = value);
    _cleanup(source, subscription);
    source.seed([
      _offer(
        'legacy',
        legacy: true,
        expiry: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);
    source.vendors['store']!.controller.add(_vendor());
    await _flush();
    expect(result, hasLength(1));
    expect(source.activeVendors, 1);
    clock.value = _epoch.add(const Duration(seconds: 1));
    search.recheck();
    await _flush();
    expect(result, isEmpty);
    expect(source.activeVendors, 0);
    await subscription.cancel();
    expect(source.activeOffers, 0);
  });

  test('disposal awaits a retired legacy vendor cancellation', () async {
    final cancellationGate = Completer<void>();
    final source = _Source()..vendorCancellationGate = cancellationGate;
    final clock = _Clock();
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    final subscription = search.stream.listen((_) {});
    addTearDown(() async {
      if (!cancellationGate.isCompleted) cancellationGate.complete();
      await subscription.cancel();
      await source.close();
    });
    source.seed([
      _offer(
        'legacy',
        legacy: true,
        expiry: _epoch.add(const Duration(seconds: 1)),
      ),
    ]);
    final vendor = source.vendors['store']!;
    vendor.controller.add(_vendor());
    await _flush();
    clock.value = _epoch.add(const Duration(seconds: 1));
    search.recheck();
    await _flush();
    expect(vendor.cancellationRequested, isTrue);
    expect(source.activeVendors, 1);
    var disposed = false;
    final disposal = search.dispose().then((_) => disposed = true);
    await _flush();
    expect(
      disposed,
      isFalse,
      reason: 'Retired vendor cancellation still awaits its acknowledgement.',
    );
    cancellationGate.complete();
    await disposal;
    expect(source.activeOffers + source.activeVendors, 0);
  });

  test(
    'query error after success closes offer and legacy vendor targets',
    () async {
      final source = _Source(), clock = _Clock();
      final search = NearbyOfferRepository(
        source: source,
        clock: clock,
      ).search(StoreLocation(0, 0));
      final errors = <Object>[];
      final subscription = search.stream.listen((_) {}, onError: errors.add);
      _cleanup(source, subscription);
      source.seed([_offer('legacy', legacy: true)]);
      source.vendors['store']!.controller.add(_vendor());
      await _flush();
      source.targets.first.controller.addError(StateError('network failed'));
      await _flush();
      expect(errors, hasLength(1));
      expect(source.activeOffers + source.activeVendors, 0);
      await subscription.cancel();
    },
  );
}
