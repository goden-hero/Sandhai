import '../core/location/store_location.dart';
import '../models/user_model.dart';
import '../models/vendor_model.dart';

class AccountIdentity {
  const AccountIdentity(this.uid, this.email);
  final String uid;
  final String email;
}

class RegistrationData {
  const RegistrationData({
    required this.name,
    required this.role,
    this.phone = '',
    this.category = 'groceries',
    this.address = '',
    this.description = '',
  });
  final String name, role, phone, category, address, description;
}

abstract class AccountRepository {
  AccountIdentity? get identity;
  Stream<AccountIdentity?> authChanges();
  Future<AccountIdentity> createAccount(String email, String password);
  Future<AccountIdentity> signIn(String email, String password);
  Future<void> signOut();
  Stream<UserModel?> watchUser(String uid);
  Stream<VendorModel?> watchVendor(String uid);
  Future<UserModel?> fetchUser(String uid);
  Future<VendorModel?> fetchVendor(String uid);
  Future<void> completeRegistration(
    AccountIdentity identity,
    RegistrationData data,
  );
  Future<VendorModel> confirmLocation(String uid, StoreLocation location);
  Future<VendorModel> updateVendor(
    String uid, {
    required String name,
    required String phone,
    required String category,
    String? address,
    String? description,
    String? imageUrl,
  });
}
