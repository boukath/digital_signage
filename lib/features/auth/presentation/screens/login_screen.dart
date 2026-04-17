// File: lib/features/auth/presentation/screens/login_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/glass_text_field.dart';
import '../widgets/glass_button.dart';
import '../../data/auth_service.dart';

/// Documentation:
/// The main login screen featuring a vibrant gradient background and a
/// centered Glassmorphism card. Fully adaptable for Web, Windows, and Mobile.
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // We add the AuthService and a loading state variable
  final _authService = AuthService(); // IMPORTANT: Make sure to import this at the top of the file!
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    // 1. Basic validation
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in both email and password.")),
      );
      return;
    }

    // 2. Start loading animation
    setState(() {
      _isLoading = true;
    });

    try {
      // 3. Attempt to log in to Firebase
      await _authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // Note: We don't need to manually navigate away!
      // The AuthGatekeeper is listening and will automatically change the screen!

    } catch (e) {
      // 4. If it fails (wrong password, etc.), show a clean error message
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Login Failed. Please check your credentials."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.backgroundGradientStart, AppColors.backgroundGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: AppColors.glassBackground,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: AppColors.glassBorder, width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.display_settings_rounded, size: 80, color: Colors.white),
                        const SizedBox(height: 24),
                        Text(
                          "Welcome Back",
                          style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Log in to manage your digital signage.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
                        ),
                        const SizedBox(height: 40),
                        GlassTextField(hintText: "Email Address", icon: Icons.email_outlined, controller: _emailController),
                        const SizedBox(height: 20),
                        GlassTextField(hintText: "Password", icon: Icons.lock_outline, isPassword: true, controller: _passwordController),
                        const SizedBox(height: 40),

                        // 5. Update the button to show a spinner if loading
                        _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : GlassButton(text: "SIGN IN", onPressed: _handleLogin),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}