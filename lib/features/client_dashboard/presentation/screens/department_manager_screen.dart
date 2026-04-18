// File: lib/features/client_dashboard/presentation/screens/department_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';

class DepartmentManagerScreen extends StatefulWidget {
  const DepartmentManagerScreen({Key? key}) : super(key: key);

  @override
  State<DepartmentManagerScreen> createState() => _DepartmentManagerScreenState();
}

class _DepartmentManagerScreenState extends State<DepartmentManagerScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _currentClientId;

  @override
  void initState() {
    super.initState();
    _fetchClientId();
  }

  Future<void> _fetchClientId() async {
    final appUser = await _authService.userStateStream.first;
    if (mounted) setState(() => _currentClientId = appUser?.uid);
  }

  // ==========================================================
  // 🌟 NEW: SMART AUTO-SYNC ALGORITHM
  // Scans existing products and imports their departments
  // ==========================================================
  Future<void> _syncDepartmentsFromCatalog() async {
    if (_currentClientId == null) return;

    // Show a loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
    );

    try {
      final docRef = _firestore.collection('clients').doc(_currentClientId);
      final snapshot = await docRef.get();
      final data = snapshot.data();
      if (data == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final List<dynamic> rawCatalog = data['catalog'] ?? [];
      final List<dynamic> existingDepts = data['departments'] ?? [];

      // 1. Gather all unique department names from your existing products
      Set<String> catalogDeptNames = {};
      for (var item in rawCatalog) {
        String deptName = item['department']?.toString().trim() ?? '';
        if (deptName.isNotEmpty) {
          catalogDeptNames.add(deptName);
        }
      }

      // 2. Gather names of departments that are already in our Manager
      Set<String> managedDeptNames = {};
      for (var dept in existingDepts) {
        String name = dept['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          managedDeptNames.add(name);
        }
      }

      // 3. Compare and add the missing ones
      bool hasChanges = false;
      List<dynamic> updatedDepts = List.from(existingDepts);

      for (String catDept in catalogDeptNames) {
        // We do a lowercase check to avoid duplicating "MEN" and "Men"
        bool exists = managedDeptNames.any((m) => m.toLowerCase() == catDept.toLowerCase());

        if (!exists) {
          updatedDepts.add({
            'name': catDept,
            'imageUrl': '', // Starts empty so you can assign a cover later!
          });
          hasChanges = true;
        }
      }

      // 4. Save to Firebase
      if (hasChanges) {
        await docRef.update({'departments': updatedDepts});
      }

      if (mounted) {
        Navigator.pop(context); // Close the loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasChanges
                  ? "Successfully imported missing departments!"
                  : "All departments are already synced up.",
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: hasChanges ? Colors.green : Colors.blueAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error syncing: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _addOrEditDepartment(Map<String, dynamic>? existingDept, int? index) async {
    final nameController = TextEditingController(text: existingDept?['name'] ?? '');
    String selectedImageUrl = existingDept?['imageUrl'] ?? '';

    await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.glassBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.glassBorder),
                ),
                title: Text(existingDept == null ? "New Department" : "Edit Department",
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        style: GoogleFonts.poppins(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Department Name (e.g., Antivol, MEN)",
                          labelStyle: GoogleFonts.poppins(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("Dedicated Background Image", style: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                      // Media Preview / Picker Button
                      GestureDetector(
                        onTap: () async {
                          // Open a simple media picker dialog
                          final String? newImage = await _pickImageFromLibrary();
                          if (newImage != null) {
                            setDialogState(() => selectedImageUrl = newImage);
                          }
                        },
                        child: Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                            image: selectedImageUrl.isNotEmpty
                                ? DecorationImage(image: NetworkImage(selectedImageUrl), fit: BoxFit.cover)
                                : null,
                          ),
                          child: selectedImageUrl.isEmpty
                              ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_rounded, color: Colors.white54, size: 40),
                              SizedBox(height: 8),
                              Text("Select Image from Library", style: TextStyle(color: Colors.white54))
                            ],
                          )
                              : Container(
                            color: Colors.black45,
                            child: const Center(child: Icon(Icons.edit, color: Colors.white, size: 32)),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart),
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;

                      final docRef = _firestore.collection('clients').doc(_currentClientId);
                      final snapshot = await docRef.get();
                      List<dynamic> depts = snapshot.data()?['departments'] ?? [];

                      final newDept = {
                        'name': nameController.text.trim(),
                        'imageUrl': selectedImageUrl,
                      };

                      if (index != null) {
                        depts[index] = newDept; // Update
                      } else {
                        depts.add(newDept); // Add new
                      }

                      await docRef.update({'departments': depts});
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text("Save Department", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              );
            }
        )
    );
  }

  // A helper to let them pick from their already-uploaded media
  Future<String?> _pickImageFromLibrary() async {
    String? chosenUrl;
    await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.glassBackground,
          title: Text("Select Background", style: GoogleFonts.poppins(color: Colors.white)),
          content: SizedBox(
            width: 600, height: 400,
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).collection('media')
                  .where('type', isEqualTo: 'image').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final url = docs[i]['url'];
                    return GestureDetector(
                      onTap: () {
                        chosenUrl = url;
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        )
    );
    return chosenUrl;
  }

  Future<void> _deleteDepartment(int index) async {
    final docRef = _firestore.collection('clients').doc(_currentClientId);
    final snapshot = await docRef.get();
    List<dynamic> depts = snapshot.data()?['departments'] ?? [];
    depts.removeAt(index);
    await docRef.update({'departments': depts});
  }

  @override
  Widget build(BuildContext context) {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Department Manager", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),

              // 👇 NEW: Sync & Add Buttons Grouped Together
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _syncDepartmentsFromCatalog,
                    icon: const Icon(Icons.sync_rounded, color: Colors.white),
                    label: Text("Sync from Catalog", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _addOrEditDepartment(null, null),
                    icon: const Icon(Icons.add),
                    label: Text("New Department", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.backgroundGradientStart,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text("Set dedicated cinematic backgrounds for your Lookbook.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 24),

          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('clients').doc(_currentClientId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final List<dynamic> depts = snapshot.data!.data() is Map
                    ? (snapshot.data!.data() as Map<String, dynamic>)['departments'] ?? []
                    : [];

                if (depts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        Text("No departments created yet.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 18)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _syncDepartmentsFromCatalog,
                          icon: const Icon(Icons.auto_awesome),
                          label: Text("Auto-Import from Products", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        )
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, childAspectRatio: 1.5, crossAxisSpacing: 16, mainAxisSpacing: 16
                  ),
                  itemCount: depts.length,
                  itemBuilder: (context, index) {
                    final dept = depts[index];
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        image: DecorationImage(
                            image: NetworkImage(dept['imageUrl'] ?? ''),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken)
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(child: Text(dept['name'].toString().toUpperCase(), style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4))),
                          Positioned(
                            top: 8, right: 8,
                            child: Row(
                              children: [
                                IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: () => _addOrEditDepartment(dept, index)),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteDepartment(index)),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}