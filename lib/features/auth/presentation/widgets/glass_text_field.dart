// File: lib/features/auth/presentation/widgets/glass_text_field.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

/// Documentation:
/// A custom, reusable text field with a semi-transparent background,
/// white text, and rounded corners to fit the modern iOS aesthetic.
class GlassTextField extends StatelessWidget {
  final String hintText;
  final IconData icon;
  final bool isPassword;
  final TextEditingController controller;

  const GlassTextField({
    Key? key,
    required this.hintText,
    required this.icon,
    required this.controller,
    this.isPassword = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15), // Very subtle inner white fill
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: GoogleFonts.poppins(color: AppColors.textPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          prefixIcon: Icon(icon, color: Colors.white70),
          hintText: hintText,
          hintStyle: GoogleFonts.poppins(color: Colors.white60),
        ),
      ),
    );
  }
}