import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/location/location_service.dart';
import '../../core/location/store_location.dart';
import '../../data/nearby_offer_repository.dart';
import '../auth/services/auth_service.dart';

enum NearbyPhase {
  locationRequired,
  locating,
  loading,
  ready,
  locationError,
  queryError,
}

class NearbyFeedController extends ChangeNotifier {
  NearbyFeedController({
    required this.auth,
    required this.repository,
    required this.location,
  }) {
    _uid = auth.identity?.uid;
    auth.addListener(_accountChanged);
  }
  final AuthService auth;
  final NearbyOfferRepository repository;
  final LocationService location;
  String? _uid;
  int _epoch = 0;
  bool _disposed = false;
  bool _paused = false;
  Future<void>? _teardown;
  NearbySearch? _search;
  StreamSubscription<List<NearbyOffer>>? _subscription;
  Completer<void>? _pendingRefresh;
  NearbyPhase phase = NearbyPhase.locationRequired;
  StoreLocation? center;
  String? error;
  List<NearbyOffer> offers = [];

  void _accountChanged() {
    if (auth.identity?.uid == _uid) return;
    _uid = auth.identity?.uid;
    unawaited(_clear());
    center = null;
    phase = NearbyPhase.locationRequired;
    _notify();
  }

  Future<void> _clear() {
    ++_epoch;
    if (_pendingRefresh?.isCompleted == false) _pendingRefresh!.complete();
    _pendingRefresh = null;
    _teardown = Future.wait<void>([
      if (_teardown != null) _teardown!,
      if (_subscription != null) _subscription!.cancel(),
      if (_search != null) _search!.dispose(),
    ]).then((_) {});
    _subscription = null;
    _search = null;
    offers = [];
    error = null;
    return _teardown!;
  }

  bool _current(int epoch) =>
      !_disposed &&
      !_paused &&
      _epoch == epoch &&
      _uid != null &&
      auth.identity?.uid == _uid;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> locate() async {
    final teardown = _clear();
    center = null;
    if (_uid == null) return;
    final epoch = _epoch;
    phase = NearbyPhase.locating;
    _notify();
    try {
      await teardown;
      if (!_current(epoch)) return;
      final result = await location.suggest();
      if (!_current(epoch)) return;
      center = result;
      await refresh();
    } catch (e) {
      if (!_current(epoch)) return;
      error = errorMessage(e);
      phase = NearbyPhase.locationError;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (center == null) return locate();
    final teardown = _clear();
    if (_uid == null) return;
    final epoch = _epoch;
    phase = NearbyPhase.loading;
    _notify();
    await teardown;
    if (!_current(epoch)) return;
    final search = repository.search(center!);
    _search = search;
    final ready = Completer<void>();
    _pendingRefresh = ready;
    _subscription = search.stream.listen(
      (values) {
        if (!_current(epoch)) return;
        offers = values;
        phase = NearbyPhase.ready;
        error = null;
        if (!ready.isCompleted) ready.complete();
        _notify();
      },
      onError: (Object e) {
        if (!_current(epoch)) return;
        offers = [];
        phase = NearbyPhase.queryError;
        error = 'Nearby offers could not be loaded. ${errorMessage(e)}';
        if (!ready.isCompleted) ready.complete();
        _notify();
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete();
      },
    );
    // The search reports a connection timeout; cancellation also completes this
    // future immediately, rather than retaining an obsolete refresh operation.
    await ready.future;
  }

  void recheckExpiry() => _search?.recheck();

  /// Routes above the feed must not retain hidden Firestore subscriptions.
  Future<void> pause() {
    _paused = true;
    return _clear();
  }

  Future<void> resume() async {
    _paused = false;
    if (_disposed) return;
    if (center != null && _uid != null) {
      await refresh();
    } else {
      phase = NearbyPhase.locationRequired;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_accountChanged);
    unawaited(_clear());
    super.dispose();
  }
}
