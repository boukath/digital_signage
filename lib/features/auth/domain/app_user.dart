// File: lib/features/auth/domain/app_user.dart

import 'package:cloud_firestore/cloud_firestore.dart'; // NEW: We need this to check for Timestamps

/// Documentation:
/// This class represents a custom user in our Digital Signage app.
class AppUser {
  final String uid;
  final String? email;
  final String role;
  final bool isPaused;
  final DateTime? licenseEndDate;

  AppUser({
    required this.uid,
    this.email,
    this.role = 'client',
    this.isPaused = false,
    this.licenseEndDate,
  });

  /// Documentation:
  /// A factory constructor to easily create our custom AppUser
  /// from a standard Firebase Auth user AND their Firestore document data.
  factory AppUser.fromFirebaseAndFirestore(
      dynamic firebaseUser,
      Map<String, dynamic>? firestoreData,
      ) {

    // --- NEW FIX: Safely handle String Dates vs Timestamp Dates ---
    DateTime? parsedEndDate;
    if (firestoreData != null && firestoreData['licenseEndDate'] != null) {
      final dateData = firestoreData['licenseEndDate'];

      if (dateData is Timestamp) {
        parsedEndDate = dateData.toDate(); // If it's a Firebase Timestamp
      } else if (dateData is String) {
        parsedEndDate = DateTime.tryParse(dateData); // If it's saved as a String
      }
    }
    // --------------------------------------------------------------

    return AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      role: firestoreData?['role'] ?? 'client',

      // Note: Your database uses 'isActive: true', but our code looks for 'isPaused'.
      // If 'isPaused' is missing, this safely defaults to 'false', which is perfect.
      isPaused: firestoreData?['isPaused'] ?? false,

      licenseEndDate: parsedEndDate, // Uses our newly parsed safe date!
    );
  }

  bool get isLicenseExpired {
    if (licenseEndDate == null) return false;
    return DateTime.now().isAfter(licenseEndDate!);
  }
}