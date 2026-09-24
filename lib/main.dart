import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'app/app.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle Firebase initialization gracefully in local dev / demo mode
  bool isFirebaseConnected = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Connect to Firebase Emulators when running locally in debug mode
    if (kDebugMode) {
      const host = kIsWeb ? 'localhost' : '10.0.2.2';
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      await FirebaseStorage.instance.useStorageEmulator(host, 9199);
    }
    isFirebaseConnected = true;
    if (kDebugMode) {
      print('✅ Firebase & Emulators initialized successfully.');
    }
  } catch (e) {
    if (kDebugMode) {
      print('ℹ️ Running 5KM Sandhai in Standalone Demo Mode (Firebase omitted or not configured yet): $e');
    }
  }

  runApp(SandhaiApp(isFirebaseConnected: isFirebaseConnected));
}
