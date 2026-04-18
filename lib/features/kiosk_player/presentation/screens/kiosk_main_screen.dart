// File: lib/features/kiosk_player/presentation/screens/kiosk_main_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Import your views
import 'screensaver_view.dart';
import 'interactive_catalog_view.dart';
// 👈 NEW IMPORTS FOR UNPAIRING
import '../../data/kiosk_pairing_service.dart';
import 'kiosk_boot_screen.dart';

class KioskMainScreen extends StatefulWidget {
  final String clientId;
  const KioskMainScreen({super.key, required this.clientId});

  @override
  State<KioskMainScreen> createState() => _KioskMainScreenState();
}

class _KioskMainScreenState extends State<KioskMainScreen> {
  bool _isInteractiveMode = false;
  Timer? _idleTimer;
  final int _idleTimeoutSeconds = 30;

  // 👈 NEW: Secret Menu Variables
  int _secretTapCount = 0;
  Timer? _secretTapTimer;
  final KioskPairingService _pairingService = KioskPairingService();

  @override
  void initState() {
    super.initState();
    // App starts in Passive Screensaver Mode
  }

  // Called whenever the user touches the screen
  void _handleUserInteraction() {
    if (!_isInteractiveMode) {
      setState(() => _isInteractiveMode = true);
      debugPrint("👆 Screen Touched! Switching to Interactive State B");
    }

    // Reset the idle timer every time they tap or interact
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(seconds: _idleTimeoutSeconds), _returnToScreensaver);
  }

  // Called when the idle timer expires
  void _returnToScreensaver() {
    if (_isInteractiveMode) {
      setState(() => _isInteractiveMode = false);
      debugPrint("⏱️ Idle Timeout. Returning to Passive State A");
    }
  }

  // 👈 NEW: Handles the 5 rapid taps in the top right corner
  void _handleSecretAdminTap() {
    _secretTapCount++;

    // Cancel the old timer and start a new 2-second window
    _secretTapTimer?.cancel();
    _secretTapTimer = Timer(const Duration(seconds: 2), () {
      _secretTapCount = 0; // Reset if they are too slow
    });

    if (_secretTapCount >= 5) {
      _secretTapCount = 0; // Reset counter
      _showAdminDialog();  // Trigger the secret menu!
    }
  }

  // 👈 NEW: The Secret Unpair Menu
  void _showAdminDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24, width: 2),
          ),
          title: Text("Secret Admin Menu", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            "Do you want to unpair this screen from the current account? This will return the screen to the PIN pairing mode.",
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                Navigator.of(context).pop(); // Close dialog

                // 1. Clear the saved Client ID from storage
                await _pairingService.unpairDevice();

                // 2. Route the screen back to the Boot/PIN screen
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const KioskBootScreen()),
                  );
                }
              },
              child: Text("Unpair Screen", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _secretTapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // The Listener catches EVERY tap, swipe, or scroll on the entire TV screen
      body: Listener(
        onPointerDown: (_) => _handleUserInteraction(),
        onPointerMove: (_) => _handleUserInteraction(),
        onPointerUp: (_) => _handleUserInteraction(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // ==========================================
            // STATE A: The Passive Screensaver
            // ==========================================
            ScreensaverView(
                clientId: widget.clientId,
                isPaused: _isInteractiveMode
            ),

            // ==========================================
            // STATE B: The Interactive Catalog
            // ==========================================
            AnimatedOpacity(
              opacity: _isInteractiveMode ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: IgnorePointer(
                ignoring: !_isInteractiveMode,
                child: InteractiveCatalogView(
                  clientId: widget.clientId,
                ),
              ),
            ),

            // ==========================================
            // 🛡️ SECRET ADMIN BUTTON
            // ==========================================
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: _handleSecretAdminTap,
                child: Container(
                  width: 120,
                  height: 120,
                  color: Colors.transparent, // Completely invisible!
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}