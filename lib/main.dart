import 'dart:ui'; // 👇 Needed for PointerDeviceKind
import 'dart:io'; // 👈 NEW: Required to check the platform and get the executable path

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:window_manager/window_manager.dart'; // 👇 The new Window Manager

// 👈 NEW: Import the startup and package info plugins
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_options.dart';

// Web Entry Point
import 'core/routing/auth_gatekeeper.dart';

// Windows Entry Point
import 'features/kiosk_player/presentation/screens/kiosk_boot_screen.dart';

void main() async {
  // Ensure Flutter is ready
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ==========================================
  // 🚀 NEW: AUTO-START ON WINDOWS BOOT
  // ==========================================
  // Note: We check !kIsWeb first because Platform.isWindows crashes on the Web
  if (!kIsWeb && Platform.isWindows) {
    try {
      // 1. Get the app's metadata (name, version, etc.)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      // 2. Configure the startup package with your exact .exe path
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );

      // 3. Force the app to enable auto-start in the Windows Registry
      await launchAtStartup.enable();

      print("✅ Windows Auto-Start Configured!");
    } catch (e) {
      print("⚠️ Warning: Failed to configure Windows Auto-Start: $e");
    }
  }

  // ==========================================
  // 🛡️ TRUE KIOSK MODE (WINDOWS ONLY)
  // ==========================================
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      fullScreen: true,     // Takes over the entire screen, hiding the taskbar
      alwaysOnTop: true,    // Prevents other Windows notifications from popping over your app
      skipTaskbar: true,    // Hides the app icon from the Windows taskbar
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setFullScreen(true);
    });
  }

  runApp(const MyApp());
}

// ==========================================
// 👇 Custom Scroll Behavior for Desktop
// ==========================================
class KioskScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,    // Default touch screens
    PointerDeviceKind.mouse,    // 👈 Forces mouse clicks to act like swiping
    PointerDeviceKind.stylus,   // Stylus pens
    PointerDeviceKind.trackpad, // Laptop trackpads
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Signage Enterprise',
      debugShowCheckedModeBanner: false,
      // 👇 Apply the custom scroll behavior here globally
      scrollBehavior: KioskScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A00E0)),
        useMaterial3: true,
      ),
      // The Platform Router
      home: kIsWeb ? const AuthGatekeeper() : const KioskBootScreen(),
    );
  }
}