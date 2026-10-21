import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/core/location/location_service.dart';
import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_offer_repository.dart';
import 'package:sandhai/data/nearby_query_source.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/customer/nearby_feed_controller.dart';

import 'support/fakes.dart';

final lifecycleEpoch = DateTime.utc(2030, 1, 1);

NearbyDocument lifecycleOffer(
  String id, {
  StoreLocation? at,
  Duration lifetime = const Duration(hours: 1),
  bool legacy = false,
}) {
  final location = at ?? StoreLocation(0, 0);
  return NearbyDocument(id, {
    'vendorId': 'lifecycle-vendor',
    'title': id,
    'description': 'Lifecycle fixture',
    'category': 'groceries',
    'oldPrice': 100.0,
    'newPrice': 50.0,
    'imageUrl': '',
    'latitude': location.latitude,
    'longitude': location.longitude,
    'geohash': location.geohash,
    'createdAt': Timestamp.fromDate(
      lifecycleEpoch.subtract(const Duration(hours: 1)),
    ),
    if (!legacy)
      'locationConfirmedAt': Timestamp.fromDate(
        lifecycleEpoch.subtract(const Duration(hours: 2)),
      ),
    'expiryTime': Timestamp.fromDate(lifecycleEpoch.add(lifetime)),
    'status': 'active',
  });
}

class LifecycleClock extends NearbyClock {
  LifecycleClock({this.manual = false});
  final bool manual;
  DateTime value = lifecycleEpoch;
  final timers = <Timer>[];
  int get activeTimers => timers.where((timer) => timer.isActive).length;
  @override
  DateTime now() => value;
  @override
  Timer schedule(Duration delay, void Function() callback) {
    final timer = manual
        ? _ManualLifecycleTimer(value.add(delay), callback)
        : super.schedule(delay, callback);
    timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    assert(manual);
    final target = value.add(duration);
    while (true) {
      final due =
          timers
              .whereType<_ManualLifecycleTimer>()
              .where((timer) => timer.isActive && !timer.due.isAfter(target))
              .toList()
            ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      value = due.first.due;
      due.first.fire();
    }
    value = target;
  }
}

class _ManualLifecycleTimer implements Timer {
  _ManualLifecycleTimer(this.due, this.callback);
  final DateTime due;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

class LifecycleProbe<T> {
  LifecycleProbe(this.onActivity);
  final void Function() onActivity;
  bool active = false, cancellationRequested = false;
  Completer<void>? cancellationGate;
  void Function(T)? staleData;
  Function? staleError;
  late final controller = StreamController<T>(
    sync: true,
    onListen: () {
      active = true;
      onActivity();
    },
    onCancel: () async {
      cancellationRequested = true;
      await cancellationGate?.future;
      active = false;
      onActivity();
    },
  );
  Stream<T> get stream =>
      _CapturedLifecycleStream<T>(controller.stream, (data, error) {
        staleData = data;
        staleError = error;
      });
  void add(T value) => controller.add(value);
  void fail(Object error) => controller.addError(error, StackTrace.current);
  void deliverLateError(Object error) =>
      Function.apply(staleError!, [error, StackTrace.current]);
}

class _CapturedLifecycleStream<T> extends Stream<T> {
  _CapturedLifecycleStream(this.source, this.capture);
  final Stream<T> source;
  final void Function(void Function(T)?, Function?) capture;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    capture(onData, onError);
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class LifecycleBoundProbe extends LifecycleProbe<NearbyChanges> {
  LifecycleBoundProbe(this.bound, super.onActivity);
  final GeohashBound bound;
}

/// Active means the underlying subscription has acknowledged cancellation, not
/// merely that the consumer called cancel(). Late callbacks bypass stream safety.
class LifecycleSource implements NearbyQuerySource {
  final probes = <LifecycleBoundProbe>[];
  final vendorProbes = <LifecycleProbe<Map<String, dynamic>?>>[];
  int watchCalls = 0, maxActive = 0;
  int? throwOnWatch;
  bool throwOnVendor = false;
  int get active => probes.where((probe) => probe.active).length;
  int get activeVendors => vendorProbes.where((probe) => probe.active).length;
  void _activity() {
    if (active > maxActive) maxActive = active;
  }

  @override
  Stream<NearbyChanges> watch(GeohashBound bound) {
    watchCalls++;
    if (watchCalls == throwOnWatch) {
      throw const AppFailure('Synchronous query setup failed');
    }
    final probe = LifecycleBoundProbe(bound, _activity);
    probes.add(probe);
    return probe.stream;
  }

  @override
  Stream<Map<String, dynamic>?> watchVendor(String uid) {
    if (throwOnVendor) {
      throw const AppFailure('Synchronous vendor setup failed');
    }
    final probe = LifecycleProbe<Map<String, dynamic>?>(() {});
    vendorProbes.add(probe);
    return probe.stream;
  }

  void seed(List<NearbyDocument> documents) {
    for (final probe in probes.where(
      (probe) => probe.active && !probe.cancellationRequested,
    )) {
      probe.add(
        NearbyChanges([
          for (final document in documents)
            if (probe.bound.contains(document.data['geohash'] as String))
              document,
        ], const []),
      );
    }
  }
}

class LifecycleLocation extends LocationService {
  final requests = <Completer<StoreLocation>>[];
  bool automatic = true;
  StoreLocation result = StoreLocation(0, 0);
  @override
  Future<StoreLocation> suggest() {
    final request = Completer<StoreLocation>();
    requests.add(request);
    if (automatic) request.complete(result);
    return request.future;
  }
}

Future<AuthService> lifecycleAuth() async {
  final auth = AuthService(repository: TestAccounts())..start();
  await auth.registerCustomer(
    email: 'lifecycle-a@example.test',
    password: 'password',
    displayName: 'Lifecycle A',
  );
  await settleSession();
  return auth;
}

void main() {
  test('synchronous bound setup failure reports an error and tears down earlier bounds', () async {
    final source = LifecycleSource()..throwOnWatch = 2;
    final clock = LifecycleClock();
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    final escaped = <Object>[], errors = <Object>[];
    final values = <List<NearbyOffer>>[];
    late StreamSubscription<List<NearbyOffer>> subscription;
    runZonedGuarded(() {
      subscription = search.stream.listen(values.add, onError: errors.add);
    }, (error, _) => escaped.add(error));
    await settleSession();
    expect(escaped, isEmpty);
    expect(
      errors.single.toString(),
      contains('Synchronous query setup failed'),
    );
    expect(values, isEmpty);
    expect(source.watchCalls, 2);
    expect(source.active, 0);
    expect(clock.activeTimers, 0);
    await subscription.cancel();
  });

  test(
    'synchronous legacy vendor setup failure terminates the whole search',
    () async {
      final source = LifecycleSource()..throwOnVendor = true;
      final clock = LifecycleClock();
      final errors = <Object>[], escaped = <Object>[];
      final values = <List<NearbyOffer>>[];
      final search = NearbyOfferRepository(
        source: source,
        clock: clock,
      ).search(StoreLocation(0, 0));
      final subscription = search.stream.listen(
        values.add,
        onError: errors.add,
      );
      runZonedGuarded(() {
        source.seed([lifecycleOffer('legacy', legacy: true)]);
      }, (error, _) => escaped.add(error));
      await settleSession();
      expect(escaped, isEmpty);
      expect(
        errors.single.toString(),
        contains('Synchronous vendor setup failed'),
      );
      expect(values, isEmpty);
      expect(source.active, 0);
      expect(clock.activeTimers, 0);
      await subscription.cancel();
    },
  );

  test(
    'every dispose caller waits for underlying cancellation acknowledgments',
    () async {
      final source = LifecycleSource(), clock = LifecycleClock();
      final search = NearbyOfferRepository(
        source: source,
        clock: clock,
      ).search(StoreLocation(0, 0));
      final values = <List<NearbyOffer>>[];
      final subscription = search.stream.listen(values.add);
      source.seed([lifecycleOffer('timer')]);
      await settleSession();
      expect(clock.activeTimers, 1);
      final gate = Completer<void>();
      for (final probe in source.probes) {
        probe.cancellationGate = gate;
      }
      var firstDone = false, secondDone = false;
      final first = search.dispose().then((_) => firstDone = true);
      final second = search.dispose().then((_) => secondDone = true);
      await settleSession();
      expect(source.probes.every((p) => p.cancellationRequested), isTrue);
      expect(firstDone, isFalse);
      expect(secondDone, isFalse);
      expect(clock.activeTimers, 0);
      final eventCount = values.length;
      source.probes.first.staleData!(
        NearbyChanges([lifecycleOffer('late')], const []),
      );
      expect(values.length, eventCount);
      gate.complete();
      await Future.wait([first, second]);
      expect(source.active, 0);
      await subscription.cancel();
    },
  );

  test('refresh waits for cancellation acknowledgment before opening replacement bounds', () async {
    final auth = await lifecycleAuth();
    final source = LifecycleSource(), clock = LifecycleClock();
    final controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(source: source, clock: clock),
      location: LifecycleLocation(),
    );
    addTearDown(auth.dispose);
    addTearDown(controller.dispose);
    final first = controller.locate();
    await settleSession();
    source.seed([lifecycleOffer('before')]);
    await first;
    final boundCount = source.probes.length;
    final obsolete = source.probes.first;
    final gate = Completer<void>();
    for (final probe in source.probes) {
      probe.cancellationGate = gate;
    }
    var finished = false;
    final refreshed = controller.refresh().then((_) => finished = true);
    await settleSession();
    expect(source.probes.length, boundCount);
    expect(source.active, boundCount);
    expect(controller.offers, isEmpty);
    expect(controller.phase, NearbyPhase.loading);
    expect(finished, isFalse);
    obsolete.staleData!(NearbyChanges([lifecycleOffer('stale')], const []));
    obsolete.deliverLateError(const AppFailure('stale error'));
    expect(controller.phase, NearbyPhase.loading);
    gate.complete();
    await settleSession();
    expect(source.probes.length, boundCount * 2);
    expect(source.active, boundCount);
    expect(source.maxActive, boundCount);
    source.seed([lifecycleOffer('after')]);
    await refreshed;
    expect(controller.offers.single.offer.id, 'after');
    expect(controller.error, isNull);
  });

  test('newer location wins and old account callbacks cannot alter the next customer', () async {
    final auth = await lifecycleAuth();
    final source = LifecycleSource(),
        location = LifecycleLocation()..automatic = false;
    final controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(
        source: source,
        clock: LifecycleClock(),
      ),
      location: location,
    );
    addTearDown(auth.dispose);
    addTearDown(controller.dispose);
    final older = controller.locate();
    await settleSession();
    final newer = controller.locate();
    await settleSession();
    location.requests[1].complete(StoreLocation(1, 1));
    await settleSession();
    source.seed([lifecycleOffer('new center', at: StoreLocation(1, 1))]);
    await newer;
    final watches = source.watchCalls;
    location.requests[0].complete(StoreLocation(0, 0));
    await older;
    expect(controller.center!.latitude, 1);
    expect(source.watchCalls, watches);
    final oldProbe = source.probes.first;
    final pendingLocation = controller.locate();
    await settleSession();
    await auth.signOut();
    await auth.registerCustomer(
      email: 'lifecycle-b@example.test',
      password: 'password',
      displayName: 'Lifecycle B',
    );
    await settleSession();
    location.requests.last.completeError(
      const AppFailure('Old location failed'),
    );
    await pendingLocation;
    oldProbe.staleData!(
      NearbyChanges([lifecycleOffer('old account')], const []),
    );
    oldProbe.deliverLateError(const AppFailure('Old account query failed'));
    await settleSession();
    expect(controller.center, isNull);
    expect(controller.offers, isEmpty);
    expect(controller.error, isNull);
    expect(controller.phase, NearbyPhase.locationRequired);
    expect(source.active, 0);
    location.automatic = true;
    final current = controller.locate();
    await settleSession();
    source.seed([lifecycleOffer('customer b')]);
    await current;
    expect(controller.offers.single.offer.id, 'customer b');
  });

  test(
    'disposed controller ignores pending location failures and auth changes',
    () async {
      final auth = await lifecycleAuth();
      final source = LifecycleSource(),
          location = LifecycleLocation()..automatic = false;
      final controller = NearbyFeedController(
        auth: auth,
        repository: NearbyOfferRepository(
          source: source,
          clock: LifecycleClock(),
        ),
        location: location,
      );
      addTearDown(auth.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.locate();
      await settleSession();
      controller.dispose();
      final before = notifications;
      location.requests.single.completeError(
        const AppFailure('After disposal'),
      );
      await pending;
      await auth.signOut();
      await settleSession();
      expect(notifications, before);
      expect(source.watchCalls, 0);
      expect(controller.offers, isEmpty);
    },
  );

  test('metadata transitions preserve the last acknowledged diff and quiet cancellation', () async {
    final input = LifecycleProbe<NearbySnapshot>(() {});
    final changes = <NearbyChanges>[];
    final subscription = acknowledgedNearbyChanges(input.stream)
        .listen(changes.add);
    final original = lifecycleOffer('acknowledged');
    input.add(NearbySnapshot([original], fromCache: true));
    input.add(NearbySnapshot([original]));
    input.add(const NearbySnapshot([], pending: true));
    input.add(const NearbySnapshot([], fromCache: true));
    input.add(NearbySnapshot([original]));
    input.add(const NearbySnapshot([]));
    await settleSession();
    expect(changes.map((change) => change.confirmed), [
      false,
      true,
      false,
      true,
      true,
    ]);
    expect(changes[1].upserts.single.id, 'acknowledged');
    expect(changes[3].upserts, isEmpty);
    expect(changes[3].removed, isEmpty);
    expect(changes.last.removed, ['acknowledged']);
    await subscription.cancel().timeout(const Duration(seconds: 1));
    expect(input.active, isFalse);
  });

  test('a bound returning to cache before initial completion must acknowledge again', () async {
    final source = LifecycleSource(), clock = LifecycleClock();
    final values = <List<NearbyOffer>>[], errors = <Object>[];
    final search = NearbyOfferRepository(
      source: source,
      clock: clock,
    ).search(StoreLocation(0, 0));
    final subscription = search.stream.listen(values.add, onError: errors.add);
    final first = source.probes.first;
    first.add(const NearbyChanges([], []));
    first.add(const NearbyChanges([], [], confirmed: false));
    for (final probe in source.probes.skip(1)) {
      probe.add(const NearbyChanges([], []));
    }
    await settleSession();
    expect(values, isEmpty);
    expect(errors, isEmpty);
    expect(clock.activeTimers, 1);
    first.add(const NearbyChanges([], []));
    await settleSession();
    expect(values.single, isEmpty);
    expect(clock.activeTimers, 0);
    await subscription.cancel();
    expect(source.active, 0);
  });

  test('persistent post-ready cache metadata becomes a retryable error after five seconds', () async {
    final auth = await lifecycleAuth();
    final source = LifecycleSource(), clock = LifecycleClock(manual: true);
    final controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(source: source, clock: clock),
      location: LifecycleLocation(),
    );
    addTearDown(auth.dispose);
    addTearDown(controller.dispose);
    final initial = controller.locate();
    await settleSession();
    for (final probe in source.probes) {
      probe.add(const NearbyChanges([], [], confirmed: false));
    }
    await settleSession();
    expect(controller.phase, NearbyPhase.loading);
    source.seed([lifecycleOffer('before disconnect')]);
    await initial;
    final previousCount = source.watchCalls;
    source.probes.first.add(const NearbyChanges([], [], confirmed: false));
    await settleSession();
    clock.elapse(const Duration(milliseconds: 4999));
    await settleSession();
    expect(controller.phase, NearbyPhase.ready);
    expect(controller.offers.single.offer.id, 'before disconnect');
    clock.elapse(const Duration(milliseconds: 1));
    await settleSession();
    expect(controller.phase, NearbyPhase.queryError);
    expect(controller.error, contains('connection'));
    expect(controller.offers, isEmpty);
    expect(source.active, 0);
    expect(clock.activeTimers, 0);
    final retry = controller.refresh();
    await settleSession();
    expect(source.watchCalls, greaterThan(previousCount));
    expect(controller.phase, NearbyPhase.loading);
    source.seed([lifecycleOffer('after reconnect')]);
    await retry;
    expect(controller.phase, NearbyPhase.ready);
    expect(controller.offers.single.offer.id, 'after reconnect');
    expect(controller.error, isNull);
  });

  test('transient cache metadata preserves expiry and all bounds must reconfirm to cancel grace', () async {
    final auth = await lifecycleAuth();
    final source = LifecycleSource(), clock = LifecycleClock(manual: true);
    final controller = NearbyFeedController(
      auth: auth,
      repository: NearbyOfferRepository(source: source, clock: clock),
      location: LifecycleLocation(),
    );
    addTearDown(auth.dispose);
    addTearDown(controller.dispose);
    final initial = controller.locate();
    await settleSession();
    source.seed([
      lifecycleOffer(
        'expires during grace',
        lifetime: const Duration(seconds: 2),
      ),
      lifecycleOffer('still active'),
    ]);
    await initial;
    final first = source.probes[0], second = source.probes[1];
    first.add(const NearbyChanges([], [], confirmed: false));
    second.add(const NearbyChanges([], [], confirmed: false));
    clock.elapse(const Duration(seconds: 2));
    await settleSession();
    expect(controller.phase, NearbyPhase.ready);
    expect(controller.offers.map((row) => row.offer.id), ['still active']);
    expect(controller.error, isNull);
    first.add(const NearbyChanges([], []));
    clock.elapse(const Duration(seconds: 2));
    await settleSession();
    expect(clock.activeTimers, 2, reason: 'One bound remains unconfirmed');
    second.add(const NearbyChanges([], []));
    expect(
      clock.activeTimers,
      1,
      reason: 'All bounds reconfirmed; only expiry remains',
    );
    clock.elapse(const Duration(seconds: 2));
    await settleSession();
    expect(controller.phase, NearbyPhase.ready);
    expect(controller.offers.single.offer.id, 'still active');
    expect(source.active, source.probes.length);
    // A later outage receives a new grace period instead of reusing an old
    // canceled timeout, and unrelated reconfirmations cannot clear that outage.
    second.add(const NearbyChanges([], [], confirmed: false));
    first.add(const NearbyChanges([], []));
    clock.elapse(const Duration(milliseconds: 4999));
    await settleSession();
    expect(controller.phase, NearbyPhase.ready);
    clock.elapse(const Duration(milliseconds: 1));
    await settleSession();
    expect(controller.phase, NearbyPhase.queryError);
    expect(source.active, 0);
    expect(clock.activeTimers, 0);
  });
}
