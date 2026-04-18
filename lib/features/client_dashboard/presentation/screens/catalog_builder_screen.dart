// File: lib/features/client_dashboard/presentation/screens/catalog_builder_screen.dart

import 'dart:typed_data'; // 👈 NEW: Fixes the Uint8List compiler error
import 'package:flutter/foundation.dart' show kIsWeb; // 👈 NEW: Required for the Web safeguard

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../domain/catalog_item.dart';
import '../../data/b2_storage_service.dart';
import '../../../../core/utils/thumbnail_router.dart';

class CatalogBuilderScreen extends StatefulWidget {
  const CatalogBuilderScreen({Key? key}) : super(key: key);

  @override
  State<CatalogBuilderScreen> createState() => _CatalogBuilderScreenState();
}

class _CatalogBuilderScreenState extends State<CatalogBuilderScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final B2StorageService _b2Service = B2StorageService();

  String? _currentClientId;
  CatalogItem? _selectedItem;
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _departmentController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _qrController = TextEditingController();

  List<Map<String, dynamic>> _selectedGallery = [];

  bool _inStock = true;
  bool _isSaving = false;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    _fetchClientId();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _departmentController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _qrController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientId() async {
    final appUser = await _authService.userStateStream.first;
    if (mounted) setState(() => _currentClientId = appUser?.uid);
  }

  void _clearForm() {
    setState(() {
      _selectedItem = null;
      _titleController.clear();
      _descController.clear();
      _departmentController.clear();
      _categoryController.clear();
      _priceController.clear();
      _qrController.clear();
      _selectedGallery = [];
      _inStock = true;
    });
  }

  void _loadItemIntoForm(CatalogItem item) {
    setState(() {
      _selectedItem = item;
      _titleController.text = item.title;
      _descController.text = item.description;
      _departmentController.text = item.department;
      _categoryController.text = item.category;
      _priceController.text = item.price > 0 ? item.price.toString() : '';
      _qrController.text = item.qrActionUrl;
      _inStock = item.inStock;

      if (item.gallery.isNotEmpty) {
        _selectedGallery = List<Map<String, dynamic>>.from(item.gallery);
      } else if (item.mediaUrl.isNotEmpty) {
        _selectedGallery = [{'url': item.mediaUrl, 'type': item.mediaType, 'thumbnailUrl': item.thumbnailUrl}];
      } else {
        _selectedGallery = [];
      }
    });
  }

  Future<void> _uploadDirectMedia(Function setDialogState, List<Map<String, dynamic>> tempGallery) async {
    if (_currentClientId == null) return;

    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'glb', 'gltf'],
      withReadStream: !kIsWeb,
      withData: kIsWeb,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setDialogState(() => _isUploadingMedia = true);

      for (var file in result.files) {
        if (file.readStream == null && file.bytes == null) continue;

        final fileName = file.name;
        String fileType = 'image';
        if (fileName.toLowerCase().endsWith('.mp4')) fileType = 'video';
        if (fileName.toLowerCase().endsWith('.glb') || fileName.toLowerCase().endsWith('.gltf')) fileType = '3d';

        String? downloadUrl;
        String autoThumbnailUrl = '';

        Stream<Uint8List> getFileStream() {
          if (kIsWeb && file.bytes != null) {
            return Stream.value(file.bytes!);
          } else {
            return file.readStream!.map((chunk) => Uint8List.fromList(chunk));
          }
        }

        if (fileType == 'video') {
          Uint8List? thumbBytes = await AppThumbnailHelper.extract(file);

          Future<String?> videoUploadTask = _b2Service.uploadMediaStream(
              fileName,
              getFileStream(),
              file.size,
              _currentClientId!
          );

          Future<String?> thumbUploadTask = Future.value(null);
          if (thumbBytes != null) {
            String thumbName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
            thumbUploadTask = _b2Service.uploadMedia(thumbName, thumbBytes, _currentClientId!);
          }

          final uploadResults = await Future.wait([videoUploadTask, thumbUploadTask]);
          downloadUrl = uploadResults[0];
          if (uploadResults[1] != null) autoThumbnailUrl = uploadResults[1]!;

        } else {
          downloadUrl = await _b2Service.uploadMediaStream(
              fileName,
              getFileStream(),
              file.size,
              _currentClientId!
          );
        }

        if (downloadUrl != null) {
          // 🌟 ADDED: Assign 'folderPath: ""' initially so it is ready to be organized
          await _firestore.collection('clients').doc(_currentClientId).collection('media').add({
            'url': downloadUrl,
            'name': fileName,
            'type': fileType,
            'thumbnailUrl': autoThumbnailUrl,
            'folderPath': "",
            'uploadedAt': FieldValue.serverTimestamp(),
          });

          setDialogState(() {
            tempGallery.add({
              'url': downloadUrl,
              'type': fileType,
              'thumbnailUrl': autoThumbnailUrl
            });
          });
        }
      }
      setDialogState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _openMediaPicker() async {
    List<Map<String, dynamic>> tempGallery = List.from(_selectedGallery);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.glassBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.glassBorder)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Select Media Gallery", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text("Select from library or upload new files.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _isUploadingMedia ? null : () => _uploadDirectMedia(setDialogState, tempGallery),
                    icon: _isUploadingMedia
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(_isUploadingMedia ? "Uploading..." : "Upload New", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  )
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 450,
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('clients').doc(_currentClientId).collection('media').orderBy('uploadedAt', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;

                    if (docs.isEmpty) return Center(child: Text("Your media library is empty. Click 'Upload New' to start.", style: GoogleFonts.poppins(color: Colors.white54)));

                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final mediaType = data['type'];
                        final url = data['url'];
                        final thumbUrl = data['thumbnailUrl'] ?? '';
                        final isSelected = tempGallery.any((m) => m['url'] == url);

                        String? bgImage;
                        if (mediaType == 'image' && url.isNotEmpty) {
                          bgImage = url;
                        } else if (thumbUrl.isNotEmpty) {
                          bgImage = thumbUrl;
                        }

                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              if (isSelected) {
                                tempGallery.removeWhere((m) => m['url'] == url);
                              } else {
                                tempGallery.add({'url': url, 'type': mediaType, 'thumbnailUrl': thumbUrl});
                              }
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? AppColors.backgroundGradientStart : Colors.white24, width: isSelected ? 4 : 1),
                              image: bgImage != null ? DecorationImage(
                                  image: NetworkImage(bgImage),
                                  fit: BoxFit.cover,
                                  colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)
                              ) : null,
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: mediaType == 'video' ? const Icon(Icons.play_circle_fill, color: Colors.white70, size: 32)
                                      : (mediaType == '3d' ? const Icon(Icons.view_in_ar_rounded, color: Colors.white70, size: 32) : null),
                                ),
                                if (isSelected) const Positioned(top: 8, right: 8, child: Icon(Icons.check_circle, color: AppColors.backgroundGradientStart, size: 28)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedGallery = tempGallery);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart),
                  child: Text("Confirm Gallery (${tempGallery.length})", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectCoverForVideo(int galleryIndex) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.glassBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.glassBorder)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Set Video Cover Image", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
              Text("Select an image to display before the video plays.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
            ],
          ),
          content: SizedBox(
            width: 700,
            height: 450,
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).collection('media').where('type', isEqualTo: 'image').orderBy('uploadedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;

                if (docs.isEmpty) return Center(child: Text("No images in library. Upload an image first to use as a cover.", style: GoogleFonts.poppins(color: Colors.white54)));

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final url = data['url'];

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedGallery[galleryIndex]['thumbnailUrl'] = url;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 1),
                          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))),
          ],
        );
      },
    );
  }

  Future<void> _saveCatalogItem() async {
    if (!_formKey.currentState!.validate() || _selectedGallery.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Title and at least 1 Media item are required."), backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isSaving = true);

    final priceText = _priceController.text.trim();
    final double parsedPrice = priceText.isEmpty ? 0.0 : (double.tryParse(priceText) ?? 0.0);

    final primaryMedia = _selectedGallery.first;

    final Map<String, dynamic> itemData = {
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'department': _departmentController.text.trim().isEmpty ? 'General' : _departmentController.text.trim(),
      'category': _categoryController.text.trim().isEmpty ? 'Uncategorized' : _categoryController.text.trim(),
      'price': parsedPrice,
      'currency': 'DZD',
      'mediaUrl': primaryMedia['url'],
      'mediaType': primaryMedia['type'],
      'thumbnailUrl': primaryMedia['thumbnailUrl'] ?? '',
      'gallery': _selectedGallery,
      'inStock': _inStock,
      'qrActionUrl': _qrController.text.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      final docRef = _firestore.collection('clients').doc(_currentClientId);

      final snapshot = await docRef.get();
      if (!snapshot.exists) throw Exception("Client document missing!");

      final data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> currentCatalog = data['catalog'] ?? [];

      if (_selectedItem == null) {
        itemData['id'] = _firestore.collection('dummy').doc().id;
        itemData['viewCount'] = 0;
        itemData['qrScanCount'] = 0;
        currentCatalog.add(itemData);
      } else {
        itemData['id'] = _selectedItem!.id;
        itemData['viewCount'] = _selectedItem!.viewCount;
        itemData['qrScanCount'] = _selectedItem!.qrScanCount;

        int index = currentCatalog.indexWhere((item) => item['id'] == _selectedItem!.id);
        if (index != -1) {
          currentCatalog[index] = itemData;
        } else {
          currentCatalog.add(itemData);
        }
      }

      await docRef.update({'catalog': currentCatalog});

      // ==========================================================
      // 🌟 MAGIC AUTO-FOLDER CREATOR 🌟
      // Extracts Department and Title, creates the folder, and moves files into it!
      // ==========================================================
      String dept = itemData['department'];
      String title = itemData['title'];
      String targetFolder = "$dept/$title"; // e.g. "MEN/Sneakers"

      // 1. Create the folders in the virtual file system
      await docRef.set({
        'mediaFolders': FieldValue.arrayUnion([dept, targetFolder])
      }, SetOptions(merge: true));

      // 2. Gather all the URLs that belong to this product
      List<String> productUrls = [];
      for (var g in _selectedGallery) {
        if (g['url'] != null) productUrls.add(g['url']);
      }

      // 3. Update the media documents so they appear inside the new folder!
      if (productUrls.isNotEmpty) {
        final mediaSnapshot = await docRef.collection('media').get();
        for (var doc in mediaSnapshot.docs) {
          final docData = doc.data();
          if (productUrls.contains(docData['url'])) {
            await doc.reference.update({'folderPath': targetFolder});
          }
        }
      }

      _clearForm();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Saved & Auto-Organized!"), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent));
    }

    setState(() => _isSaving = false);
  }

  Future<void> _deleteItem(String id) async {
    try {
      final docRef = _firestore.collection('clients').doc(_currentClientId);

      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> currentCatalog = data['catalog'] ?? [];

      currentCatalog.removeWhere((item) => item['id'] == id);

      await docRef.update({'catalog': currentCatalog});

      if (_selectedItem?.id == id) _clearForm();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Deleted"), backgroundColor: Colors.orange));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Error: $e"), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Catalog Builder", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: _clearForm,
                icon: const Icon(Icons.add),
                label: Text("New Product", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
                    child: _buildProductList(),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
                    child: _buildForm(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> rawCatalog = data['catalog'] ?? [];

        final List<CatalogItem> catalogItems = rawCatalog.map((json) {
          return CatalogItem.fromMap(json as Map<String, dynamic>);
        }).toList();

        // 👈 Sort primarily by Department, then Category
        catalogItems.sort((a, b) {
          int deptCompare = a.department.compareTo(b.department);
          if (deptCompare != 0) return deptCompare;
          return a.category.compareTo(b.category);
        });

        if (catalogItems.isEmpty) return Center(child: Text("No products yet.", style: GoogleFonts.poppins(color: Colors.white54)));

        return ListView.builder(
          itemCount: catalogItems.length,
          itemBuilder: (context, index) {
            final item = catalogItems[index];

            String avatarUrl = item.mediaType == 'image' ? item.mediaUrl : item.thumbnailUrl;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.black45,
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: item.mediaType == 'video' && avatarUrl.isEmpty
                    ? const Icon(Icons.play_arrow, color: Colors.white)
                    : (item.mediaType == '3d' && avatarUrl.isEmpty ? const Icon(Icons.view_in_ar, color: Colors.white) : null),
              ),
              title: Text(item.title, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),

              // 👈 Updated subtitle to show Breadcrumb: Department > Category
              subtitle: Text(
                  item.price > 0 ? "${item.department} > ${item.category} • ${item.price} DZD" : "${item.department} > ${item.category}",
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)
              ),

              onTap: () => _loadItemIntoForm(item),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                onPressed: () => _deleteItem(item.id),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_selectedItem == null ? "Create New Product" : "Edit Product", style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            // 👈 REORGANIZED FORM FIELDS
            Row(
              children: [
                Expanded(flex: 2, child: _buildTextField(_titleController, "Product Name *", isRequired: true)),
                const SizedBox(width: 16),
                Expanded(flex: 1, child: _buildTextField(_priceController, "Price in DZD (Optional)", isNumber: true)),
              ],
            ),
            const SizedBox(height: 16),

            // 👈 NEW ROW FOR HIERARCHY
            Row(
              children: [
                Expanded(child: _buildTextField(_departmentController, "Department (e.g., MEN, WOMEN, KIDS)")),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(_categoryController, "Category (e.g., T-Shirts, Shoes)")),
              ],
            ),

            const SizedBox(height: 16),
            _buildTextField(_descController, "Detailed Description (Optional)", maxLines: 4),
            const SizedBox(height: 16),
            _buildTextField(_qrController, "Online Store Link (Optional)", isUrl: true),

            const SizedBox(height: 32),

            Text("Cinematic Media Gallery *", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text("Select multiple items. Drag left/right to reorder. The first item acts as the main thumbnail.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),

            SizedBox(
              height: 120, // Height of the cinematic strip
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _openMediaPicker,
                    child: Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24, width: 2, style: BorderStyle.solid),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded, color: Colors.white54, size: 36),
                          SizedBox(height: 8),
                          Text("Add Media", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    child: ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final item = _selectedGallery.removeAt(oldIndex);
                          _selectedGallery.insert(newIndex, item);
                        });
                      },
                      children: [
                        for (int i = 0; i < _selectedGallery.length; i++)
                          _buildGalleryThumbnail(_selectedGallery[i], i, key: ValueKey('${_selectedGallery[i]['url']}_$i')),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Divider(color: Colors.white24),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("In Stock", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("If false, item will show as 'Sold Out' on Kiosk.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
                    value: _inStock,
                    activeColor: AppColors.backgroundGradientStart,
                    onChanged: (val) => setState(() => _inStock = val),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveCatalogItem,
                      icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.check_circle),
                      label: Text(_isSaving ? "Saving..." : "Save Product", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryThumbnail(Map<String, dynamic> media, int index, {required Key key}) {
    bool isPrimary = index == 0;

    String? thumbUrl = media['thumbnailUrl'];
    String? bgImage = media['type'] == 'image' ? media['url'] : (thumbUrl != null && thumbUrl.isNotEmpty ? thumbUrl : null);

    return Container(
      key: key,
      width: 120,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isPrimary ? AppColors.backgroundGradientStart : Colors.white24, width: isPrimary ? 2 : 1),
        image: bgImage != null ? DecorationImage(image: NetworkImage(bgImage), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken)) : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media['type'] == 'video')
            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36)),
          if (media['type'] == '3d')
            const Center(child: Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 36)),

          if (media['type'] != 'image')
            Positioned(
              top: 4, left: 4,
              child: GestureDetector(
                onTap: () => _selectCoverForVideo(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image, color: Colors.white, size: 10),
                      SizedBox(width: 4),
                      Text("Cover", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),

          if (isPrimary)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(
                    color: AppColors.backgroundGradientStart,
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10))
                ),
                child: const Text("⭐ Main", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),

          Positioned(
            top: 4, right: 4,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedGallery.removeAt(index));
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1, bool isNumber = false, bool isUrl = false, bool isRequired = false}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : (isUrl ? TextInputType.url : TextInputType.text),
      style: GoogleFonts.poppins(color: Colors.white),
      validator: isRequired ? (val) => val == null || val.isEmpty ? "Required" : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.white54),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}