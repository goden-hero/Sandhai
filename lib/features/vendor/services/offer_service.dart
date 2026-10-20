import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/utils/geohash_utils.dart';
import '../../../data/demo_offer_repository.dart';
import '../../../data/firebase_offer_repository.dart';
import '../../../data/offer_repository.dart';
import '../../../models/offer_model.dart';
import '../../auth/services/auth_service.dart';

class OfferService {
  OfferService({required this.auth, required this.repository});
  final AuthService auth;
  final OfferRepository repository;
  static OfferService? _instance;
  static void install(OfferService service) { _instance = service; }
  static OfferService get instance {
    final auth = AuthService.instance;
    if (_instance == null || _instance!.auth != auth) {
      _instance = OfferService(
        auth: auth,
        repository: auth.isDemo
            ? DemoOfferRepository()
            : FirebaseOfferRepository(),
      );
    }
    return _instance!;
  }

  String newOfferId() => repository.newId();
  Stream<List<OfferModel>> watchVendorOffers(String uid) {
    auth.requireAccount(uid);
    return repository.watchVendor(uid).map((offers) {
      auth.requireAccount(uid);
      if (offers.any((offer) => offer.vendorId != uid)) {
        throw const AppFailure(
          'The server returned offers for another account.',
        );
      }
      return offers;
    });
  }

  Future<OfferModel> createOffer({
    required String title,
    required String description,
    required double oldPrice,
    required double newPrice,
    required String category,
    required int durationHours,
    String? offerId,
    String? imageUrl,
    Uint8List? imageBytes,
    String? imageFileName,
    double? latitude,
    double? longitude,
    String? geohash,
    ValueChanged<String>? onProgress,
  }) async {
    final uid = auth.identity?.uid;
    if (uid == null)
      throw const AppFailure('Sign in as a vendor before publishing.');
    final userModel = await auth.fetchUserProfile(uid);
    if (userModel == null || !userModel.isApprovedVendor) {
      throw const AppFailure(
        'Store approval is required before publishing offers.',
      );
    }
    final vendorProfile = await auth.fetchVendorProfile(uid);
    final lat = latitude ?? vendorProfile?.latitude;
    final lng = longitude ?? vendorProfile?.longitude;
    if (!GeohashUtils.isValidLocation(lat, lng)) {
      throw const AppFailure(
        'Your store location is missing or invalid. Update your business profile before publishing.',
      );
    }
    if (title.trim().isEmpty ||
        title.trim().length > 100 ||
        description.trim().length > 1000) {
      throw const AppFailure(
        'Enter a title of 1–100 characters and a description under 1000 characters.',
      );
    }
    if (!oldPrice.isFinite ||
        !newPrice.isFinite ||
        oldPrice <= 0 ||
        newPrice <= 0 ||
        newPrice > oldPrice) {
      throw const AppFailure(
        'Clearance price must be positive and cannot exceed the original price.',
      );
    }
    if (imageBytes != null && imageBytes.length > 5 * 1024 * 1024) {
      throw const AppFailure('Image file size must not exceed 5 MB.');
    }
    final id = offerId ?? repository.newId();
    final existing = await repository.fetch(id);
    auth.requireAccount(uid);
    if (existing != null) {
      if (existing.vendorId != uid)
        throw const AppFailure('This offer belongs to another account.');
      return existing;
    }
    UploadedImage? uploaded;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      onProgress?.call('Uploading image…');
      uploaded = await repository.upload(
        uid,
        id,
        imageBytes,
        imageFileName ?? '$id.jpg',
      );
      auth.requireAccount(uid);
    }
    final now = DateTime.now();
    final offer = OfferModel(
      id: id,
      vendorId: uid,
      title: title.trim(),
      description: description.trim(),
      oldPrice: oldPrice,
      newPrice: newPrice,
      imageUrl: uploaded?.url ?? imageUrl ?? '',
      latitude: lat!,
      longitude: lng!,
      geohash: GeohashUtils.encode(lat, lng),
      createdAt: now,
      expiryTime: now.add(
        Duration(hours: durationHours > 0 ? durationHours : 6),
      ),
      status: 'active',
    );
    onProgress?.call('Saving… waiting for server confirmation');
    try {
      final saved = await repository.save(offer);
      auth.requireAccount(uid);
      return saved;
    } catch (error) {
      // A lost response does not establish whether a commit reached the server.
      // Reconcile by ID before deleting an image or allowing the same-ID retry.
      OfferModel? confirmed;
      bool knownAbsent = false;
      try {
        confirmed = await repository.fetch(id);
        knownAbsent = confirmed == null;
      } catch (_) {
        /* Unknown outcome: retain uploaded object. */
      }
      if (confirmed != null && confirmed.vendorId == uid) {
        auth.requireAccount(uid);
        return confirmed;
      }
      String cleanup = '';
      if (knownAbsent && uploaded != null) {
        try {
          await repository.deleteUpload(uploaded);
        } catch (_) {
          cleanup = ' Image cleanup could not be confirmed.';
        }
      }
      throw AppFailure(
        '${errorMessage(error)}$cleanup Your form is retained; retry uses the same offer ID.',
      );
    }
  }
}
