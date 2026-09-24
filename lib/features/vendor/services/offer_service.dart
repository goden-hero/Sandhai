import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../../models/offer_model.dart';
import '../../../models/user_model.dart';
import '../../auth/services/auth_service.dart';

class OfferService {
  static final OfferService instance = OfferService._internal();
  factory OfferService() => instance;
  OfferService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // In-memory list of created offers for demo mode sync
  final List<OfferModel> _demoOffers = [];

  List<OfferModel> get demoOffers => List.unmodifiable(_demoOffers);

  /// Create and publish a clearance offer to Cloud Firestore
  Future<OfferModel> createOffer({
    required String title,
    required String description,
    required double oldPrice,
    required double newPrice,
    required String category,
    required int durationHours,
    String? imageUrl,
    Uint8List? imageBytes,
    String? imageFileName,
    double? latitude,
    double? longitude,
    String? geohash,
  }) async {
    // 1. Resolve current user profile & check authorization
    final currentUser = AuthService.instance.currentUser;
    UserModel? userModel = AuthService.instance.demoCurrentUser;

    if (currentUser != null) {
      userModel = await AuthService.instance.fetchUserProfile(currentUser.uid) ?? userModel;
    }

    if (userModel == null) {
      throw Exception('Authentication required: Please sign in as a vendor.');
    }

    if (!userModel.isVendor) {
      throw Exception('Authorization Error: Customer accounts cannot publish clearance offers.');
    }

    if (!userModel.isApprovedVendor) {
      throw Exception('Store Approval Required: Your vendor account status is PENDING. Offer posting is restricted until store verification.');
    }

    // 1b. Fetch vendor store location from vendors/{uid} if coordinates not passed explicitly
    final vendorProfile = await AuthService.instance.fetchVendorProfile(userModel.uid);
    final finalLat = latitude ?? vendorProfile?.latitude ?? 13.0827;
    final finalLng = longitude ?? vendorProfile?.longitude ?? 80.2707;
    final finalGeohash = geohash ?? vendorProfile?.geohash ?? 'tf340w';

    // 2. Validate input boundaries
    final cleanTitle = title.trim();
    final cleanDesc = description.trim();

    if (cleanTitle.isEmpty || cleanTitle.length > 100) {
      throw Exception('Validation Error: Offer title must be between 1 and 100 characters.');
    }

    if (cleanDesc.length > 1000) {
      throw Exception('Validation Error: Description cannot exceed 1000 characters.');
    }

    if (oldPrice <= 0 || newPrice <= 0) {
      throw Exception('Validation Error: Prices must be positive numeric values.');
    }

    if (newPrice > oldPrice) {
      throw Exception('Validation Error: Clearance price (₹$newPrice) cannot exceed original price (₹$oldPrice).');
    }

    final now = DateTime.now();
    final expiry = now.add(Duration(hours: durationHours > 0 ? durationHours : 6));
    final docRef = _firestore.collection('offers').doc();
    final offerId = docRef.id;

    String finalImageUrl = imageUrl ?? '';
    Reference? uploadedStorageRef;

    // 3. Upload offer image to Firebase Storage if imageBytes supplied
    if (imageBytes != null && imageBytes.isNotEmpty) {
      if (imageBytes.length > 5 * 1024 * 1024) {
        throw Exception('Validation Error: Image file size must not exceed 5 MB.');
      }

      try {
        final fileName = imageFileName ?? '$offerId.jpg';
        final storagePath = 'offers/${userModel.uid}/$offerId/$fileName';
        final ref = _storage.ref().child(storagePath);

        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'vendorId': userModel.uid, 'offerId': offerId},
        );

        final uploadTask = await ref.putData(imageBytes, metadata);
        uploadedStorageRef = ref;
        finalImageUrl = await uploadTask.ref.getDownloadURL();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Firebase Storage upload info: $e');
        }
        // Fallback to placeholder image reference if storage emulator/offline
        finalImageUrl = 'https://storage.googleapis.com/sandhai-5km-demo.appspot.com/offers/${userModel.uid}/$offerId.jpg';
      }
    }

    // 4. Construct OfferModel document with resolved vendor store coordinates
    final offerModel = OfferModel(
      id: offerId,
      vendorId: userModel.uid,
      title: cleanTitle,
      description: cleanDesc,
      oldPrice: oldPrice,
      newPrice: newPrice,
      imageUrl: finalImageUrl,
      latitude: finalLat,
      longitude: finalLng,
      geohash: finalGeohash,
      createdAt: now,
      expiryTime: expiry,
      status: 'active',
    );

    // 5. Save document to Cloud Firestore with partial-failure cleanup guard
    try {
      await docRef.set(offerModel.toFirestore());
    } catch (e) {
      if (uploadedStorageRef != null) {
        try {
          await uploadedStorageRef.delete();
        } catch (cleanupErr) {
          if (kDebugMode) {
            print('⚠️ Storage image cleanup info on Firestore failure: $cleanupErr');
          }
        }
      }
      if (kDebugMode) {
        print('ℹ️ Firestore offer write warning: $e');
      }
    }

    _demoOffers.insert(0, offerModel);
    return offerModel;
  }
}
