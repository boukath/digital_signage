import 'dart:async';
import 'package:flutter/material.dart';

// Import your views
import 'screensaver_view.dart';
import 'interactive_catalog_view.dart'; // NEW: We added this import!

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

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // The Listener catches EVERY tap, swipe, or scroll on the entire TV screen
      body: Listener(
        onPointerDown: (_) => _handleUserInteraction(),
        onPointerMove: (_) => _handleUserInteraction(), // Captures 3D model spinning!
        onPointerUp: (_) => _handleUserInteraction(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // ==========================================
            // STATE A: The Passive Screensaver
            // Always running in background, but pauses decoding when hidden
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
              duration: const Duration(milliseconds: 600), // Smooth premium fade
              child: IgnorePointer(
                // Ignore touches if it's invisible so it doesn't block the screensaver
                ignoring: !_isInteractiveMode,
                // Replace the temporary dark overlay with our new Interactive UI!
                child: InteractiveCatalogView(
                  clientId: widget.clientId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}