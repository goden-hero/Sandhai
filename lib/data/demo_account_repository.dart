import 'dart:async';

import '../core/utils/geohash_utils.dart';
import '../models/user_model.dart';
import '../models/vendor_model.dart';
import 'account_repository.dart';

/// Explicit in-memory demo backend. Never used by Firebase modes.
class DemoAccountRepository implements AccountRepository {
  AccountIdentity? _identity;
  final users = <String, UserModel>{};
  final vendors = <String, VendorModel>{};
  final _auth = StreamController<AccountIdentity?>.broadcast(sync: true);
  final _profiles = StreamController<void>.broadcast(sync: true);
  @override
  AccountIdentity? get identity => _identity;
  @override
  Stream<AccountIdentity?> authChanges() async* {
    yield identity;
    yield* _auth.stream;
  }

  @override
  Future<AccountIdentity> createAccount(String email, String password) async {
    _identity = AccountIdentity(
      'demo_${DateTime.now().microsecondsSinceEpoch}',
      email,
    );
    _auth.add(_identity);
    return _identity!;
  }

  @override
  Future<AccountIdentity> signIn(String email, String password) async {
    final id = await createAccount(email, password);
    await completeRegistration(
      id,
      RegistrationData(
        name: email.split('@').first,
        role: email.contains('vendor') ? 'vendor' : 'customer',
        phone: '9876543210',
      ),
    );
    return id;
  }

  @override
  Future<void> signOut() async {
    _identity = null;
    _auth.add(null);
  }

  @override
  Stream<UserModel?> watchUser(String uid) async* {
    yield users[uid];
    yield* _profiles.stream.map((_) => users[uid]);
  }

  @override
  Stream<VendorModel?> watchVendor(String uid) async* {
    yield vendors[uid];
    yield* _profiles.stream.map((_) => vendors[uid]);
  }

  @override
  Future<UserModel?> fetchUser(String uid) async => users[uid];
  @override
  Future<VendorModel?> fetchVendor(String uid) async => vendors[uid];
  @override
  Future<void> completeRegistration(
    AccountIdentity identity,
    RegistrationData data,
  ) async {
    users.putIfAbsent(
      identity.uid,
      () => UserModel(
        uid: identity.uid,
        displayName: data.name,
        email: identity.email,
        role: data.role,
        approvalStatus: data.role == 'vendor' ? 'pending' : 'approved',
        createdAt: DateTime.now(),
      ),
    );
    if (data.role == 'vendor') {
      vendors.putIfAbsent(
        identity.uid,
        () => VendorModel(
          uid: identity.uid,
          name: data.name,
          phone: data.phone,
          category: data.category,
          address: data.address,
          description: data.description,
          latitude: data.latitude,
          longitude: data.longitude,
          geohash:
              data.geohash ??
              GeohashUtils.encode(data.latitude, data.longitude),
          createdAt: DateTime.now(),
        ),
      );
    }
    _profiles.add(null);
  }

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
    final old = vendors[uid]!;
    final updated = old.copyWith(
      name: name,
      phone: phone,
      category: category,
      address: address,
      description: description,
      imageUrl: imageUrl,
      updatedAt: DateTime.now(),
    );
    vendors[uid] = updated;
    final user = users[uid]!;
    users[uid] = UserModel(
      uid: uid,
      displayName: name,
      email: user.email,
      role: user.role,
      approvalStatus: user.approvalStatus,
      createdAt: user.createdAt,
    );
    _profiles.add(null);
    return updated;
  }

  // Demo/test-only session setup; does not exist on the Firebase repository.
  void setUser(UserModel? user) {
    _identity = user == null ? null : AccountIdentity(user.uid, user.email);
    if (user != null) users[user.uid] = user;
    _auth.add(_identity);
    _profiles.add(null);
  }
}
