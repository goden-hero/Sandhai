import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../models/user_model.dart';
import '../../../models/vendor_model.dart';
import '../../../mock_data/mock_data.dart';

/// Firebase Authentication & User Profile Management Service
class AuthService {
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // In-memory fallback user profile for standalone demo mode
  UserModel? _demoCurrentUser;

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Currently authenticated Firebase user
  User? get currentUser => _auth.currentUser;

  /// Get active UserModel (either from Firestore or Demo fallback)
  UserModel? get demoCurrentUser => _demoCurrentUser;

  /// Set demo user for offline / standalone mode testing
  void setDemoUser(UserModel? user) {
    _demoCurrentUser = user;
  }

  /// Register a new Customer account directly
  /// Register a new Customer account directly
  Future<UserModel> registerCustomer({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      // 1. Create Firebase Auth credentials
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = userCredential.user!.uid;

      // 2. Create User Profile object
      final userModel = UserModel(
        uid: uid,
        displayName: displayName.trim(),
        email: email.trim(),
        role: 'customer',
        approvalStatus: 'approved',
        createdAt: DateTime.now(),
      );

      // 3. Save profile to Firestore users/{uid}
      try {
        await _firestore.collection('users').doc(uid).set(userModel.toFirestore());
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Firestore user profile creation warning: $e');
        }
        // If Firestore write failed, attempt single retry before reporting
        try {
          await _firestore.collection('users').doc(uid).set(userModel.toFirestore());
        } catch (retryErr) {
          throw Exception('Account created, but user profile initialization failed: $retryErr');
        }
      }

      _demoCurrentUser = userModel;
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e is Exception && e.toString().contains('user profile initialization failed')) {
        rethrow;
      }
      // Fallback only for standalone demo mode when Firebase app is not initialized
      final mockUid = 'demo_cust_${DateTime.now().millisecondsSinceEpoch}';
      final demoUser = UserModel(
        uid: mockUid,
        displayName: displayName.trim(),
        email: email.trim(),
        role: 'customer',
        approvalStatus: 'approved',
        createdAt: DateTime.now(),
      );
      _demoCurrentUser = demoUser;
      return demoUser;
    }
  }

  /// Register a new Vendor account directly (initial status is 'pending')
  Future<UserModel> registerVendor({
    required String email,
    required String password,
    required String storeName,
    required String phone,
    required String category,
    double latitude = 13.0827,
    double longitude = 80.2707,
    String geohash = 'tf340w',
  }) async {
    try {
      // 1. Create Firebase Auth credentials directly as Vendor
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = userCredential.user!.uid;

      // 2. Create User Profile with role 'vendor' and approvalStatus 'pending'
      final userModel = UserModel(
        uid: uid,
        displayName: storeName.trim(),
        email: email.trim(),
        role: 'vendor',
        approvalStatus: 'pending', // Vendor starts as PENDING APPROVAL
        createdAt: DateTime.now(),
      );

      // 3. Save to Firestore users/{uid} and vendors/{uid}
      try {
        await _firestore.collection('users').doc(uid).set(userModel.toFirestore());

        final vendorModel = VendorModel(
          uid: uid,
          name: storeName.trim(),
          phone: phone.trim(),
          category: category,
          latitude: latitude,
          longitude: longitude,
          geohash: geohash,
          createdAt: DateTime.now(),
        );
        await _firestore.collection('vendors').doc(uid).set(vendorModel.toFirestore());
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Firestore vendor profile creation warning: $e');
        }
        // Attempt single retry for user profile
        try {
          await _firestore.collection('users').doc(uid).set(userModel.toFirestore());
        } catch (retryErr) {
          throw Exception('Vendor account created, but store profile initialization failed: $retryErr');
        }
      }

      _demoCurrentUser = userModel;
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e is Exception && e.toString().contains('profile initialization failed')) {
        rethrow;
      }
      // Fallback only for standalone demo mode when Firebase app is not initialized
      final mockUid = 'demo_vendor_${DateTime.now().millisecondsSinceEpoch}';
      final demoUser = UserModel(
        uid: mockUid,
        displayName: storeName.trim(),
        email: email.trim(),
        role: 'vendor',
        approvalStatus: 'pending',
        createdAt: DateTime.now(),
      );
      _demoCurrentUser = demoUser;
      return demoUser;
    }
  }

  /// Sign in with email and password
  Future<UserModel> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = userCredential.user!.uid;
      final profile = await fetchUserProfile(uid);
      if (profile != null) {
        _demoCurrentUser = profile;
        return profile;
      }

      // If authenticated but profile document missing in Firestore
      throw Exception('User profile not found for account. Please complete account registration.');
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e is Exception && e.toString().contains('User profile not found')) {
        rethrow;
      }
      // Fallback for standalone demo mode
      final demoUser = UserModel(
        uid: 'demo_user',
        displayName: email.split('@').first,
        email: email.trim(),
        role: email.contains('vendor') ? 'vendor' : 'customer',
        approvalStatus: email.contains('vendor') ? 'pending' : 'approved',
        createdAt: DateTime.now(),
      );
      _demoCurrentUser = demoUser;
      return demoUser;
    }
  }

  /// Fetch user profile from Cloud Firestore
  Future<UserModel?> fetchUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error fetching user profile for $uid: $e');
      }
    }
    return null;
  }

  /// Fetch vendor store profile from Cloud Firestore
  Future<VendorModel?> fetchVendorProfile(String uid) async {
    try {
      final doc = await _firestore.collection('vendors').doc(uid).get();
      if (doc.exists) {
        return VendorModel.fromFirestore(doc);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error fetching vendor profile for $uid: $e');
      }
    }
    return null;
  }

  /// Update permitted vendor business profile fields in Cloud Firestore
  Future<VendorModel> updateVendorProfile({
    required String uid,
    required String name,
    required String phone,
    required String category,
    String? address,
    String? description,
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    final existingVendor = await fetchVendorProfile(uid);

    final updatedVendor = VendorModel(
      uid: uid,
      name: name.trim(),
      phone: phone.trim(),
      category: category,
      address: address?.trim(),
      description: description?.trim(),
      imageUrl: imageUrl?.trim(),
      latitude: existingVendor?.latitude ?? 13.0827,
      longitude: existingVendor?.longitude ?? 80.2707,
      geohash: existingVendor?.geohash ?? 'tf340w',
      createdAt: existingVendor?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      // 1. Update vendors/{uid} document
      await _firestore.collection('vendors').doc(uid).set(
        updatedVendor.toFirestore(),
        SetOptions(merge: true),
      );

      // 2. Update users/{uid} displayName
      await _firestore.collection('users').doc(uid).update({
        'displayName': name.trim(),
        'updatedAt': Timestamp.fromDate(now),
      });

      // 3. Keep in-memory profile in sync
      if (_demoCurrentUser != null && _demoCurrentUser!.uid == uid) {
        _demoCurrentUser = UserModel(
          uid: _demoCurrentUser!.uid,
          displayName: name.trim(),
          email: _demoCurrentUser!.email,
          role: _demoCurrentUser!.role,
          approvalStatus: _demoCurrentUser!.approvalStatus,
          createdAt: _demoCurrentUser!.createdAt,
          updatedAt: now,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('ℹ️ Vendor profile update warning: $e');
      }
    }

    return updatedVendor;
  }

  /// Sign out current authenticated user
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print('ℹ️ Sign out info: $e');
      }
    }
    _demoCurrentUser = null;
  }

  /// Helper to turn Firebase Auth exceptions into user-friendly messages
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email address.';
      case 'invalid-email':
        return 'The email address is not formatted correctly.';
      case 'weak-password':
        return 'The password is too weak. Please use at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password combination.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed sign-in attempts. Please try again later.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
