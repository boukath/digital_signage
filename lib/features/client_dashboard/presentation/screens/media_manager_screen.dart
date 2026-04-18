// File: lib/features/client_dashboard/presentation/screens/media_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/domain/app_user.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../data/b2_storage_service.dart';

class MediaManagerScreen extends StatefulWidget {
  const MediaManagerScreen({Key? key}) : super(key: key);

  @override
  State<MediaManagerScreen> createState() => _MediaManagerScreenState();
}

class _MediaManagerScreenState extends State<MediaManagerScreen> {
  final B2StorageService _b2Service = B2StorageService();
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isUploading = false;
  String? _currentClientId;

  @override
  void initState() {
    super.initState();
    _fetchClientId();
  }

  Future<void> _fetchClientId() async {
    final appUser = await _authService.userStateStream.first;
    if (mounted) {
      setState(() {
        _currentClientId = appUser?.uid;
      });
    }
  }

  /// Documentation:
  /// Opens the file explorer allowing Images, Videos, AND 3D Spatial Models (.glb)
  Future<void> _pickAndUploadFile() async {
    if (_currentClientId == null) return;

    // NEW: We changed this to custom to explicitly allow .glb files!
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'glb', 'gltf'],
      withData: true,
    );

    if (result != null && result.files.first.bytes != null) {
      setState(() => _isUploading = true);

      final fileName = result.files.first.name;
      final fileBytes = result.files.first.bytes!;

      // 1. Upload to B2
      final String? downloadUrl = await _b2Service.uploadMedia(fileName, fileBytes, _currentClientId!);

      // 2. Save metadata to Firestore
      if (downloadUrl != null) {
        // Determine the file type dynamically
        String fileType = 'image';
        if (fileName.toLowerCase().endsWith('.mp4')) fileType = 'video';
        if (fileName.toLowerCase().endsWith('.glb') || fileName.toLowerCase().endsWith('.gltf')) fileType = '3d';

        await _firestore.collection('clients').doc(_currentClientId).collection('media').add({
          'url': downloadUrl,
          'name': fileName,
          'type': fileType, // Now supports 'image', 'video', or '3d'
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() => _isUploading = false);
    }
  }

  // 🗑️ NEW: Confirmation Dialog before permanent deletion
  Future<void> _confirmDelete(String docId, String fileName) async {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.glassBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.glassBorder)),
          title: Text("Delete Media?", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text("Are you sure you want to permanently delete '$fileName'? It will be removed from the cloud.", style: GoogleFonts.poppins(color: Colors.white70)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                Navigator.pop(ctx);
                await _executeDelete(docId, fileName);
              },
              child: Text("Delete", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
    );
  }

  // 🗑️ NEW: The actual deletion logic (Database + Cloud Storage)
  Future<void> _executeDelete(String docId, String fileName) async {
    if (_currentClientId == null) return;

    try {
      // 1. Delete from Firestore Database
      await _firestore.collection('clients').doc(_currentClientId).collection('media').doc(docId).delete();

      // 2. Delete the actual heavy file from Backblaze B2
      await _b2Service.deleteMedia(fileName, _currentClientId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File permanently deleted."), backgroundColor: Colors.orange)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error deleting file: $e"), backgroundColor: Colors.redAccent)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Media Library",
                style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              ElevatedButton.icon(
                onPressed: (_isUploading || _currentClientId == null) ? null : _pickAndUploadFile,
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.backgroundGradientStart, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_rounded, color: AppColors.backgroundGradientStart),
                label: Text(
                  _isUploading ? "Uploading..." : "Upload Media (inc. 3D)",
                  style: GoogleFonts.poppins(color: AppColors.backgroundGradientStart, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Real-time Grid of Media using StreamBuilder
          Expanded(
            child: _currentClientId == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).collection('media').orderBy('uploadedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                if (snapshot.hasError) return Center(child: Text("Error loading media.", style: GoogleFonts.poppins(color: Colors.redAccent)));

                final mediaDocs = snapshot.data?.docs ?? [];
                if (mediaDocs.isEmpty) {
                  return Center(child: Text("Your library is empty. Upload media to start!", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 18)));
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16
                  ),
                  itemCount: mediaDocs.length,
                  itemBuilder: (context, index) {
                    final docId = mediaDocs[index].id; // 👈 NEW: Need document ID for deletion
                    final data = mediaDocs[index].data() as Map<String, dynamic>;

                    final mediaUrl = data['url'] ?? '';
                    final fileName = data['name'] ?? 'Unknown File'; // 👈 NEW: Need filename for B2 deletion
                    final isVideo = data['type'] == 'video';
                    final is3D = data['type'] == '3d';

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // The Media Card
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.glassBackground,
                            border: Border.all(color: AppColors.glassBorder),
                            borderRadius: BorderRadius.circular(16),
                            // Only show image preview if it is an actual image
                            image: (!isVideo && !is3D && mediaUrl.isNotEmpty)
                                ? DecorationImage(
                                image: NetworkImage(mediaUrl),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)
                            )
                                : null,
                          ),
                          child: Center(
                            child: Icon(
                              isVideo ? Icons.play_circle_fill : (is3D ? Icons.view_in_ar_rounded : Icons.image),
                              color: Colors.white70,
                              size: 48,
                            ),
                          ),
                        ),

                        // 🗑️ NEW: The Red Delete Button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _confirmDelete(docId, fileName),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)]
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                            ),
                          ),
                        )
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}