// File: lib/features/super_admin/presentation/widgets/add_client_modal.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/widgets/glass_text_field.dart';
import '../../../auth/presentation/widgets/glass_button.dart';
import '../../data/super_admin_service.dart';

class AddClientModal extends StatefulWidget {
  const AddClientModal({Key? key}) : super(key: key);

  @override
  State<AddClientModal> createState() => _AddClientModalState();
}

class _AddClientModalState extends State<AddClientModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController(); // NEW
  final TextEditingController _phoneController = TextEditingController();    // NEW
  final TextEditingController _addressController = TextEditingController();  // NEW

  final SuperAdminService _adminService = SuperAdminService();
  bool _isLoading = false;

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    // Basic validation to ensure the critical fields are filled
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Name, Email, and Password are required.")),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password must be at least 6 characters.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Send all the data to our updated service
      await _adminService.createClient(
        companyName: name,
        contactEmail: email,
        password: password,
        phoneNumber: phone.isEmpty ? "N/A" : phone,
        address: address.isEmpty ? "N/A" : address,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Client account fully created!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add client: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500), // Made slightly wider for the new fields
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.glassBackground,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.glassBorder, width: 1.5),
              ),
              child: SingleChildScrollView( // Added scrolling in case screen is small
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("New Client Profile", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text("Register a business and generate their login.", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 30),

                    // The Full Form
                    GlassTextField(hintText: "Business Name", icon: Icons.storefront_rounded, controller: _nameController),
                    const SizedBox(height: 16),
                    GlassTextField(hintText: "Contact Email", icon: Icons.email_outlined, controller: _emailController),
                    const SizedBox(height: 16),
                    GlassTextField(hintText: "Temporary Password", icon: Icons.lock_outline, isPassword: true, controller: _passwordController),
                    const SizedBox(height: 16),
                    GlassTextField(hintText: "Phone Number (Optional)", icon: Icons.phone_outlined, controller: _phoneController),
                    const SizedBox(height: 16),
                    GlassTextField(hintText: "Store Address (Optional)", icon: Icons.location_on_outlined, controller: _addressController),
                    const SizedBox(height: 32),

                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : GlassButton(text: "CREATE SECURE ACCOUNT", onPressed: _handleSubmit),

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white70)),
                    )
                  ],
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
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}