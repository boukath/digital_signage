import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ NEW: Added Auth Import
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/kiosk_pairing_service.dart';
import 'kiosk_main_screen.dart';

class KioskBootScreen extends StatefulWidget {
  const KioskBootScreen({Key? key}) : super(key: key);

  @override
  State<KioskBootScreen> createState() => _KioskBootScreenState();
}

class _KioskBootScreenState extends State<KioskBootScreen> {
  final KioskPairingService _pairingService = KioskPairingService();
  Future<Map<String, String>>? _pairingFuture;
  bool _isCheckingLocalState = true;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _checkExistingPairing();
  }

  // 🛡️ Helper to ensure Auth is ready before we render screens that write data
  Future<void> _ensureAuthenticated() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        print("🟡 [AUTH] Warming up Anonymous Auth for Kiosk...");
        await FirebaseAuth.instance.signInAnonymously();
        print("🟢 [AUTH] Success! Kiosk UID: ${FirebaseAuth.instance.currentUser?.uid}");
      }
    } catch (e) {
      print("❌ [AUTH] Fatal Error: $e");
    }
  }

  Future<void> _checkExistingPairing() async {
    final String? clientId = await _pairingService.getPairedClientId();

    if (clientId != null && clientId.isNotEmpty) {
      print("⚡ Device already paired to Client ID: $clientId. Bypassing PIN...");

      // ✅ FIX: Wait for Auth before routing!
      await _ensureAuthenticated();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => KioskMainScreen(clientId: clientId)),
        );
      }
    } else {
      setState(() {
        _isCheckingLocalState = false;
        _pairingFuture = _pairingService.initializePairing();
      });
    }
  }

  void _handleSuccessfulPairing(String pin, String clientId) async {
    if (_isNavigating) return;
    _isNavigating = true;

    await _pairingService.finalizePairing(pin, clientId);

    // ✅ FIX: Wait for Auth before routing!
    await _ensureAuthenticated();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => KioskMainScreen(clientId: clientId)),
      );
    }
    print("✅ Successfully paired to Client ID: $clientId");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4A00E0),
              Color(0xFF8E2DE2),
              Color(0xFF00C9FF),
            ],
          ),
        ),
        child: _isCheckingLocalState
            ? Center(child: _buildGlassCard(child: const CircularProgressIndicator(color: Colors.white)))
            : FutureBuilder<Map<String, String>>(
          future: _pairingFuture,
          builder: (context, futureSnapshot) {

            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return Center(child: _buildGlassCard(
                child: const CircularProgressIndicator(color: Colors.white),
              ));
            }

            if (futureSnapshot.hasError) {
              return Center(child: _buildGlassCard(
                child: Text(
                  "Error: ${futureSnapshot.error}",
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                ),
              ));
            }

            final pin = futureSnapshot.data!['pin']!;

            return StreamBuilder<DocumentSnapshot>(
              stream: _pairingService.listenToPairingStatus(pin),
              builder: (context, streamSnapshot) {

                if (!streamSnapshot.hasData || !streamSnapshot.data!.exists) {
                  return Center(child: _buildGlassCard(
                    child: const CircularProgressIndicator(color: Colors.white),
                  ));
                }

                final data = streamSnapshot.data!.data() as Map<String, dynamic>;
                final status = data['status'];

                if (status == 'paired') {
                  final clientId = data['clientId'];

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _handleSuccessfulPairing(pin, clientId);
                  });

                  return Center(
                    child: _buildGlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 80),
                          const SizedBox(height: 20),
                          Text(
                            "Pairing Successful!",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Loading your media library...",
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Center(
                  child: _buildGlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Link this Display",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Enter this 6-digit PIN on your Web Dashboard",
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Text(
                            pin,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 80,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const CircularProgressIndicator(
                          color: Colors.white54,
                          strokeWidth: 2,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Waiting for secure handshake...",
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(60),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}