import 'package:sandhai/core/location/store_location.dart';

import 'support/phase3_fixtures.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sandhai/core/errors/app_failure.dart';
import 'package:sandhai/data/account_repository.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/vendor/services/offer_service.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installDraftFakes();
  late TestAccounts accounts;
  late AuthService auth;
  setUp(() {
    accounts = TestAccounts();
    auth = AuthService(repository: accounts)..start();
  });
  tearDown(() async {
    auth.dispose();
    await settleSession();
  });
  Future<String> vendor() async {
    final u = await auth.registerVendor(
      email: 'vendor@example.com',
      password: 'password',
      storeName: 'My store',
      phone: '9876543210',
      category: 'groceries',
    );
    await settleSession();
    return u.uid;
  }

  test('failed registration retries the authenticated UID without duplicate accounts', () async {
    accounts.failCompletion = true;
    await expectLater(vendor(), throwsA(isA<AppFailure>()));
    await settleSession();
    final uid = accounts.identity!.uid;
    expect(accounts.creations, 1);
    expect(auth.phase, SessionPhase.incomplete);
    accounts.failCompletion = false;
    expect(await vendor(), uid);
    expect(accounts.creations, 1);
    expect(auth.profile!.approvalStatus, 'pending');
    expect(auth.vendorProfile!.name, 'My store');
  });
  test(
    'an interrupted account restores into completion, not a mock user',
    () async {
      final id = await accounts.createAccount(
        'incomplete@example.com',
        'password',
      );
      await settleSession();
      expect(auth.phase, SessionPhase.incomplete);
      expect(auth.profile, isNull);
      await auth.completeRegistration(
        const RegistrationData(
          name: 'Recovered',
          role: 'vendor',
          phone: '9876543210',
        ),
      );
      expect(auth.identity!.uid, id.uid);
      expect(auth.phase, SessionPhase.ready);
      expect(auth.profile!.isPendingVendor, isTrue);
      expect(accounts.creations, 1);
    },
  );
  test(
    'restoring a completed session and observing approval needs no login',
    () async {
      final uid = await vendor();
      auth.dispose();
      auth = AuthService(repository: accounts)..start();
      await settleSession();
      expect(auth.profile!.uid, uid);
      expect(auth.profile!.isPendingVendor, isTrue);
      await auth.confirmStoreLocation(StoreLocation(13.0827, 80.2707));
      accounts.approval(uid, 'approved');
      await settleSession();
      expect(auth.profile!.isApprovedVendor, isTrue);
      accounts.approval(uid, 'rejected');
      await settleSession();
      expect(auth.profile!.isApprovedVendor, isFalse);
      expect(auth.profile!.isRejectedVendor, isTrue);
      accounts.approval(uid, 'suspended');
      await settleSession();
      expect(auth.profile!.isApprovedVendor, isFalse);
    },
  );
  test('completion does not change an existing role or approval', () async {
    final uid = await vendor();
    await auth.confirmStoreLocation(StoreLocation(13.0827, 80.2707));
    accounts.approval(uid, 'approved');
    await settleSession();
    await auth.completeRegistration(
      const RegistrationData(
        name: 'Retry',
        role: 'vendor',
        phone: '9876543210',
      ),
    );
    expect(auth.profile!.isApprovedVendor, isTrue);
  });
  test(
    'read and update failures propagate and do not change confirmed profiles',
    () async {
      final uid = await vendor();
      accounts.failRead = true;
      await expectLater(auth.fetchUserProfile(uid), throwsA(isA<AppFailure>()));
      accounts.failRead = false;
      accounts.failUpdate = true;
      await expectLater(
        auth.updateVendorProfile(
          uid: uid,
          name: 'Not saved',
          phone: '9876543210',
          category: 'groceries',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(accounts.vendors[uid]!.name, 'My store');
      expect(auth.profile!.displayName, 'My store');
    },
  );
  test('logout/account switching cancels old profile subscriptions and clears identity', () async {
    final uid = await vendor();
    expect(accounts.activeUserWatches, 1);
    expect(accounts.activeVendorWatches, 1);
    await auth.signOut();
    await settleSession();
    expect(auth.profile, isNull);
    expect(auth.vendorProfile, isNull);
    expect(auth.phase, SessionPhase.signedOut);
    expect(accounts.activeUserWatches, 0);
    expect(accounts.activeVendorWatches, 0);
    await auth.registerCustomer(
      email: 'other@example.com',
      password: 'password',
      displayName: 'Other',
    );
    await settleSession();
    expect(auth.identity!.uid, isNot(uid));
    expect(auth.profile!.displayName, 'Other');
    expect(auth.vendorProfile, isNull);
    expect(() => auth.requireAccount(uid), throwsA(isA<AppFailure>()));
  });
  test(
    'session stream errors surface and can be retried without a mock profile',
    () async {
      final uid = await vendor();
      accounts.failWatch = true;
      auth.retrySession();
      await settleSession();
      expect(auth.phase, SessionPhase.error);
      expect(auth.sessionError.toString(), contains('Session stream failed'));
      accounts.failWatch = false;
      auth.retrySession();
      await settleSession();
      expect(auth.phase, SessionPhase.ready);
      expect(auth.profile!.uid, uid);
    },
  );
  test(
    'a failed logout keeps the authenticated session and reports the failure',
    () async {
      final uid = await vendor();
      accounts.failLogout = true;
      await expectLater(auth.signOut(), throwsA(isA<AppFailure>()));
      expect(auth.identity!.uid, uid);
      expect(auth.profile!.uid, uid);
      accounts.failLogout = false;
      await auth.signOut();
      await settleSession();
      expect(auth.phase, SessionPhase.signedOut);
      expect(auth.profile, isNull);
    },
  );
  group('offer confirmation and failure handling', () {
    late TestOffers offers;
    late OfferService service;
    setUp(() async {
      final uid = await vendor();
      await auth.confirmStoreLocation(StoreLocation(13.0827, 80.2707));
      accounts.approval(uid, 'approved');
      await settleSession();
      offers = TestOffers();
      service = OfferService(auth: auth, repository: offers);
    });
    Future<dynamic> save({bool image = false}) => service.createOffer(
      offerId: 'stable-id',
      title: 'Offer',
      description: 'Details',
      oldPrice: 100,
      newPrice: 50,
      category: 'groceries',
      durationHours: 6,
      imageBytes: image ? testPng : null,
      imageFileName: 'test.jpg',
    );
    test('a pending save is never treated as a confirmed offer', () async {
      offers.saveGate = Completer<void>();
      var confirmed = false;
      final operation = save().then((_) => confirmed = true);
      await settleSession();
      expect(confirmed, isFalse);
      expect(offers.offers, isEmpty);
      offers.saveGate!.complete();
      await operation;
      expect(confirmed, isTrue);
    });
    test('upload failure stops the document write', () async {
      offers.failUpload = true;
      await expectLater(save(image: true), throwsA(isA<AppFailure>()));
      expect(offers.saves, 0);
      expect(offers.offers, isEmpty);
    });
    test(
      'account change after upload stops the write and attempts cleanup',
      () async {
        offers.afterUpload = auth.signOut;
        await expectLater(save(image: true), throwsA(isA<AppFailure>()));
        expect(offers.saves, 0);
        expect(offers.cleanups, 1);
        expect(offers.offers, isEmpty);
      },
    );
    test(
      'write failure propagates and cleans up an unreferenced upload',
      () async {
        offers.failSave = true;
        await expectLater(save(image: true), throwsA(isA<AppFailure>()));
        expect(offers.cleanups, 1);
        expect(offers.offers, isEmpty);
        offers.failSave = false;
        await save(image: true);
        expect(offers.offers.length, 1);
      },
    );
    test('a lost commit response is reconciled and retry does not duplicate or delete its image', () async {
      offers.loseResponse = true;
      await save(image: true);
      await save(image: true);
      expect(offers.offers.length, 1);
      expect(offers.saves, 1);
      expect(offers.uploads, 1);
      expect(offers.cleanups, 0);
    });
    test('revoked approval is checked again before a write', () async {
      accounts.approval(auth.identity!.uid, 'suspended');
      await settleSession();
      await expectLater(save(), throwsA(isA<AppFailure>()));
      expect(offers.saves, 0);
    });
    test('revocation between upload and publication cleans an absent offer and retries the same ID', () async {
      final uid = auth.identity!.uid;
      offers.afterUpload = () async {
        accounts.approval(uid, 'suspended');
        offers.failSave = true;
        await settleSession();
      };
      await expectLater(save(image: true), throwsA(isA<AppFailure>()));
      expect(offers.cleanups, 1);
      expect(offers.offers, isEmpty);
      expect(auth.profile!.isApprovedVendor, isFalse);
      accounts.approval(uid, 'approved');
      await settleSession();
      offers.afterUpload = null;
      offers.failSave = false;
      await save(image: true);
      expect(offers.offers.values.single.id, 'stable-id');
      expect(offers.offers, hasLength(1));
    });
    test('dashboard subscriptions only return their account and reject stale account access', () async {
      await save();
      final uid = auth.identity!.uid;
      final values = await service.watchVendorOffers(uid).first;
      expect(values.every((v) => v.vendorId == uid), isTrue);
      await auth.signOut();
      await settleSession();
      expect(() => service.watchVendorOffers(uid), throwsA(isA<AppFailure>()));
    });
  });
}
