// File: lib/features/super_admin/presentation/widgets/deploy_update_modal.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/super_admin_service.dart';

// ☁️ Import your exact B2 Storage Service
import '../../../client_dashboard/data/b2_storage_service.dart';

class DeployUpdateModal extends StatefulWidget {
  const DeployUpdateModal({super.key});

  @override
  State<DeployUpdateModal> createState() => _DeployUpdateModalState();
}

class _DeployUpdateModalState extends State<DeployUpdateModal> {
  final SuperAdminService _adminService = SuperAdminService();
  final B2StorageService _b2StorageService = B2StorageService();

  bool _isUploading = false;
  String _statusMessage = "";

  Future<void> _handleDeploy() async {
    try {
      // 1. Pick the .zip file
      // ➔ CHANGED: Removed '.platform' to fix the version 11.0.2 breaking change
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true, // Forces file_picker to load the bytes into RAM for B2
      );

      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;

      setState(() {
        _isUploading = true;
        _statusMessage = "Uploading ${file.name} to B2 Storage...";
      });

      // 2. UPLOAD TO BACKBLAZE B2
      // Using your exact method from b2_storage_service.dart
      final String? uploadedZipUrl = await _b2StorageService.uploadMedia(
        file.name,
        file.bytes!,
        'global_updates', // Creates a clean folder in B2 for updates
      );

      // Safety check in case the Backblaze upload fails
      if (uploadedZipUrl == null) {
        setState(() {
          _statusMessage = "❌ Error: Failed to upload to Backblaze.";
          _isUploading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = "Broadcasting update command to all screens...";
      });

      // 3. SEND THE COMMAND TO FIRESTORE
      await _adminService.deployGlobalUpdate(uploadedZipUrl);

      setState(() {
        _statusMessage = "✅ Update Deployed Successfully!";
        _isUploading = false;
      });

      // Close the modal cleanly after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });

    } catch (e) {
      setState(() {
        _statusMessage = "❌ Error: $e";
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.glassBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
      title: Text(
        "Deploy Global Update",
        style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Upload a new .zip release to Backblaze B2. This will force all active screens across all clients to silently download, install, and reboot.",
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            if (_isUploading) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
            ],
            Text(
              _statusMessage,
              style: GoogleFonts.poppins(
                color: _statusMessage.contains("❌") ? Colors.redAccent : Colors.amber,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          onPressed: _isUploading ? null : _handleDeploy,
          icon: const Icon(Icons.rocket_launch, color: Colors.black),
          label: Text(
            "Upload & Deploy",
            style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}