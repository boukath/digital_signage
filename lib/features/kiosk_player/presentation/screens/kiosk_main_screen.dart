// File: lib/features/kiosk_player/presentation/screens/kiosk_main_screen.dart

import 'dart:async';
import 'dart:io'; // Required for Process, exit, and File
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Needed for kIsWeb
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // For listening to commands
import 'package:shared_preferences/shared_preferences.dart'; // To get the hardware Screen ID

// 📥 Required for downloading the update
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// Import your views and components
import 'screensaver_view.dart';
import 'interactive_catalog_view.dart';
import '../../data/kiosk_pairing_service.dart';
import 'kiosk_boot_screen.dart';
import '../widgets/smart_branding_overlay.dart';

// 👇 NEW: Import the Pro Layout Data Models, Service, and the new MediaZonePlayer!
import '../../../client_dashboard/domain/layout_model.dart';
import '../../data/kiosk_layout_service.dart';
import '../widgets/media_zone_player.dart'; // <--- We import the player here

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

  // 👇 The Service to fetch the Pro Layouts
  final KioskLayoutService _layoutService = KioskLayoutService();

  @override
  void initState() {
    super.initState();
    // App starts in Passive Screensaver Mode
    // Start listening for dashboard commands immediately!
    _listenForRemoteCommands();
  }

  // --- HELPER FUNCTION FOR PRO LAYOUT COLORS ---
  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  // ==========================================
  // 🌟 REMOTE COMMAND LISTENER
  // ==========================================
  Future<void> _listenForRemoteCommands() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final screenId = prefs.getString('screen_id');

      if (screenId == null) {
        debugPrint("⚠️ [COMMAND] No Screen ID found. Cannot listen for commands.");
        return;
      }

      debugPrint("📡 [COMMAND] Listening for remote commands on Screen ID: $screenId");

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

          // ACKNOWLEDGE: Clear the command immediately
          await snapshot.reference.update({'pendingCommand': null});

          // EXECUTE THE COMMAND
          if (command == 'reboot') {
            _executeSystemReboot();
          } else if (command == 'update') {
            final updateUrl = data['updateUrl'];
            if (updateUrl != null) {
              _downloadUpdateAndPrepare(updateUrl);
            } else {
              debugPrint("⚠️ [UPDATE] Received update command, but no URL was provided!");
            }
          }
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
      final tempDir = await getTemporaryDirectory();
      final zipPath = '${tempDir.path}\\signage_update.zip';
      final file = File(zipPath);

      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint("✅ [UPDATE] Successfully downloaded update to: $zipPath");
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
    final appExecutablePath = Platform.resolvedExecutable;
    final appInstallDirectory = File(appExecutablePath).parent.path;
    final scriptPath = '$tempDirPath\\updater.bat';

    final batContent = '''
@echo off
echo Installing Update for Digital Signage...
timeout /t 3 /nobreak > NUL
powershell -Command "Expand-Archive -Path '$zipPath' -DestinationPath '$appInstallDirectory' -Force"
del "$zipPath"
start "" "$appExecutablePath"
del "%~f0"
''';

    final scriptFile = File(scriptPath);
    await scriptFile.writeAsString(batContent);

    debugPrint("🚀 [UPDATE] Launching Updater and closing app...");
    await Process.start(scriptPath, [], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ==========================================
  // 🔄 NATIVE WINDOWS REBOOT
  // ==========================================
  void _executeSystemReboot() {
    debugPrint("🔄 [SYSTEM] Initiating Hardware Reboot...");
    if (!kIsWeb && Platform.isWindows) {
      Process.run('shutdown', ['/r', '/f', '/t', '0']).then((result) {
        debugPrint("💻 Windows shutdown command sent.");
      }).catchError((e) {
        debugPrint("❌ Failed to reboot Windows: $e");
      });
    } else {
      exit(0);
    }
  }

  // Called whenever the user touches the screen
  void _handleUserInteraction() {
    if (!_isInteractiveMode) {
      setState(() => _isInteractiveMode = true);
      debugPrint("👆 Screen Touched! Switching to Interactive State B");
    }
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
      _secretTapCount = 0;
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
      _secretCloseTapCount = 0;
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
                exit(0);
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

            // ==========================================
            // 🎨 STATE A: PRO MULTI-ZONE LAYOUT (Screensaver)
            // ==========================================
            Positioned.fill(
              child: StreamBuilder<LayoutModel?>(
                // Note: Hardcoded 'layout_001' for testing. Later, you can tie this to a specific screenId!
                stream: _layoutService.listenToLayout('layout_001'),
                builder: (context, snapshot) {

                  // If the layout is missing, gracefully fall back to the original full-screen video loop!
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                    return ScreensaverView(
                        clientId: widget.clientId,
                        isPaused: _isInteractiveMode
                    );
                  }

                  final layout = snapshot.data!;

                  // 🧩 Render the Multi-Zone Parser!
                  return Center(
                    child: AspectRatio(
                      aspectRatio: layout.isLandscape ? 16 / 9 : 9 / 16,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          children: layout.zones.map((zone) {
                            return Positioned(
                              left: zone.x,
                              top: zone.y,
                              width: zone.width,
                              height: zone.height,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _hexToColor(zone.colorHex),
                                ),
                                child: ClipRRect(
                                  // 👇 THIS IS THE NEW INTEGRATION!
                                  child: Builder(
                                    builder: (context) {
                                      // 1. IS IT A PLAYLIST?
                                      if (zone.zoneType == 'playlist') {
                                        return MediaZonePlayer(
                                          clientId: widget.clientId,
                                          zoneId: zone.id,
                                          // Note: We will update MediaZonePlayer to accept assignedPlaylistId next!
                                        );
                                      }

                                      // 2. IS IT A STATIC LOGO?
                                      else if (zone.zoneType == 'static_logo') {
                                        if (zone.contentId == null || zone.contentId!.isEmpty) {
                                          return const Center(child: Icon(Icons.broken_image, color: Colors.white54));
                                        }
                                        return Image.network(
                                          zone.contentId!,
                                          fit: BoxFit.contain, // Contain ensures the logo doesn't get cut off!
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
                                          ),
                                        );
                                      }

                                      // 3. FALLBACK
                                      return const Center(child: Text('Empty Zone', style: TextStyle(color: Colors.white)));
                                    },
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ==========================================
            // 👆 STATE B: THE INTERACTIVE CATALOG
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

            // 🛡️ SECRET BUTTON: TOP-RIGHT (UNPAIR)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleSecretAdminTap,
                child: Container(width: 80, height: 80, color: Colors.transparent),
              ),
            ),

            // 🌟 SECRET BUTTON: TOP-LEFT (CLOSE APP)
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleSecretCloseTap,
                child: Container(width: 80, height: 80, color: Colors.transparent),
              ),
            ),

            // 🚀 THE BOITEXINFO SMART BRANDING OVERLAY
            SmartBrandingOverlay(
              isInteractive: _isInteractiveMode,
            ),
          ],
        ),
      ),
    );
  }
}