// File: lib/features/kiosk_player/presentation/screens/kiosk_main_screen.dart

import 'dart:async';
import 'dart:io'; // Required for Process, exit, and File
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Needed for kIsWeb
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For listening to commands
import 'package:shared_preferences/shared_preferences.dart'; // To get the hardware Screen ID

// 📥 NEW: Required for downloading the update
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// Import your views and components
import 'screensaver_view.dart';
import 'interactive_catalog_view.dart';
import '../../data/kiosk_pairing_service.dart';
import 'kiosk_boot_screen.dart';
import '../widgets/smart_branding_overlay.dart';

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

  // 🌟 Subscription for Remote Commands
  StreamSubscription? _remoteCommandSubscription;

  @override
  void initState() {
    super.initState();
    // App starts in Passive Screensaver Mode
    // Start listening for dashboard commands immediately!
    _listenForRemoteCommands();
  }

  // ==========================================
  // 🌟 REMOTE COMMAND LISTENER
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
          } else if (command == 'update') {
            // 📥 NEW: Handle the update command
            final updateUrl = data['updateUrl'];
            if (updateUrl != null) {
              // Start the background download!
              _downloadUpdateAndPrepare(updateUrl);
            } else {
              debugPrint("⚠️ [UPDATE] Received update command, but no URL was provided!");
            }
          }
          // You can add logic for 'force_sync' and 'clear_cache' here in the future
        }
      });
    } catch (e) {
      debugPrint("❌ [COMMAND] Failed to set up command listener: $e");
    }
  }

  // ==========================================
  // 📥 SILENT UPDATE DOWNLOADER & SIDECAR TRIGGER
  // ==========================================
  Future<void> _downloadUpdateAndPrepare(String downloadUrl) async {
    debugPrint("📥 [UPDATE] Starting silent download from: $downloadUrl");

    try {
      // 1. Get the hidden Windows Temp folder
      final tempDir = await getTemporaryDirectory();

      // 2. Define where we will save the zip file
      final zipPath = '${tempDir.path}\\signage_update.zip';
      final file = File(zipPath);

      // 3. Download the file using http
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint("✅ [UPDATE] Successfully downloaded update to: $zipPath");

        // 🚀 NEW: Trigger Step 2 (The Sidecar Script)
        _triggerSidecarUpdater(zipPath, tempDir.path);

      } else {
        debugPrint("❌ [UPDATE] Failed to download. Server returned: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ [UPDATE] Download error: $e");
    }
  }

  // ==========================================
  // 🪄 THE SIDECAR UPDATER MAGIC
  // ==========================================
  void _triggerSidecarUpdater(String zipPath, String tempDirPath) async {
    debugPrint("🪄 [UPDATE] Generating Sidecar Updater Script...");

    // 1. Find exactly where this current app is running from
    final appExecutablePath = Platform.resolvedExecutable;
    final appInstallDirectory = File(appExecutablePath).parent.path;

    // 2. Define where we will write our temporary Batch script
    final scriptPath = '$tempDirPath\\updater.bat';

    // 3. Write the Windows Batch script commands
    // - Wait 3 seconds
    // - Unzip and overwrite files
    // - Delete the zip file
    // - Relaunch the app
    // - Delete this batch script
    final batContent = '''
@echo off
echo Installing Update for Digital Signage...
timeout /t 3 /nobreak > NUL
powershell -Command "Expand-Archive -Path '$zipPath' -DestinationPath '$appInstallDirectory' -Force"
del "$zipPath"
start "" "$appExecutablePath"
del "%~f0"
''';

    // 4. Save the script to the disk
    final scriptFile = File(scriptPath);
    await scriptFile.writeAsString(batContent);

    debugPrint("🚀 [UPDATE] Launching Updater and closing app...");

    // 5. Execute the batch script detached from the app (so it survives when the app dies)
    await Process.start(scriptPath, [], mode: ProcessStartMode.detached);

    // 6. INSTANTLY KILL THE FLUTTER APP
    // This unlocks the files so the batch script can safely overwrite them!
    exit(0);
  }

  // ==========================================
  // 🔄 NATIVE WINDOWS REBOOT
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

            // 🚀 NEW: THE BOITEXINFO SMART BRANDING OVERLAY
            // Placed at the very end of the stack so it always stays on top!
            SmartBrandingOverlay(
              isInteractive: _isInteractiveMode,
            ),
          ],
        ),
      ),
    );
  }
}