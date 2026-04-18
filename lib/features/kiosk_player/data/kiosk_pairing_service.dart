// File: lib/features/kiosk_player/data/kiosk_pairing_service.dart

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class KioskPairingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if the device is already paired
  Future<String?> getPairedClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('paired_client_id');
  }

  // Generate a random 6-digit PIN
  String generatePin() {
    final random = Random.secure();
    final values = List<int>.generate(6, (i) => random.nextInt(10));
    return values.join();
  }

  // Initialize the pairing process and return the PIN
  Future<Map<String, String>> initializePairing() async {
    final prefs = await SharedPreferences.getInstance();

    // Generate unique Screen ID if it doesn't exist
    String screenId = prefs.getString('screen_id') ?? Uuid().v4();
    await prefs.setString('screen_id', screenId);

    final String pin = generatePin();

    // Create the pending pairing document
    await _firestore.collection('pairing_codes').doc(pin).set({
      'pin': pin,
      'screenId': screenId,
      'status': 'pending',
      'clientId': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return {'pin': pin, 'screenId': screenId};
  }

  // Stream to listen for the Web Dashboard handshake
  Stream<DocumentSnapshot> listenToPairingStatus(String pin) {
    return _firestore.collection('pairing_codes').doc(pin).snapshots();
  }

  // Finalize pairing locally once the stream detects success
  Future<void> finalizePairing(String pin, String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paired_client_id', clientId);

    // 🛑 REMOVED THIS LINE TO FIX WINDOWS THREADING CRASH 🛑
    // await _firestore.collection('pairing_codes').doc(pin).delete();

    print("💾 Local storage updated with Client ID.");
  }

  // 🔓 NEW: Clears the saved pairing data so the device can be paired again
  Future<void> unpairDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('paired_client_id');
    print("🗑️ Device unpaired. SharedPreferences cleared.");
  }
}