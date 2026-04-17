// File: lib/features/auth/data/auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/app_user.dart';

/// Documentation:
/// This service handles all communication with Firebase Authentication
/// AND fetches the corresponding user data from Firestore across multiple collections.
class AuthService {
  FirebaseAuth get _firebaseAuth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Documentation:
  /// Private helper method to search for a user's profile.
  /// It checks the 'admins' collection first. If not found, it checks 'clients'.
  Future<Map<String, dynamic>?> _fetchUserData(String uid) async {
    try {
      // 1. Check Admins Collection
      DocumentSnapshot adminDoc = await _firestore.collection('admins').doc(uid).get();
      if (adminDoc.exists) {
        return adminDoc.data() as Map<String, dynamic>?;
      }

      // 2. Check Clients Collection
      DocumentSnapshot clientDoc = await _firestore.collection('clients').doc(uid).get();
      if (clientDoc.exists) {
        return clientDoc.data() as Map<String, dynamic>?;
      }

      // 3. User not found in either collection
      return null;
    } catch (e) {
      print('Error fetching user data from Firestore: $e');
      return null;
    }
  }

  /// Documentation:
  /// This creates a 'Stream' that listens continuously to Firebase.
  Stream<AppUser?> get userStateStream {
    return _firebaseAuth.authStateChanges().asyncMap((User? firebaseUser) async {
      if (firebaseUser == null) {
        return null;
      }

      // Use our new helper method to find the user in the correct collection
      Map<String, dynamic>? firestoreData = await _fetchUserData(firebaseUser.uid);

      return AppUser.fromFirebaseAndFirestore(firebaseUser, firestoreData);
    });
  }

  /// Documentation:
  /// Attempts to sign in a user using their email and password.
  Future<AppUser?> signInWithEmail(String email, String password) async {
    try {
      UserCredential credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Fetch custom data from either 'admins' or 'clients'
        Map<String, dynamic>? firestoreData = await _fetchUserData(credential.user!.uid);
        return AppUser.fromFirebaseAndFirestore(credential.user!, firestoreData);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.message}');
      rethrow;
    }
  }

  /// Documentation:
  /// Securely logs the user out of the app.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}