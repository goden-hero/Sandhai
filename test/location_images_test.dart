import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sandhai/core/images/image_selection_service.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sandhai/core/constants/offer_categories.dart';
import 'package:sandhai/core/images/selected_image.dart';
import 'package:sandhai/core/location/location_service.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/core/utils/geohash_utils.dart';
import 'package:sandhai/features/auth/services/auth_service.dart';
import 'package:sandhai/features/vendor/services/offer_service.dart';
import 'package:sandhai/models/vendor_model.dart';
import 'package:sandhai/models/offer_model.dart';

import 'support/fakes.dart';
import 'support/phase3_fixtures.dart';

class RecoveredPicker extends ImagePicker {
  LostDataResponse response = LostDataResponse.empty();
  @override
  Future<LostDataResponse> retrieveLostData() async => response;
}

class LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Object? failure;
  int fixes = 0, requests = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    fixes++;
    expect(locationSettings!.timeLimit, const Duration(seconds: 20));
    if (failure != null) throw failure!;
    return Position(
      latitude: 11.1,
      longitude: 77.2,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class CleanupOffers extends TestOffers {
  bool failCleanup = true, failReconciliation = false;
  @override
  Future<void> deleteUpload(image) async {
    if (failCleanup) throw StateError('Cleanup unavailable');
    await super.deleteUpload(image);
  }

  @override
  Future<OfferModel?> fetch(String id) async {
    if (failReconciliation && saves > 0) throw StateError('Offline');
    return super.fetch(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installDraftFakes);
  test('Android lost picker data is decoded and canonicalized; cancellation is empty', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final picker = RecoveredPicker();
    final service = ImageSelectionService(picker: picker);
    expect(await service.recover(), isNull);
    picker.response = LostDataResponse(
      files: [XFile.fromData(testPng, name: 'misleading.jpg')],
      type: RetrieveType.image,
    );
    final recovered = await service.recover();
    expect(recovered!.contentType, 'image/png');
    expect(recovered.filename, endsWith('.png'));
  });
  test('finite coordinate bounds, zero coordinates, and canonical geohash', () {
    for (final lat in [double.nan, double.infinity, -91.0, 91.0]) {
      expect(() => StoreLocation(lat, 0), throwsArgumentError);
      expect(() => GeohashUtils.encode(lat, 0), throwsArgumentError);
    }
    for (final lng in [double.nan, double.negativeInfinity, -181.0, 181.0]) {
      expect(() => StoreLocation(0, lng), throwsArgumentError);
    }
    expect(StoreLocation(0, 0).geohash, 's00000');
    expect(StoreLocation(13.0827, 80.2707).geohash, 'tf346t');
  });
  test('legacy/default store location is unconfirmed; missing coordinates remain absent', () {
    final data = {
      'name': 'Store',
      'phone': '9876543210',
      'category': 'Groceries',
      'createdAt': Timestamp.now(),
    };
    final missing = VendorModel.fromMap('uid', data);
    expect(missing.latitude, isNull);
    expect(missing.longitude, isNull);
    expect(missing.toFirestore().containsKey('latitude'), isFalse);
    final legacy = VendorModel.fromMap('uid', {
      ...data,
      'latitude': 13.0827,
      'longitude': 80.2707,
      'geohash': 'tf346t',
    });
    expect(legacy.hasConfirmedLocation, isFalse);
    final confirmed = legacy.copyWith(locationConfirmedAt: DateTime.now());
    expect(
      VendorModel.fromMap('uid', confirmed.toFirestore()).hasConfirmedLocation,
      isTrue,
    );
    expect(confirmed.copyWith(geohash: '000000').hasConfirmedLocation, isFalse);
  });
  test('category and image metadata roundtrip, with documented legacy category fallback', () {
    final now = DateTime.now();
    final o = OfferModel(
      id: 'id',
      vendorId: 'v',
      title: 'Bread rice mango',
      description: 'Words do not determine category',
      category: 'services',
      oldPrice: 20,
      newPrice: 10,
      imageUrl: 'https://image',
      imagePath: 'offers/v/id/p.png',
      imageContentType: 'image/png',
      imageSize: 100,
      latitude: 0,
      longitude: 0,
      geohash: 's00000',
      createdAt: now,
      expiryTime: now.add(const Duration(hours: 1)),
      status: 'active',
    );
    final saved = OfferModel.fromMap('id', o.toFirestore());
    expect(saved.category, 'services');
    expect(saved.imageContentType, 'image/png');
    expect(saved.imageSize, 100);
    final legacy = o.toFirestore()..remove('category');
    expect(OfferModel.fromMap('id', legacy).category, 'other');
    expect(OfferCategories.normalize('Bakery & Dairy'), 'bakery_dairy');
    expect(OfferCategories.normalize('Unknown legacy category'), 'other');
  });
  test(
    'location failures give actionable feedback and never fabricate a fix',
    () async {
      final platform = LocationPlatform();
      final service = LocationService(platform: platform);
      platform.enabled = false;
      await expectLater(
        service.suggest(),
        throwsA(predicate((e) => e.toString().contains('disabled'))),
      );
      platform.enabled = true;
      platform.permission = LocationPermission.denied;
      await expectLater(
        service.suggest(),
        throwsA(predicate((e) => e.toString().contains('denied'))),
      );
      expect(platform.requests, 1);
      platform.permission = LocationPermission.deniedForever;
      await expectLater(
        service.suggest(),
        throwsA(predicate((e) => e.toString().contains('permanently denied'))),
      );
      expect(platform.fixes, 0);
      platform.permission = LocationPermission.whileInUse;
      platform.failure = TimeoutException('timeout');
      await expectLater(
        service.suggest(),
        throwsA(predicate((e) => e.toString().contains('timed out'))),
      );
      platform.failure = UnsupportedError('unsupported');
      await expectLater(
        service.suggest(),
        throwsA(predicate((e) => e.toString().contains('HTTPS'))),
      );
      platform.failure = null;
      expect((await service.suggest()).latitude, 11.1);
    },
  );
  test('content validation rejects fake, truncated, oversized, and unsupported images', () async {
    for (final bytes in [
      Uint8List(0),
      Uint8List(SelectedImage.maxBytes + 1),
      Uint8List.fromList([255, 216, 255]),
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList('GIF89a'.codeUnits),
    ]) {
      await expectLater(SelectedImage.validate(bytes), throwsA(anything));
    }
    final image = await SelectedImage.validate(testPng);
    expect(image.contentType, 'image/png');
    expect(image.filename, matches(RegExp(r'^[a-f0-9]{64}\.png$')));
    expect((await SelectedImage.validate(testPng)).filename, image.filename);
  });
  test('unconfirmed registration cannot publish; confirmed snapshot and category are saved', () async {
    final accounts = TestAccounts();
    final auth = AuthService(repository: accounts)..start();
    addTearDown(auth.dispose);
    final user = await auth.registerVendor(
      email: 'phase3@test.com',
      password: 'password',
      storeName: 'Store',
      phone: '9876543210',
      category: 'groceries',
    );
    accounts.approval(user.uid, 'approved');
    await settleSession();
    final offers = TestOffers();
    final service = OfferService(auth: auth, repository: offers);
    Future<OfferModel> save() => service.createOffer(
      title: 'Rice bread',
      description: '',
      oldPrice: 100,
      newPrice: 50,
      category: 'services',
      durationHours: 6,
    );
    await expectLater(
      save(),
      throwsA(predicate((e) => e.toString().contains('confirmation'))),
    );
    await auth.confirmStoreLocation(StoreLocation(11.1, 77.2));
    final saved = await save();
    expect(saved.latitude, 11.1);
    expect(saved.geohash, GeohashUtils.encode(11.1, 77.2));
    expect(saved.category, 'services');
  });
  test('cleanup failure reuses the same photo; uncertain commits retain it until reconciliation', () async {
    final accounts = TestAccounts();
    final auth = AuthService(repository: accounts)..start();
    addTearDown(auth.dispose);
    final u = await auth.registerVendor(
      email: 'cleanup@test.com',
      password: 'password',
      storeName: 'Store',
      phone: '9876543210',
      category: 'groceries',
    );
    accounts.approval(u.uid, 'approved');
    await auth.confirmStoreLocation(StoreLocation(11.1, 77.2));
    await settleSession();
    final repo = CleanupOffers()..failSave = true;
    var service = OfferService(auth: auth, repository: repo);
    Future<OfferModel> save() => service.createOffer(
      offerId: 'stable',
      title: 'Offer',
      description: '',
      oldPrice: 100,
      newPrice: 50,
      category: 'groceries',
      durationHours: 6,
      imageBytes: testPng,
    );
    await expectLater(
      save(),
      throwsA(
        predicate(
          (e) => e.toString().contains('cleanup could not be confirmed'),
        ),
      ),
    );
    expect(repo.uploads, 1);
    repo.failSave = false;
    service = OfferService(
      auth: auth,
      repository: repo,
    ); // Simulate service restart; the journal reuses the upload.
    await save();
    expect(repo.uploads, 1);
    expect(repo.offers.length, 1);
    final uncertain = CleanupOffers()
      ..failSave = true
      ..failReconciliation = true;
    final service2 = OfferService(auth: auth, repository: uncertain);
    Future<OfferModel> retry() => service2.createOffer(
      offerId: 'uncertain',
      title: 'Offer',
      description: '',
      oldPrice: 100,
      newPrice: 50,
      category: 'groceries',
      durationHours: 6,
      imageBytes: testPng,
    );
    await expectLater(
      retry(),
      throwsA(predicate((e) => e.toString().contains('uncertain'))),
    );
    expect(uncertain.cleanups, 0);
    await expectLater(retry(), throwsA(anything));
    expect(uncertain.uploads, 1);
    uncertain.failReconciliation = false;
    uncertain.failSave = false;
    await retry();
    expect(uncertain.uploads, 1);
    expect(uncertain.offers.length, 1);
  });
}
