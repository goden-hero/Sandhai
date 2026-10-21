import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/location/nearby_geometry.dart';

class NearbyDocument {
  const NearbyDocument(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

/// Changes, rather than full snapshots, prevent an unchanged overlapping result
/// from overwriting a newer document received through another bound.
class NearbyChanges {
  const NearbyChanges(this.upserts, this.removed, {this.confirmed = true});
  final List<NearbyDocument> upserts;
  final List<String> removed;
  final bool confirmed;
}

abstract class NearbyQuerySource {
  Stream<NearbyChanges> watch(GeohashBound bound);
  Stream<Map<String, dynamic>?> watchVendor(String uid);
}

class FirebaseNearbyQuerySource implements NearbyQuerySource {
  FirebaseNearbyQuerySource([this._firestore]);
  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  @override
  Stream<NearbyChanges> watch(GeohashBound bound) => acknowledgedNearbyChanges(
    _db
        .collection('offers')
        .where('status', isEqualTo: 'active')
        .orderBy('geohash')
        .startAt([bound.start])
        .endAt([bound.end])
        .snapshots(includeMetadataChanges: true)
        .map(
          (s) => NearbySnapshot(
            [for (final d in s.docs) NearbyDocument(d.id, d.data())],
            fromCache: s.metadata.isFromCache,
            pending: s.metadata.hasPendingWrites,
          ),
        ),
  );

  @override
  Stream<Map<String, dynamic>?> watchVendor(String uid) => _db
      .collection('vendors')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.isFromCache && !s.metadata.hasPendingWrites)
      .map((s) => s.data());
}

class NearbySnapshot {
  const NearbySnapshot(
    this.documents, {
    this.fromCache = false,
    this.pending = false,
  });
  final List<NearbyDocument> documents;
  final bool fromCache, pending;
}

/// Diff only acknowledged snapshots: metadata-only server transitions can follow
/// filtered cache/pending events. Stream.multi forwards cancellation immediately,
/// including while the SDK is quiet; an async* await-for can wait for a new event.
Stream<NearbyChanges> acknowledgedNearbyChanges(
  Stream<NearbySnapshot> snapshots,
) => Stream.multi((out) {
  var previous = <String, Map<String, dynamic>>{};
  final subscription = snapshots.listen(
    (snapshot) {
      if (snapshot.fromCache) {
        out.addSync(const NearbyChanges([], [], confirmed: false));
        return;
      }
      if (snapshot.pending) return;
      final current = {for (final d in snapshot.documents) d.id: d.data};
      out.addSync(
        NearbyChanges(
          [
            for (final entry in current.entries)
              if (!mapEquals(previous[entry.key], entry.value))
                NearbyDocument(entry.key, entry.value),
          ],
          [
            for (final id in previous.keys)
              if (!current.containsKey(id)) id,
          ],
        ),
      );
      previous = current;
    },
    onError: out.addErrorSync,
    onDone: out.closeSync,
  );
  out.onCancel = subscription.cancel;
});
