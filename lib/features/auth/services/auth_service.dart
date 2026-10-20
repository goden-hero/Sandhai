import '../../../core/location/store_location.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/account_repository.dart';
import '../../../data/demo_account_repository.dart';
import '../../../data/firebase_account_repository.dart';
import '../../../models/user_model.dart';
import '../../../models/vendor_model.dart';

enum SessionPhase { loading, signedOut, incomplete, ready, error }

/// Owns the current account and its subscriptions, never a fallback identity.
class AuthService extends ChangeNotifier {
  AuthService({required this.repository});
  final AccountRepository repository;
  static AuthService? _instance;
  static AuthService get instance => _instance ??= (AuthService(
    repository: AppConfig.current.isDemo
        ? DemoAccountRepository()
        : FirebaseAccountRepository(),
  )..start());
  static void install(AuthService service) {
    _instance?.dispose();
    _instance = service;
    service.start();
  }

  static void configure() => install(
    AuthService(
      repository: AppConfig.current.isDemo
          ? DemoAccountRepository()
          : FirebaseAccountRepository(),
    ),
  );

  SessionPhase phase = SessionPhase.loading;
  AccountIdentity? identity;
  UserModel? profile;
  VendorModel? vendorProfile;
  Object? sessionError;
  int routeEpoch = 0;
  int _generation = 0;
  bool _started = false,
      _disposed = false,
      _formOperation = false,
      _vendorKnown = false;
  StreamSubscription<AccountIdentity?>? _authSub;
  StreamSubscription<UserModel?>? _userSub;
  StreamSubscription<VendorModel?>? _vendorSub;
  bool get isDemo => repository is DemoAccountRepository;
  // Compatibility for the existing demo smoke test, never populated in live modes.
  UserModel? get demoCurrentUser => isDemo ? profile : null;
  int get generation => _generation;

  void setDemoUser(UserModel? user) {
    final repo = repository;
    if (repo is! DemoAccountRepository) {
      throw const AppFailure('Demo users are disabled in Firebase modes.');
    }
    repo.setUser(user);
  }

  void start() {
    if (_started) return;
    _started = true;
    _authSub = repository.authChanges().listen(
      _attach,
      onError: (Object error) => _fail(error),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _attach(AccountIdentity? next, {bool force = false}) {
    if (!force &&
        next?.uid == identity?.uid &&
        (next != null || phase != SessionPhase.loading)) {
      return;
    }
    final previous = identity?.uid;
    final epoch = ++_generation;
    unawaited(_userSub?.cancel());
    unawaited(_vendorSub?.cancel());
    _userSub = null;
    _vendorSub = null;
    identity = next;
    profile = null;
    vendorProfile = null;
    _vendorKnown = false;
    sessionError = null;
    if (!_formOperation || (previous != null && previous != next?.uid)) {
      routeEpoch++;
    }
    if (next == null) {
      phase = SessionPhase.signedOut;
      _notify();
      return;
    }
    phase = SessionPhase.loading;
    _notify();
    _userSub = repository
        .watchUser(next.uid)
        .listen(
          (user) {
            if (_disposed || epoch != _generation) return;
            profile = user;
            if (user?.isVendor == true && _vendorSub == null) {
              _vendorSub = repository
                  .watchVendor(next.uid)
                  .listen(
                    (vendor) {
                      if (_disposed || epoch != _generation) return;
                      vendorProfile = vendor;
                      _vendorKnown = true;
                      _derive();
                    },
                    onError: (Object error) {
                      if (epoch == _generation) _fail(error);
                    },
                  );
            }
            _derive();
          },
          onError: (Object error) {
            if (epoch == _generation) _fail(error);
          },
        );
  }

  void _derive() {
    // A different listener's successful event must not hide a failed account
    // subscription. Retry explicitly reattaches both profile listeners.
    if (sessionError != null) {
      phase = SessionPhase.error;
      _notify();
      return;
    }
    phase = profile == null
        ? SessionPhase.incomplete
        : profile!.isVendor && !_vendorKnown
        ? SessionPhase.loading
        : profile!.isVendor && vendorProfile == null
        ? SessionPhase.incomplete
        : SessionPhase.ready;
    _notify();
  }

  void _fail(Object error) {
    sessionError = error;
    phase = SessionPhase.error;
    _notify();
  }

  void retrySession() => _attach(repository.identity, force: true);

  void requireAccount(String uid) {
    if (repository.identity?.uid != uid || identity?.uid != uid) {
      throw const AppFailure(
        'Your account changed. Sign in again before continuing.',
      );
    }
  }

  Future<UserModel?> fetchUserProfile(String uid) {
    requireAccount(uid);
    return repository.fetchUser(uid);
  }

  Future<VendorModel?> fetchVendorProfile(String uid) {
    requireAccount(uid);
    return repository.fetchVendor(uid);
  }

  Future<void> _loadConfirmed(AccountIdentity account) async {
    final epoch = _generation;
    final user = await repository.fetchUser(account.uid);
    final vendor = user?.isVendor == true
        ? await repository.fetchVendor(account.uid)
        : null;
    requireAccount(account.uid);
    if (epoch != _generation) {
      throw const AppFailure('The session changed. Please retry.');
    }
    // Restart terminal listeners only after successful server reads. A failed
    // read must leave an incomplete-registration form mounted for retry.
    if (phase == SessionPhase.error) _attach(account, force: true);
    profile = user;
    vendorProfile = vendor;
    _vendorKnown = true;
    _derive();
  }

  Future<UserModel> registerCustomer({
    required String email,
    required String password,
    required String displayName,
  }) => _register(
    email,
    password,
    RegistrationData(name: displayName, role: 'customer'),
  );

  Future<UserModel> registerVendor({
    required String email,
    required String password,
    required String storeName,
    required String phone,
    required String category,
    String address = '',
    String description = '',
  }) => _register(
    email,
    password,
    RegistrationData(
      name: storeName,
      role: 'vendor',
      phone: phone,
      category: category,
      address: address,
      description: description,
    ),
  );

  Future<UserModel> _register(
    String email,
    String password,
    RegistrationData data,
  ) async {
    _formOperation = true;
    try {
      var account = repository.identity;
      if (account != null &&
          account.email.toLowerCase() != email.trim().toLowerCase()) {
        throw const AppFailure(
          'Sign out before registering a different account.',
        );
      }
      account ??= await repository.createAccount(email.trim(), password);
      if (identity?.uid != account.uid) _attach(account);
      await repository.completeRegistration(account, data);
      await _loadConfirmed(account);
      _formOperation = false;
      routeEpoch++;
      _notify();
      return profile!;
    } catch (error) {
      // The form stays mounted with its values, including when Auth succeeded.
      // Retry uses repository.identity, so no duplicate Auth account is created.
      throw AppFailure(
        repository.identity == null
            ? errorMessage(error)
            : 'Registration was not confirmed. Your account exists; retry to complete it. ${errorMessage(error)}',
      );
    } finally {
      _formOperation = false;
    }
  }

  Future<void> completeRegistration(RegistrationData data) async {
    final account = identity;
    if (account == null) {
      throw const AppFailure('Sign in before completing registration.');
    }
    _formOperation = true;
    try {
      await repository.completeRegistration(account, data);
      await _loadConfirmed(account);
      routeEpoch++;
      _notify();
    } finally {
      _formOperation = false;
    }
  }

  Future<UserModel?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _formOperation = true;
    try {
      final account = await repository.signIn(email.trim(), password);
      if (identity?.uid != account.uid) _attach(account);
      await _loadConfirmed(account);
      routeEpoch++;
      _notify();
      return profile; // Missing profiles route to completion, never a mock customer.
    } finally {
      _formOperation = false;
    }
  }

  Future<VendorModel> confirmStoreLocation(StoreLocation location) async {
    final uid = identity!.uid;
    requireAccount(uid);
    final result = await repository.confirmLocation(uid, location);
    requireAccount(uid);
    return result;
  }

  Future<VendorModel> updateVendorProfile({
    required String uid,
    required String name,
    required String phone,
    required String category,
    String? address,
    String? description,
    String? imageUrl,
  }) async {
    requireAccount(uid);
    final result = await repository.updateVendor(
      uid,
      name: name,
      phone: phone,
      category: category,
      address: address,
      description: description,
      imageUrl: imageUrl,
    );
    requireAccount(uid);
    return result;
  }

  Future<void> signOut() async {
    await repository.signOut(); // Failed logout is not reported as success.
    _attach(null, force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_authSub?.cancel());
    unawaited(_userSub?.cancel());
    unawaited(_vendorSub?.cancel());
    super.dispose();
  }
}
