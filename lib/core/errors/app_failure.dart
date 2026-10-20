import 'package:firebase_core/firebase_core.dart';

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String errorMessage(Object error) {
  if (error is AppFailure) return error.message;
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' || 'unauthorized' => 'The server rejected this operation. Check your account approval and permissions, then retry.',
      'unavailable' || 'network-request-failed' || 'retry-limit-exceeded' => 'Could not confirm the save with the server. Check your connection and retry.',
      'email-already-in-use' => 'An account already exists. Sign in to finish any incomplete registration.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Invalid email or password.',
      'weak-password' => 'Use a password with at least 6 characters.',
      'invalid-email' => 'Enter a valid email address.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      _ => error.message ?? 'The operation failed. Please retry.',
    };
  }
  return error.toString().replaceFirst('Exception: ', '');
}
