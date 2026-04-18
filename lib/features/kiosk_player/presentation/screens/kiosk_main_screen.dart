// File: lib/features/kiosk_player/presentation/screens/kiosk_main_screen.dart

import 'dart:async';
import 'dart:io'; // Required to completely exit the Windows app
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Import your views
import 'screensaver_view.dart';
import 'interactive_catalog_view.dart';
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

  // --- Secret Menu Variables (Top-Right: Unpair) ---
  int _secretTapCount = 0;
  Timer? _secretTapTimer;
  final KioskPairingService _pairingService = KioskPairingService();

  // --- Secret Menu Variables (Top-Left: Close App) ---
  int _secretCloseTapCount = 0;
  Timer? _secretCloseTapTimer;

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

  // ==========================================
  // TOP-RIGHT LOGIC: UNPAIR SCREEN
  // ==========================================
  void _handleSecretAdminTap() {
    _secretTapCount++;
    _secretTapTimer?.cancel();
    _secretTapTimer = Timer(const Duration(seconds: 2), () {
      _secretTapCount = 0; // Reset if they are too slow
    });

    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      _showAdminDialog();
    }
  }

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
                Navigator.of(context).pop();
                await _pairingService.unpairDevice();
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

  // ==========================================
  // TOP-LEFT LOGIC: CLOSE APP
  // ==========================================
  void _handleSecretCloseTap() {
    _secretCloseTapCount++;
    _secretCloseTapTimer?.cancel();
    _secretCloseTapTimer = Timer(const Duration(seconds: 2), () {
      _secretCloseTapCount = 0; // Reset if they are too slow
    });

    if (_secretCloseTapCount >= 5) {
      _secretCloseTapCount = 0;
      _showCloseDialog();
    }
  }

  void _showCloseDialog() {
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
          title: Text("Exit Application", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            "Do you want to completely close the Digital Signage application and return to the Windows Desktop?",
            style: GoogleFonts.poppins(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                exit(0); // This instantly closes the Windows Application
              },
              child: Text("Close App", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
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
    _secretCloseTapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Listener(
        onPointerDown: (_) => _handleUserInteraction(),
        onPointerMove: (_) => _handleUserInteraction(),
        onPointerUp: (_) => _handleUserInteraction(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // STATE A: The Passive Screensaver
            ScreensaverView(
                clientId: widget.clientId,
                isPaused: _isInteractiveMode
            ),

            // STATE B: The Interactive Catalog
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

            // 🛡️ SECRET BUTTON: TOP-RIGHT (UNPAIR)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // 👈 Ensures it catches taps even with transparent background
                onTap: _handleSecretAdminTap,
                child: Container(
                  width: 50, // 👈 FIXED: Shrunk from 120 to 50 so it sits in the absolute corner
                  height: 50,
                  color: Colors.transparent,
                ),
              ),
            ),

            // 🌟 SECRET BUTTON: TOP-LEFT (CLOSE APP)
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque, // 👈 Ensures it catches taps even with transparent background
                onTap: _handleSecretCloseTap,
                child: Container(
                  width: 50, // 👈 FIXED: Shrunk from 120 to 50 to avoid overlapping the "Back to Aisle" button!
                  height: 50,
                  color: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}