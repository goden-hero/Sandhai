import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/app_failure.dart';
import '../models/offer_model.dart';
import 'offer_repository.dart';

class FirebaseOfferRepository implements OfferRepository {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;
  @override
  String newId() => _db.collection('offers').doc().id;
  @override
  Stream<List<OfferModel>> watchVendor(String uid) => _db
      .collection('offers')
      .where('vendorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots(includeMetadataChanges: true)
      .where((s) => !s.metadata.hasPendingWrites)
      .map((s) => s.docs.map(OfferModel.fromFirestore).toList());
  @override
  Future<OfferModel?> fetch(String id) async {
    final doc = await _db
        .collection('offers')
        .doc(id)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? OfferModel.fromFirestore(doc) : null;
  }

  @override
  Future<UploadedImage> upload(
    String uid,
    String id,
    Uint8List bytes,
    String filename,
  ) async {
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final extension = safeName.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => throw const AppFailure('Use a PNG, JPEG, or WebP image.'),
    };
    final ref = _storage.ref('offers/$uid/$id/$safeName');
    try {
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      return UploadedImage(ref.fullPath, await ref.getDownloadURL());
    } catch (_) {
      // Preserve the upload error even if cleanup also fails (e.g. offline).
      try {
        await ref.delete();
      } catch (_) {
        /* Best effort; no document references this failed upload. */
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteUpload(UploadedImage image) =>
      _storage.ref(image.path).delete();
  @override
  Future<OfferModel> save(OfferModel offer) => _db.runTransaction((tx) async {
    final user = await tx.get(_db.collection('users').doc(offer.vendorId));
    final ref = _db.collection('offers').doc(offer.id);
    final existing = await tx.get(ref);
    if (user.data()?['role'] != 'vendor' ||
        user.data()?['approvalStatus'] != 'approved') {
      throw const AppFailure(
        'Store approval is required. Your approval may have changed; refresh and retry.',
      );
    }
    if (existing.exists) {
      final saved = OfferModel.fromFirestore(existing);
      if (saved.vendorId != offer.vendorId) {
        throw const AppFailure('This offer belongs to another account.');
      }
      return saved; // Stable document ID makes retries idempotent.
    }
    tx.set(ref, offer.toFirestore());
    return offer;
  });
}
