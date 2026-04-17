// File: lib/features/client_dashboard/presentation/screens/catalog_builder_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../domain/catalog_item.dart';

// REMOVED: import 'package:model_viewer_plus/model_viewer_plus.dart';

class CatalogBuilderScreen extends StatefulWidget {
  const CatalogBuilderScreen({Key? key}) : super(key: key);

  @override
  State<CatalogBuilderScreen> createState() => _CatalogBuilderScreenState();
}

class _CatalogBuilderScreenState extends State<CatalogBuilderScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentClientId;

  // Form State
  CatalogItem? _selectedItem;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _qrController = TextEditingController();

  String _selectedMediaUrl = '';
  String _selectedMediaType = 'image';
  bool _inStock = true;
  bool _isSaving = false;

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

  void _clearForm() {
    setState(() {
      _selectedItem = null;
      _titleController.clear();
      _descController.clear();
      _categoryController.clear();
      _priceController.clear();
      _qrController.clear();
      _selectedMediaUrl = '';
      _selectedMediaType = 'image';
      _inStock = true;
    });
  }

  void _loadItemIntoForm(CatalogItem item) {
    setState(() {
      _selectedItem = item;
      _titleController.text = item.title;
      _descController.text = item.description;
      _categoryController.text = item.category;
      _priceController.text = item.price > 0 ? item.price.toString() : '';
      _qrController.text = item.qrActionUrl;
      _selectedMediaUrl = item.mediaUrl;
      _selectedMediaType = item.mediaType;
      _inStock = item.inStock;
    });
  }

  Future<void> _openMediaPicker() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.glassBackground,
          title: Text("Select Media", style: GoogleFonts.poppins(color: Colors.white)),
          content: SizedBox(
            width: 600,
            height: 400,
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).collection('media').orderBy('uploadedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final mediaType = data['type'];
                    final url = data['url'];

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedMediaUrl = url;
                          _selectedMediaType = mediaType;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _selectedMediaUrl == url ? AppColors.backgroundGradientStart : Colors.transparent, width: 3),
                          image: mediaType == 'image' ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
                        ),
                        child: Center(
                          child: mediaType == 'video'
                              ? const Icon(Icons.play_circle_fill, color: Colors.white70, size: 32)
                              : (mediaType == '3d' ? const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 32) : null),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)))],
        );
      },
    );
  }

  Future<void> _saveCatalogItem() async {
    if (!_formKey.currentState!.validate() || _selectedMediaUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Title and Media are required."), backgroundColor: Colors.redAccent)
      );
      return;
    }

    setState(() => _isSaving = true);

    final priceText = _priceController.text.trim();
    final double parsedPrice = priceText.isEmpty ? 0.0 : (double.tryParse(priceText) ?? 0.0);

    final Map<String, dynamic> itemData = {
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'category': _categoryController.text.trim().isEmpty ? 'Uncategorized' : _categoryController.text.trim(),
      'price': parsedPrice,
      'currency': 'DZD',
      'mediaUrl': _selectedMediaUrl,
      'mediaType': _selectedMediaType,
      'inStock': _inStock,
      'qrActionUrl': _qrController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_selectedItem == null) {
        itemData['viewCount'] = 0;
        itemData['qrScanCount'] = 0;
        await _firestore.collection('clients').doc(_currentClientId).collection('catalog_items').add(itemData);
      } else {
        await _firestore.collection('clients').doc(_currentClientId).collection('catalog_items').doc(_selectedItem!.id).update(itemData);
      }

      _clearForm();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Saved!"), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent));
    }

    setState(() => _isSaving = false);
  }

  Future<void> _deleteItem(String id) async {
    await _firestore.collection('clients').doc(_currentClientId).collection('catalog_items').doc(id).delete();
    if (_selectedItem?.id == id) _clearForm();
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

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).collection('catalog_items').orderBy('category').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return Center(child: Text("No products yet.", style: GoogleFonts.poppins(color: Colors.white54)));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final item = CatalogItem.fromMap(docs[index].data() as Map<String, dynamic>, docs[index].id);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.black45,
                backgroundImage: item.mediaType == 'image' ? NetworkImage(item.mediaUrl) : null,
                child: item.mediaType == 'video'
                    ? const Icon(Icons.play_arrow, color: Colors.white)
                    : (item.mediaType == '3d' ? const Icon(Icons.view_in_ar, color: Colors.white) : null),
              ),
              title: Text(item.title, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(item.price > 0 ? "${item.category} • ${item.price} DZD" : item.category, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
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

            Row(
              children: [
                Expanded(child: _buildTextField(_titleController, "Product Name *", isRequired: true)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(_categoryController, "Category (Optional)")),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(_priceController, "Price in DZD (Optional)", isNumber: true)),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(_descController, "Detailed Description (Optional)", maxLines: 4),
            const SizedBox(height: 16),
            _buildTextField(_qrController, "Online Store Link (Optional)", isUrl: true),

            const SizedBox(height: 24),
            const Divider(color: Colors.white24),
            const SizedBox(height: 24),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Product Media *", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _openMediaPicker,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                          image: _selectedMediaUrl.isNotEmpty && _selectedMediaType == 'image'
                              ? DecorationImage(image: NetworkImage(_selectedMediaUrl), fit: BoxFit.cover)
                              : null,
                        ),
                        child: _selectedMediaUrl.isEmpty
                            ? const Center(child: Icon(Icons.add_photo_alternate, color: Colors.white54, size: 40))
                            : (_selectedMediaType == '3d'
                            ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.view_in_ar_rounded, color: Colors.white70, size: 50),
                              SizedBox(height: 8),
                              Text("3D Model Selected", style: TextStyle(color: Colors.white54, fontSize: 10)),
                            ],
                          ),
                        ) // FIXED: Removed ModelViewer usage
                            : (_selectedMediaType == 'video' ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50)) : null)),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 32),

                Expanded(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text("In Stock", style: GoogleFonts.poppins(color: Colors.white)),
                        subtitle: Text("If false, item will show as 'Sold Out' on Kiosk.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
                        value: _inStock,
                        activeColor: AppColors.backgroundGradientStart,
                        onChanged: (val) => setState(() => _inStock = val),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveCatalogItem,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : Text("Save Product", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                )
              ],
            )
          ],
        ),
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