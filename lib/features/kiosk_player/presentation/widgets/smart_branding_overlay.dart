// File: lib/features/kiosk_player/presentation/widgets/smart_branding_overlay.dart

import 'dart:ui'; // Needed for ImageFilter (Frosted Glass)
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmartBrandingOverlay extends StatefulWidget {
  final bool isInteractive;

  const SmartBrandingOverlay({
    super.key,
    required this.isInteractive,
  });

  @override
  State<SmartBrandingOverlay> createState() => _SmartBrandingOverlayState();
}

class _SmartBrandingOverlayState extends State<SmartBrandingOverlay> {
  String _screenId = "UNKNOWN_SCREEN";

  @override
  void initState() {
    super.initState();
    _loadHardwareAnalyticsId();
  }

  /// Fetches the unique ID of this specific physical machine
  Future<void> _loadHardwareAnalyticsId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _screenId = prefs.getString('screen_id') ?? "UNKNOWN_SCREEN";
    });
  }

  @override
  Widget build(BuildContext context) {
    // ==========================================
    // 1. HARDWARE DETECTION
    // ==========================================
    final size = MediaQuery.of(context).size;
    final isHorizontal = size.width > size.height;

    // 2. Assign the correct URL based on the detected hardware
    final String baseUrl = isHorizontal
        ? "https://boitexinfo.com/432-horizental-lcd-digital-interactive-kiosk"
        : "https://boitexinfo.com/431-floor-standing-LCD-screen-Digital-Advertising";

    // 3. Append the Analytics tracking tag
    final String finalUrl = "$baseUrl?source=kiosk_$_screenId";

    // ==========================================
    // 4. ANIMATION STATE DIMENSIONS
    // ==========================================
    // If interactive, shrink out of the way. If idle, expand to show QR.
    final double overlayWidth = widget.isInteractive ? 120.0 : 340.0;
    final double overlayHeight = widget.isInteractive ? 40.0 : 160.0;

    return Positioned(
      bottom: 24, // Place it in the bottom right corner
      right: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          // Applies the Premium "Frosted Glass" blur effect to whatever is behind it
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutBack,
            width: overlayWidth,
            height: overlayHeight,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.2)), // Sleek edge
            ),
            padding: const EdgeInsets.all(16),
            // Switch between the small text and the full QR code
            child: widget.isInteractive
                ? _buildMinimizedState()
                : _buildExpandedState(finalUrl),
          ),
        ),
      ),
    );
  }

  /// State A: Small text when user is touching the screen
  Widget _buildMinimizedState() {
    return const Center(
      child: Text(
        "BoitexInfo",
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// State B: Full QR Code and marketing text when screen is idle
  Widget _buildExpandedState(String targetUrl) {
    // Use an AnimatedOpacity to prevent overflow errors while the container resizes
    return AnimatedOpacity(
      opacity: widget.isInteractive ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 400),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The Dynamic QR Code
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(6),
            child: QrImageView(
              data: targetUrl, // 👈 The smart URL with the tracking tag
              version: QrVersions.auto,
              size: 110.0,
              gapless: false,
            ),
          ),
          const SizedBox(width: 16),
          // The Marketing Text
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Engineered by",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  "BoitexInfo",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Scan to get this hardware for your business.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}