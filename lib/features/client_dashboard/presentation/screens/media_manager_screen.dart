// File: lib/features/client_dashboard/presentation/screens/media_manager_screen.dart

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../../core/constants/app_colors.dart';
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

  String _currentPath = ""; // "" means Root Directory

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

  // =========================================================================
  // 🌟 MAGIC RETROACTIVE AUTO-ORGANIZER 🌟
  // =========================================================================
  Future<void> _autoOrganizeExistingMedia() async {
    if (_currentClientId == null) return;

    // Show loading spinner
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.backgroundGradientStart)));

    try {
      final docRef = _firestore.collection('clients').doc(_currentClientId);
      final clientSnap = await docRef.get();
      final data = clientSnap.data() ?? {};
      final List<dynamic> catalog = data['catalog'] ?? [];

      Set<String> newFoldersToCreate = {};
      Map<String, String> urlToFolderMap = {};

      // 1. Map out where every file *should* go based on the products in the catalog
      for (var item in catalog) {
        String dept = (item['department'] ?? 'General').toString().trim();
        if (dept.isEmpty) dept = 'General';
        String title = (item['title'] ?? 'Unnamed Product').toString().trim();
        if (title.isEmpty) title = 'Unnamed Product';

        String folderPath = "$dept/$title"; // e.g. "MEN/Jacket"

        newFoldersToCreate.add(dept);
        newFoldersToCreate.add(folderPath);

        // Map primary media
        if (item['mediaUrl'] != null && item['mediaUrl'].toString().isNotEmpty) {
          urlToFolderMap[item['mediaUrl']] = folderPath;
        }

        // Map gallery media
        if (item['gallery'] != null) {
          for (var g in item['gallery']) {
            if (g['url'] != null && g['url'].toString().isNotEmpty) {
              urlToFolderMap[g['url']] = folderPath;
            }
          }
        }
      }

      // 2. Save the new folders to the database so they appear in the UI
      if (newFoldersToCreate.isNotEmpty) {
        await docRef.set({
          'mediaFolders': FieldValue.arrayUnion(newFoldersToCreate.toList())
        }, SetOptions(merge: true));
      }

      // 3. Find those images in the media library and move them to their new folders
      final mediaRef = docRef.collection('media');
      final mediaSnap = await mediaRef.get();

      int updateCount = 0;
      for (var doc in mediaSnap.docs) {
        final mediaData = doc.data();
        final url = mediaData['url'];

        if (url != null && urlToFolderMap.containsKey(url)) {
          String correctFolder = urlToFolderMap[url]!;

          // Only update if it's not already in the correct folder
          if (mediaData['folderPath'] != correctFolder) {
            await doc.reference.update({'folderPath': correctFolder});
            updateCount++;
          }
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Success! Cleaned up and moved $updateCount files into folders."), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error Auto-Organizing: $e"), backgroundColor: Colors.redAccent));
      }
    }
  }

  // =========================================================================
  // 📁 FOLDER MANAGEMENT LOGIC
  // =========================================================================

  Future<void> _createNewFolder() async {
    final TextEditingController nameController = TextEditingController();

    await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.glassBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.glassBorder)),
          title: Text("Create New Folder", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "e.g. Summer Collection",
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart),
              onPressed: () async {
                String folderName = nameController.text.trim();
                if (folderName.isEmpty || folderName.contains('/')) return; // No slashes allowed in names

                String newFullPath = _currentPath.isEmpty ? folderName : "$_currentPath/$folderName";
                final docRef = _firestore.collection('clients').doc(_currentClientId);
                await docRef.set({
                  'mediaFolders': FieldValue.arrayUnion([newFullPath])
                }, SetOptions(merge: true));

                if (mounted) Navigator.pop(ctx);
              },
              child: Text("Create", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
    );
  }

  Future<void> _deleteFolder(String folderPath) async {
    final docRef = _firestore.collection('clients').doc(_currentClientId);
    await docRef.update({
      'mediaFolders': FieldValue.arrayRemove([folderPath])
    });
  }

  List<String> _getImmediateChildFolders(List<dynamic> allFolders) {
    List<String> result = [];
    for (String f in allFolders.map((e) => e.toString())) {
      if (_currentPath.isEmpty) {
        if (!f.contains('/')) result.add(f);
      } else {
        if (f.startsWith('$_currentPath/') && !f.substring(_currentPath.length + 1).contains('/')) {
          result.add(f);
        }
      }
    }
    return result;
  }

  // =========================================================================
  // 🚀 MEDIA UPLOAD & DELETE LOGIC
  // =========================================================================

  Future<void> _pickAndUploadFile() async {
    if (_currentClientId == null) return;

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'glb', 'gltf'],
      withReadStream: true,
    );

    if (result != null && result.files.first.readStream != null) {
      setState(() => _isUploading = true);

      final file = result.files.first;
      final fileName = file.name;

      String fileType = 'image';
      if (fileName.toLowerCase().endsWith('.mp4')) fileType = 'video';
      if (fileName.toLowerCase().endsWith('.glb') || fileName.toLowerCase().endsWith('.gltf')) fileType = '3d';

      String? downloadUrl;
      String autoThumbnailUrl = '';

      if (fileType == 'video') {
        Uint8List? thumbBytes;
        if (!kIsWeb && file.path != null) {
          try {
            thumbBytes = await VideoThumbnail.thumbnailData(video: file.path!, imageFormat: ImageFormat.JPEG, maxWidth: 600, quality: 75);
          } catch (e) {
            print("⚠️ Local extraction failed: $e");
          }
        }

        final videoStream = file.readStream!.map((chunk) => Uint8List.fromList(chunk));
        Future<String?> videoUploadTask = _b2Service.uploadMediaStream(fileName, videoStream, file.size, _currentClientId!);
        Future<String?> thumbUploadTask = Future.value(null);
        if (thumbBytes != null) {
          String thumbName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
          thumbUploadTask = _b2Service.uploadMedia(thumbName, thumbBytes, _currentClientId!);
        }

        final uploadResults = await Future.wait([videoUploadTask, thumbUploadTask]);
        downloadUrl = uploadResults[0];
        if (uploadResults[1] != null) autoThumbnailUrl = uploadResults[1]!;
      } else {
        final fileStream = file.readStream!.map((chunk) => Uint8List.fromList(chunk));
        downloadUrl = await _b2Service.uploadMediaStream(fileName, fileStream, file.size, _currentClientId!);
      }

      if (downloadUrl != null) {
        await _firestore.collection('clients').doc(_currentClientId).collection('media').add({
          'url': downloadUrl,
          'name': fileName,
          'type': fileType,
          'thumbnailUrl': autoThumbnailUrl,
          'folderPath': _currentPath,
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() => _isUploading = false);
    }
  }

  Future<void> _confirmDeleteFile(String docId, String fileName, String? thumbnailUrl) async {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.glassBackground,
          title: Text("Delete Media?", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text("Are you sure you want to permanently delete '$fileName'?", style: GoogleFonts.poppins(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                Navigator.pop(ctx);
                await _executeDeleteFile(docId, fileName, thumbnailUrl);
              },
              child: Text("Delete", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
    );
  }

  Future<void> _executeDeleteFile(String docId, String fileName, String? thumbnailUrl) async {
    if (_currentClientId == null) return;
    try {
      await _firestore.collection('clients').doc(_currentClientId).collection('media').doc(docId).delete();
      await _b2Service.deleteMedia(fileName, _currentClientId!);
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        final uri = Uri.parse(thumbnailUrl);
        await _b2Service.deleteMedia(uri.pathSegments.last, _currentClientId!);
      }
    } catch (e) {
      print("Error deleting: $e");
    }
  }

  // =========================================================================
  // 🎨 UI BUILDING
  // =========================================================================

  Widget _buildBreadcrumbs() {
    List<String> parts = _currentPath.isEmpty ? [] : _currentPath.split('/');

    List<Widget> breadcrumbWidgets = [
      InkWell(
        onTap: () => setState(() => _currentPath = ""),
        child: Row(children: [Icon(Icons.home, color: Colors.white70, size: 20), SizedBox(width: 8), Text("Home", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]),
      ),
    ];

    String accumulated = "";
    for (String part in parts) {
      accumulated = accumulated.isEmpty ? part : "$accumulated/$part";
      String pathCapture = accumulated;

      breadcrumbWidgets.add(Text("  /  ", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 18)));
      breadcrumbWidgets.add(
          InkWell(
            onTap: () => setState(() => _currentPath = pathCapture),
            child: Text(part, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          )
      );
    }

    return Row(children: breadcrumbWidgets);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator(color: Colors.white));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER: Title & Buttons ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Media Library", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Row(
                children: [
                  // 👇 THE NEW AUTO ORGANIZE BUTTON
                  OutlinedButton.icon(
                    onPressed: _autoOrganizeExistingMedia,
                    icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
                    label: Text("Auto-Organize Catalog Media", style: GoogleFonts.poppins(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amberAccent), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _createNewFolder,
                    icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
                    label: Text("New Folder", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickAndUploadFile,
                    icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.backgroundGradientStart, strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded, color: AppColors.backgroundGradientStart),
                    label: Text(_isUploading ? "Uploading..." : "Upload File Here", style: GoogleFonts.poppins(color: AppColors.backgroundGradientStart, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- BREADCRUMBS ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: _buildBreadcrumbs(),
          ),
          const SizedBox(height: 24),

          // --- HYBRID GRID VIEWER ---
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).snapshots(),
              builder: (context, clientSnap) {
                if (!clientSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));

                List<dynamic> allFolders = clientSnap.data!.data() != null ? (clientSnap.data!.data() as Map<String, dynamic>)['mediaFolders'] ?? [] : [];
                List<String> currentDirFolders = _getImmediateChildFolders(allFolders);

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('clients').doc(_currentClientId).collection('media').orderBy('uploadedAt', descending: true).snapshots(),
                  builder: (context, mediaSnap) {
                    if (!mediaSnap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));

                    final mediaDocs = mediaSnap.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final docPath = data['folderPath'] ?? "";
                      return docPath == _currentPath;
                    }).toList();

                    if (currentDirFolders.isEmpty && mediaDocs.isEmpty) {
                      return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 64, color: Colors.white24),
                              const SizedBox(height: 16),
                              Text("This folder is empty.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 18)),
                            ],
                          )
                      );
                    }

                    int totalItems = currentDirFolders.length + mediaDocs.length;

                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 16, mainAxisSpacing: 16),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {

                        // --- RENDER FOLDERS FIRST ---
                        if (index < currentDirFolders.length) {
                          String folderFullPath = currentDirFolders[index];
                          String folderName = folderFullPath.split('/').last;

                          return GestureDetector(
                            onTap: () => setState(() => _currentPath = folderFullPath),
                            child: Container(
                              decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.folder_rounded, color: Colors.amber, size: 64),
                                        const SizedBox(height: 8),
                                        Text(folderName, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    top: 8, right: 8,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                                      onPressed: () => _deleteFolder(folderFullPath),
                                      tooltip: "Remove Folder",
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        }

                        // --- RENDER MEDIA FILES SECOND ---
                        final fileIndex = index - currentDirFolders.length;
                        final docId = mediaDocs[fileIndex].id;
                        final data = mediaDocs[fileIndex].data() as Map<String, dynamic>;

                        final mediaUrl = data['url'] ?? '';
                        final thumbUrl = data['thumbnailUrl'] ?? '';
                        final fileName = data['name'] ?? 'Unknown File';
                        final isVideo = data['type'] == 'video';
                        final is3D = data['type'] == '3d';

                        String? bgImage;
                        if (!isVideo && !is3D && mediaUrl.isNotEmpty) bgImage = mediaUrl;
                        else if (thumbUrl.isNotEmpty) bgImage = thumbUrl;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.glassBackground,
                                border: Border.all(color: AppColors.glassBorder),
                                borderRadius: BorderRadius.circular(16),
                                image: bgImage != null ? DecorationImage(image: NetworkImage(bgImage), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)) : null,
                              ),
                              child: Center(child: Icon(isVideo ? Icons.play_circle_fill : (is3D ? Icons.view_in_ar_rounded : Icons.image), color: Colors.white70, size: 48)),
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () => _confirmDeleteFile(docId, fileName, thumbUrl),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)]),
                                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8, left: 8, right: 8,
                              child: Text(fileName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                            )
                          ],
                        );
                      },
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