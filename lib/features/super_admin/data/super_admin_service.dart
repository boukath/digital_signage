// File: lib/features/super_admin/data/super_admin_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; // Required for the secondary app trick
import '../domain/tenant_model.dart';

class SuperAdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Tenant>> getClientsStream() {
    // ➔ CHANGED: Now reads from the 'clients' collection
    return _firestore.collection('clients').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Tenant.fromMap(doc.data(), doc.id)).toList();
    });
  }

  /// Documentation:
  /// Creates a secure Firebase Auth account AND a Firestore profile without logging
  /// the Super Admin out of their current session.
  Future<void> createClient({
    required String companyName,
    required String contactEmail,
    required String password,
    required String phoneNumber,
    required String address,
  }) async {
    FirebaseApp? tempApp;
    try {
      // 1. ADD TO FIREBASE AUTH: Create a temporary Firebase instance
      tempApp = await Firebase.initializeApp(
        name: 'TemporaryClientCreator',
        options: Firebase.app().options,
      );

      // Create the user account securely in Firebase Authentication
      UserCredential userCredential = await FirebaseAuth.instanceFor(app: tempApp)
          .createUserWithEmailAndPassword(email: contactEmail, password: password);

      // Get the unique secure ID Firebase generated for this new user
      String newClientId = userCredential.user!.uid;

      // Calculate strict license dates (Default: 1 Year from today)
      final DateTime startDate = DateTime.now();
      final DateTime endDate = DateTime(startDate.year + 1, startDate.month, startDate.day);

      // 2. ADD TO FIRESTORE DATABASE: Save business details into the 'clients' collection
      await _firestore.collection('clients').doc(newClientId).set({
        'companyName': companyName,
        'contactEmail': contactEmail,
        'phoneNumber': phoneNumber,
        'address': address,
        'isActive': true,
        'role': 'client',
        'createdAt': FieldValue.serverTimestamp(),
        'licenseStartDate': startDate.toIso8601String(),
        'licenseEndDate': endDate.toIso8601String(),
        'initialPassword': password,
      });

    } catch (e) {
      print('Error creating full client profile: $e');
      rethrow;
    } finally {
      // CRITICAL: Delete the temporary app so it doesn't leak memory
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  /// Documentation:
  /// Toggles the 'isActive' state. If true, becomes false (Paused).
  Future<void> toggleClientStatus(String clientId, bool currentStatus) async {
    try {
      await _firestore.collection('clients').doc(clientId).update({
        'isActive': !currentStatus,
      });
    } catch (e) {
      print('Error toggling status: $e');
      rethrow;
    }
  }

  /// Documentation:
  /// Deletes the client's profile from the database entirely.
  Future<void> deleteClient(String clientId) async {
    try {
      await _firestore.collection('clients').doc(clientId).delete();
    } catch (e) {
      print('Error deleting client: $e');
      rethrow;
    }
  }

  /// Documentation:
  /// Updates specific fields for an existing client (like extending their license date).
  Future<void> updateClientDetails(String clientId, Map<String, dynamic> updatedData) async {
    try {
      await _firestore.collection('clients').doc(clientId).update(updatedData);
    } catch (e) {
      print('Error updating client: $e');
      rethrow;
    }
  }

  // ==========================================
  // 🚀 NEW: GLOBAL FLEET UPDATE
  // ==========================================
  /// Documentation:
  /// Sends an 'update' command to EVERY screen across EVERY client simultaneously.
  /// Uses a Firestore Batch to ensure atomic operations.
  Future<void> deployGlobalUpdate(String downloadUrl) async {
    try {
      // 1. Get all clients
      final clientsSnap = await _firestore.collection('clients').get();

      // 2. We use a Batch to send commands to hundreds of screens simultaneously
      final batch = _firestore.batch();

      for (var clientDoc in clientsSnap.docs) {
        // Get all screens for this specific client
        final screensSnap = await clientDoc.reference.collection('screens').get();

        for (var screenDoc in screensSnap.docs) {
          // Attach the update command and the URL to the screen document
          batch.update(screenDoc.reference, {
            'pendingCommand': 'update',
            'updateUrl': downloadUrl,
          });
        }
      }

      // 3. Commit the batch! All screens will instantly trigger the download protocol.
      await batch.commit();
      print('✅ Global update command broadcasted to all screens.');

    } catch (e) {
      print('Error deploying global update: $e');
      throw Exception("Failed to deploy global update: $e");
    }
  }
}