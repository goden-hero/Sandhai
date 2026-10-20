import '../../../core/images/offer_draft_store.dart';
import '../../../core/images/selected_image.dart';
import '../../../core/constants/offer_categories.dart';

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
  final _uploads = <String, UploadedImage>{};
  final _inFlight = <String>{};
  static OfferService? _instance;
  static void install(OfferService service) {
    _instance = service;
  }

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
    ValueChanged<String>? onProgress,
  }) async {
    final uid = auth.identity?.uid;
    if (uid == null) {
      throw const AppFailure('Sign in as a vendor before publishing.');
    }
    final userModel = await auth.fetchUserProfile(uid);
    if (userModel == null || !userModel.isApprovedVendor) {
      throw const AppFailure(
        'Store approval is required before publishing offers.',
      );
    }
    final vendorProfile = await auth.fetchVendorProfile(uid);
    final lat = vendorProfile?.latitude;
    final lng = vendorProfile?.longitude;
    if (vendorProfile?.hasConfirmedLocation != true ||
        !GeohashUtils.isValidLocation(lat, lng)) {
      throw const AppFailure(
        'Your store location needs confirmation. Update your business profile before publishing.',
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
    if (!OfferCategories.ids.contains(category)) {
      throw const AppFailure('Select a valid offer category.');
    }
    if (durationHours <= 0 || durationHours > 24) {
      throw const AppFailure('Choose a validity of 1–24 hours.');
    }
    final image = imageBytes == null
        ? null
        : await SelectedImage.validate(imageBytes);
    final id = offerId ?? repository.newId();
    final existing = await repository.fetch(id);
    auth.requireAccount(uid);
    if (existing != null) {
      if (existing.vendorId != uid) {
        throw const AppFailure('This offer belongs to another account.');
      }
      _uploads.remove('$uid/$id');
      try {
        await OfferDraftStore.instance.forgetUpload(uid, id);
      } catch (_) {
        /* Confirmed saved object must stay referenced. */
      }
      return existing;
    }
    final key = '$uid/$id';
    if (!_inFlight.add(key)) {
      throw const AppFailure('This offer is already being saved. Please wait.');
    }
    try {
      _uploads[key] ??=
          await OfferDraftStore.instance.pendingUpload(uid, id) ??
          const UploadedImage('', '');
      if (_uploads[key]!.path.isEmpty) _uploads.remove(key);
      final cached = _uploads[key];
      if (cached != null &&
          (image == null || !cached.path.endsWith('/${image.filename}'))) {
        try {
          await repository.deleteUpload(cached);
          _uploads.remove(key);
          await OfferDraftStore.instance.forgetUpload(uid, id);
        } catch (e) {
          throw AppFailure(
            'The previous unreferenced photo could not be cleaned up. Retry before replacing it. ${errorMessage(e)}',
          );
        }
      }
      UploadedImage? uploaded = _uploads[key];
      if (image != null && (uploaded == null || uploaded.url.isEmpty)) {
        // Record the deterministic candidate before starting Storage. If the
        // activity/process dies, a same-ID retry can still reconcile or clean it.
        final candidate = UploadedImage(
          'offers/$uid/$id/${image.filename}',
          '',
        );
        await OfferDraftStore.instance.rememberUpload(uid, id, candidate);
        _uploads[key] = candidate;
        onProgress?.call('Uploading image…');
        uploaded = await repository.upload(
          uid,
          id,
          image.bytes,
          image.filename,
        );
        _uploads[key] = uploaded;
        await OfferDraftStore.instance.rememberUpload(uid, id, uploaded);
        try {
          auth.requireAccount(uid);
        } catch (_) {
          // No document write has started, so this upload is unreferenced.
          try {
            await repository.deleteUpload(uploaded);
            _uploads.remove(key);
            await OfferDraftStore.instance.forgetUpload(uid, id);
          } catch (_) {
            throw const AppFailure(
              'Account changed before publication. The unreferenced photo could not be cleaned up; sign in to its owner account to retry.',
            );
          }
          rethrow;
        }
      }
      final now = DateTime.now();
      final offer = OfferModel(
        id: id,
        vendorId: uid,
        title: title.trim(),
        description: description.trim(),
        oldPrice: oldPrice,
        newPrice: newPrice,
        imageUrl: uploaded?.url ?? '',
        imagePath: uploaded?.path,
        imageContentType: image?.contentType,
        imageSize: image?.bytes.length.toDouble(),
        category: category,
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
        _uploads.remove(key);
        try {
          await OfferDraftStore.instance.forgetUpload(uid, id);
        } catch (_) {
          /* Same-ID reconciliation remains safe. */
        }
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
          _uploads.remove(key);
          try {
            await OfferDraftStore.instance.forgetUpload(uid, id);
          } catch (_) {
            /* Saved image stays referenced. */
          }
          return confirmed;
        }
        String cleanup = knownAbsent
            ? ''
            : ' Save outcome is uncertain; the image is retained until the same-ID retry can check the server.';
        if (knownAbsent && uploaded != null) {
          try {
            await repository.deleteUpload(uploaded);
            _uploads.remove(key);
            await OfferDraftStore.instance.forgetUpload(uid, id);
          } catch (_) {
            cleanup = ' Image cleanup could not be confirmed.';
          }
        }
        throw AppFailure(
          '${errorMessage(error)}$cleanup Your form is retained; retry uses the same offer ID.',
        );
      }
    } finally {
      _inFlight.remove(key);
    }
  }
}
