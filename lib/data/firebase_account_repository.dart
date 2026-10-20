import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/errors/app_failure.dart';
import '../core/location/store_location.dart';
import '../models/user_model.dart';
import '../models/vendor_model.dart';
import 'account_repository.dart';

class FirebaseAccountRepository implements AccountRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  AccountIdentity _identity(User user) =>
      AccountIdentity(user.uid, user.email ?? '');
  @override
  AccountIdentity? get identity =>
      _auth.currentUser == null ? null : _identity(_auth.currentUser!);
  @override
  Stream<AccountIdentity?> authChanges() =>
      _auth.authStateChanges().map((u) => u == null ? null : _identity(u));
  @override
  Future<AccountIdentity> createAccount(String email, String password) async =>
      _identity(
        (await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).user!,
      );
  @override
  Future<AccountIdentity> signIn(String email, String password) async =>
      _identity(
        (await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        )).user!,
      );
  @override
  Future<void> signOut() => _auth.signOut();
  @override
  Stream<UserModel?> watchUser(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where((d) => !d.metadata.hasPendingWrites && !d.metadata.isFromCache)
      .map((d) => d.exists ? UserModel.fromFirestore(d) : null);
  @override
  Stream<VendorModel?> watchVendor(String uid) => _db
      .collection('vendors')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where((d) => !d.metadata.hasPendingWrites && !d.metadata.isFromCache)
      .map((d) => d.exists ? VendorModel.fromFirestore(d) : null);
  @override
  Future<UserModel?> fetchUser(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? UserModel.fromFirestore(doc) : null;
  }

  @override
  Future<VendorModel?> fetchVendor(String uid) async {
    final doc = await _db
        .collection('vendors')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists ? VendorModel.fromFirestore(doc) : null;
  }

  @override
  Future<void> completeRegistration(
    AccountIdentity identity,
    RegistrationData data,
  ) async {
    final userRef = _db.collection('users').doc(identity.uid);
    final vendorRef = _db.collection('vendors').doc(identity.uid);
    // Transactions are online-only and return after server acknowledgement. There
    // is no queued offline write and no second Auth account on completion/retry.
    await _db.runTransaction((tx) async {
      final userDoc = await tx.get(userRef);
      final vendorDoc = await tx.get(vendorRef);
      final existing = userDoc.exists ? UserModel.fromFirestore(userDoc) : null;
      if (existing != null && existing.role != data.role) {
        throw AppFailure(
          'This account is already a ${existing.role}. Its role cannot be changed.',
        );
      }
      final now = DateTime.now();
      if (existing == null) {
        tx.set(
          userRef,
          UserModel(
            uid: identity.uid,
            displayName: data.name.trim(),
            email: identity.email,
            role: data.role,
            approvalStatus: data.role == 'vendor' ? 'pending' : 'approved',
            createdAt: now,
          ).toFirestore(),
        );
      }
      if (data.role == 'vendor' && !vendorDoc.exists) {
        tx.set(
          vendorRef,
          VendorModel(
            uid: identity.uid,
            name: data.name.trim(),
            phone: data.phone.trim(),
            category: data.category,
            address: data.address.trim(),
            description: data.description.trim(),
            createdAt: now,
          ).toFirestore(),
        );
      }
      // Existing profiles, roles, approvals, and creation timestamps are immutable
      // during completion. In particular a retry never resets an approved vendor.
    });
  }

  @override
  Future<VendorModel> confirmLocation(String uid, StoreLocation location) =>
      _db.runTransaction((tx) async {
        final ref = _db.collection('vendors').doc(uid);
        final doc = await tx.get(ref);
        if (!doc.exists) {
          throw const AppFailure('Complete your store profile first.');
        }
        final updated = VendorModel.fromFirestore(doc).copyWith(
          latitude: location.latitude,
          longitude: location.longitude,
          geohash: location.geohash,
          locationConfirmedAt: DateTime.now(),
        );
        tx.set(ref, {
          ...updated.toFirestore(),
          'locationConfirmedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return updated;
      });

  @override
  Future<VendorModel> updateVendor(
    String uid, {
    required String name,
    required String phone,
    required String category,
    String? address,
    String? description,
    String? imageUrl,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final vendorRef = _db.collection('vendors').doc(uid);
    return _db.runTransaction((tx) async {
      final userDoc = await tx.get(userRef);
      final vendorDoc = await tx.get(vendorRef);
      if (!userDoc.exists ||
          !vendorDoc.exists ||
          UserModel.fromFirestore(userDoc).role != 'vendor') {
        throw const AppFailure(
          'Complete your vendor registration before editing the store profile.',
        );
      }
      final existing = VendorModel.fromFirestore(vendorDoc);
      final updated = existing.copyWith(
        name: name.trim(),
        phone: phone.trim(),
        category: category,
        address: address?.trim(),
        description: description?.trim(),
        imageUrl: imageUrl?.trim(),
        updatedAt: DateTime.now(),
      );
      // Full replacement intentionally allows clearing optional fields.
      tx.set(vendorRef, updated.toFirestore());
      tx.update(userRef, {
        'displayName': name.trim(),
        'updatedAt': Timestamp.now(),
      });
      return updated;
    });
  }
}
