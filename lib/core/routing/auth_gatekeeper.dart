// File: lib/core/routing/auth_gatekeeper.dart

import 'package:flutter/material.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/super_admin/presentation/screens/super_admin_dashboard.dart';
import '../../features/client_dashboard/presentation/screens/client_dashboard.dart';

/// Documentation:
/// This widget acts as the smart traffic controller for the entire app.
/// It listens to Firebase, checks the user's role, verifies their license,
/// and routes them to the correct screen.
class AuthGatekeeper extends StatelessWidget {
  const AuthGatekeeper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder(
      stream: authService.userStateStream,
      builder: (context, snapshot) {
        // 1. While waiting for Firebase & Firestore to respond, show a loading spinner
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF4A00E0), // Matching your premium theme
            body: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }

        final user = snapshot.data;

        // 2. If the user is null, they are NOT logged in. Send to Login.
        if (user == null) {
          return const LoginScreen();
        }

        // 3. SECURITY CHECK: Is the client paused or expired?
        // We skip this check for 'super_admin' so you never accidentally lock yourself out!
        if (user.role != 'super_admin') {
          if (user.isPaused || user.isLicenseExpired) {
            // If they are blocked, we trigger a sign-out immediately.
            // addPostFrameCallback ensures this happens safely after the widget builds.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              authService.signOut();
            });

            // Show a temporary blocked message before they are redirected to Login
            return Scaffold(
              backgroundColor: const Color(0xFF1E1E2C),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    user.isPaused
                        ? 'Your account has been paused by the Administrator.'
                        : 'Your license has expired. Please contact support.',
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
        }

        // 4. ROLE-BASED ROUTING: Send them to the correct dashboard!
        if (user.role == 'super_admin') {
          return const SuperAdminDashboard();
        } else if (user.role == 'client') {
          // WE REPLACED THE PLACEHOLDER WITH OUR NEW UI!
          return const ClientDashboard();
        }

        // 5. Fallback screen just in case a role is missing or typed incorrectly in the database
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Error: Unknown User Role'),
                ElevatedButton(
                  onPressed: () => authService.signOut(),
                  child: const Text('Log Out'),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}