import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/location/nearby_geometry.dart';
import '../core/errors/app_failure.dart';
import '../core/location/store_location.dart';
import '../core/utils/geohash_utils.dart';
import '../models/offer_model.dart';
import 'nearby_query_source.dart';

class NearbyOffer {
  const NearbyOffer(this.offer, this.distanceMetres);
  final OfferModel offer;
  final double distanceMetres;
}

class NearbyClock {
  const NearbyClock();
  DateTime now() => DateTime.now();
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

class NearbyOfferRepository {
  NearbyOfferRepository({
    required this.source,
    this.clock = const NearbyClock(),
  });
  final NearbyQuerySource source;
  final NearbyClock clock;
  NearbySearch search(StoreLocation center) =>
      NearbySearch(source, center, clock);
}

/// One bounded search owns all query/vendor subscriptions and its expiry timer.
/// Errors terminate this search; retry creates a fresh, empty search.
class NearbySearch {
  NearbySearch(this.source, this.center, this.clock) {
    _out = StreamController<List<NearbyOffer>>(
      onListen: _start,
      onCancel: dispose,
    );
  }
  final NearbyQuerySource source;
  final StoreLocation center;
  final NearbyClock clock;
  late final StreamController<List<NearbyOffer>> _out;
  final _subscriptions = <StreamSubscription<NearbyChanges>>[];
  final _vendors = <String, StreamSubscription<Map<String, dynamic>?>>{};
  final _vendorData = <String, Map<String, dynamic>?>{};
  final _vendorTokens = <String, Object>{};
  final _retiringVendors = <Future<void>>{};
  final _records = <String, NearbyDocument>{};
  final _members = <int, Set<String>>{};
  final _ready = <int>{};
  late List<GeohashBound> _bounds;
  Timer? _timer;
  Timer? _initialTimeout;
  Timer? _confirmationTimeout;
  final _unconfirmed = <int>{};
  Future<void>? _disposal;
  bool _disposed = false, _emitted = false;
  Stream<List<NearbyOffer>> get stream => _out.stream;

  void _start() {
    _bounds = NearbyGeometry.bounds(center);
    _initialTimeout = clock.schedule(
      const Duration(seconds: 25),
      () => _fail(
        const AppFailure(
          'The server did not confirm nearby results. Check your connection and retry.',
        ),
      ),
    );
    for (var i = 0; i < _bounds.length; i++) {
      if (_disposed) break;
      final index = i;
      _members[i] = {};
      try {
        _subscriptions.add(
          source.watch(_bounds[i]).listen((changes) {
            if (_disposed) return;
            if (!changes.confirmed) {
              _ready.remove(index);
              _unconfirmed.add(index);
              // Native query membership changes can briefly enter cache state
              // while resolving limbo documents. Allow reconfirmation before
              // declaring a connection failure; expiry keeps running meanwhile.
              if (_emitted && _confirmationTimeout == null) {
                _confirmationTimeout = clock.schedule(
                  const Duration(seconds: 5),
                  () => _fail(
                    const AppFailure(
                      'The connection to Firestore was interrupted. Reconnect and retry.',
                    ),
                  ),
                );
              }
              return;
            }
            _ready.add(index);
            _unconfirmed.remove(index);
            if (_unconfirmed.isEmpty) {
              _confirmationTimeout?.cancel();
              _confirmationTimeout = null;
            }
            for (final id in changes.removed) {
              _members[index]!.remove(id);
              final hash = _records[id]?.data['geohash'];
              // A move may arrive in its new bound before the old removal. Keep the
              // new version only if it no longer belongs to the removed bound.
              if (hash is! String ||
                  _bounds[index].contains(hash) ||
                  !_members.values.any((ids) => ids.contains(id))) {
                _records.remove(id);
              }
            }
            for (final doc in changes.upserts) {
              _members[index]!.add(doc.id);
              _records[doc.id] = doc;
            }
            recheck();
          }, onError: _fail),
        );
      } catch (error, stack) {
        _fail(error, stack);
      }
    }
  }

  void _syncVendors(DateTime now) {
    final needed = <String>{};
    for (final doc in _records.values) {
      if (!doc.data.containsKey('locationConfirmedAt') &&
          _decode(doc, now, requireConfirmation: false) != null) {
        needed.add(doc.data['vendorId'] as String);
      }
    }
    for (final uid in _vendors.keys.toList()) {
      if (!needed.contains(uid)) {
        final cancellation = _vendors.remove(uid)!.cancel();
        _retiringVendors.add(cancellation);
        unawaited(
          cancellation.then(
            (_) {
              _retiringVendors.remove(cancellation);
            },
            onError: (Object error, StackTrace stack) {
              _retiringVendors.remove(cancellation);
              _fail(error, stack);
            },
          ),
        );
        _vendorData.remove(uid);
        _vendorTokens.remove(uid);
      }
    }
    for (final uid in needed) {
      if (_vendors.containsKey(uid)) continue;
      final token = Object();
      _vendorTokens[uid] = token;
      try {
        _vendors[uid] = source
            .watchVendor(uid)
            .listen(
              (data) {
                if (_disposed || _vendorTokens[uid] != token) return;
                _vendorData[uid] = data;
                recheck();
              },
              onError: (Object error, StackTrace stack) {
                if (_vendorTokens[uid] == token) _fail(error, stack);
              },
            );
      } catch (error, stack) {
        _fail(error, stack);
        return;
      }
    }
  }

  NearbyOffer? _decode(
    NearbyDocument document,
    DateTime now, {
    bool requireConfirmation = true,
  }) {
    final d = document.data;
    try {
      if (d['status'] != 'active' ||
          d['createdAt'] is! Timestamp ||
          d['expiryTime'] is! Timestamp ||
          !(d['expiryTime'] as Timestamp).toDate().isAfter(now) ||
          !_validVendorId(d['vendorId']) ||
          d['title'] is! String ||
          (d['title'] as String).trim().isEmpty ||
          d['description'] is! String ||
          d['imageUrl'] is! String ||
          d['latitude'] is! num ||
          d['longitude'] is! num ||
          d['oldPrice'] is! num ||
          d['newPrice'] is! num) {
        return null;
      }
      final lat = (d['latitude'] as num).toDouble(),
          lng = (d['longitude'] as num).toDouble();
      if (!GeohashUtils.isValidLocation(lat, lng) ||
          d['geohash'] != GeohashUtils.encode(lat, lng)) {
        return null;
      }
      final old = (d['oldPrice'] as num).toDouble(),
          price = (d['newPrice'] as num).toDouble();
      if (!old.isFinite || !price.isFinite || price <= 0 || old < price) {
        return null;
      }
      final created = (d['createdAt'] as Timestamp).toDate();
      if (!(d['expiryTime'] as Timestamp).toDate().isAfter(created)) {
        return null;
      }
      if (requireConfirmation && d['locationConfirmedAt'] is! Timestamp) {
        // Phase 3 offers predate the snapshot marker. Accept only when the
        // current confirmed store still matches, and was confirmed BEFORE this
        // offer. Never bless old sample coordinates by a later confirmation.
        final vendor = _vendorData[d['vendorId']];
        if (d.containsKey('locationConfirmedAt') ||
            vendor == null ||
            vendor['locationConfirmedAt'] is! Timestamp ||
            (vendor['locationConfirmedAt'] as Timestamp).toDate().isAfter(
              created,
            ) ||
            vendor['latitude'] != d['latitude'] ||
            vendor['longitude'] != d['longitude'] ||
            vendor['geohash'] != d['geohash']) {
          return null;
        }
      }
      final distance = NearbyGeometry.distance(center, StoreLocation(lat, lng));
      if (distance > NearbyGeometry.radiusMetres) return null;
      return NearbyOffer(OfferModel.fromMap(document.id, d), distance);
    } on Object {
      // Untrusted legacy fields must not take down the whole feed.
      return null;
    }
  }

  /// Called by the UI on application resume as well as by the next-expiry timer.
  void recheck() {
    if (_disposed) return;
    _timer?.cancel();
    final now = clock.now();
    _syncVendors(now);
    if (_disposed) return;
    if ((!_emitted && _ready.length != _bounds.length) ||
        (!_emitted &&
            _vendors.keys.any((uid) => !_vendorData.containsKey(uid)))) {
      return;
    }
    _emitted = true;
    _initialTimeout?.cancel();
    final offers = [
      for (final doc in _records.values)
        if (_decode(doc, now) case final value?) value,
    ];
    offers.sort((a, b) {
      final distance = a.distanceMetres.compareTo(b.distanceMetres);
      return distance != 0 ? distance : a.offer.id.compareTo(b.offer.id);
    });
    _out.add(offers);
    if (offers.isNotEmpty) {
      final next = offers
          .map((v) => v.offer.expiryTime)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final delay = next.difference(now);
      // Avoid browser setTimeout overflow on malformed far-future legacy dates;
      // the cap also catches foreground wall-clock adjustments within a minute.
      _timer = clock.schedule(
        delay > const Duration(minutes: 1) ? const Duration(minutes: 1) : delay,
        recheck,
      );
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_disposed) return;
    _out.addError(error, stack);
    unawaited(dispose().then((_) => _out.close()));
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    _initialTimeout?.cancel();
    _confirmationTimeout?.cancel();
    await Future.wait([
      ..._subscriptions.map((s) => s.cancel()),
      ..._vendors.values.map((s) => s.cancel()),
      ..._retiringVendors,
    ]);
    _records.clear();
    _members.clear();
    _vendorData.clear();
  }
}

bool _validVendorId(Object? uid) =>
    uid is String && uid.isNotEmpty && uid.length <= 128 && !uid.contains('/');
