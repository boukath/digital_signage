import 'dart:ui'; // 👇 Needed for PointerDeviceKind
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:window_manager/window_manager.dart'; // 👇 The new Window Manager

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
  // 🛡️ TRUE KIOSK MODE (WINDOWS ONLY)
  // ==========================================
  if (!kIsWeb) {
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
// 👇 NEW: Custom Scroll Behavior for Desktop
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
      // 👇 NEW: Apply the custom scroll behavior here globally
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