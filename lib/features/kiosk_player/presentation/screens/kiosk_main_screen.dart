// File: lib/features/kiosk_player/presentation/screens/kiosk_main_screen.dart

import 'dart:async';
import 'dart:io'; // Required for Process and exit
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Needed for kIsWeb
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // NEW: For listening to commands
import 'package:shared_preferences/shared_preferences.dart'; // NEW: To get the hardware Screen ID

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

  // 🌟 NEW: Subscription for Remote Commands
  StreamSubscription? _remoteCommandSubscription;

  @override
  void initState() {
    super.initState();
    // App starts in Passive Screensaver Mode
    // Start listening for dashboard commands immediately!
    _listenForRemoteCommands();
  }

  // ==========================================
  // 🌟 NEW: REMOTE COMMAND LISTENER
  // ==========================================
  Future<void> _listenForRemoteCommands() async {
    try {
      // 1. Get this specific hardware's Screen ID
      final prefs = await SharedPreferences.getInstance();
      final screenId = prefs.getString('screen_id');

      if (screenId == null) {
        debugPrint("⚠️ [COMMAND] No Screen ID found. Cannot listen for commands.");
        return;
      }

      debugPrint("📡 [COMMAND] Listening for remote commands on Screen ID: $screenId");

      // 2. Listen to this specific screen's document in Firestore
      _remoteCommandSubscription = FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('screens')
          .doc(screenId)
          .snapshots()
          .listen((snapshot) async {

        if (!snapshot.exists || !snapshot.data()!.containsKey('pendingCommand')) return;

        final data = snapshot.data()!;
        final command = data['pendingCommand'];

        if (command != null) {
          debugPrint("🚨 [COMMAND] RECEIVED REMOTE COMMAND: $command");

          // 3. ACKNOWLEDGE: Clear the command immediately so we don't loop!
          await snapshot.reference.update({'pendingCommand': null});

          // 4. EXECUTE THE COMMAND
          if (command == 'reboot') {
            _executeSystemReboot();
          }
          // You can add logic for 'force_sync' and 'clear_cache' here in the future
        }
      });
    } catch (e) {
      debugPrint("❌ [COMMAND] Failed to set up command listener: $e");
    }
  }

  // ==========================================
  // 🔄 NEW: NATIVE WINDOWS REBOOT
  // ==========================================
  void _executeSystemReboot() {
    debugPrint("🔄 [SYSTEM] Initiating Hardware Reboot...");

    if (!kIsWeb && Platform.isWindows) {
      // Uses the native Windows CMD to force a restart instantly
      // /r = restart, /f = force close apps, /t 0 = zero seconds delay
      Process.run('shutdown', ['/r', '/f', '/t', '0']).then((result) {
        debugPrint("💻 Windows shutdown command sent.");
      }).catchError((e) {
        debugPrint("❌ Failed to reboot Windows: $e");
      });
    } else {
      // Fallback for testing on Mac/Linux (just closes the app)
      exit(0);
    }
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
    // 🌟 Clean up our remote listener!
    _remoteCommandSubscription?.cancel();
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
                behavior: HitTestBehavior.opaque, // Ensures it catches taps even with transparent background
                onTap: _handleSecretAdminTap,
                child: Container(
                  width: 50,
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
                behavior: HitTestBehavior.opaque, // Ensures it catches taps even with transparent background
                onTap: _handleSecretCloseTap,
                child: Container(
                  width: 50,
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