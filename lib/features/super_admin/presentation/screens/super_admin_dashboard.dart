// File: lib/features/super_admin/presentation/screens/super_admin_dashboard.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/super_admin_service.dart';
import '../../domain/tenant_model.dart';
import '../widgets/add_client_modal.dart';
import '../widgets/deploy_update_modal.dart'; // 🚀 NEW: Import the deployment modal

/// Documentation:
/// The main Level 1 control panel. Displays a list of all clients (tenants)
/// and provides tools to manage them.
class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({Key? key}) : super(key: key);

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final AuthService _authService = AuthService();
  final SuperAdminService _adminService = SuperAdminService();

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
        child: SafeArea(
          child: Column(
            children: [
              // Custom Glass Top Bar
              _buildTopBar(),

              // Main Content Area (List of Clients)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildClientList(),
                ),
              ),
            ],
          ),
        ),
      ),
      // A floating action button to add new clients
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // This tells Flutter to pop up our new Glass Dialog!
          showDialog(
            context: context,
            barrierColor: Colors.black.withOpacity(0.4), // Darkens the background slightly
            builder: (BuildContext context) {
              return const AddClientModal();
            },
          );
        },
        backgroundColor: Colors.white,
        icon: const Icon(Icons.add_business_rounded, color: AppColors.backgroundGradientStart),
        label: Text(
          "New Client",
          style: GoogleFonts.poppins(color: AppColors.backgroundGradientStart, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Documentation:
  /// A beautiful custom top bar for the dashboard.
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.glassBackground,
        border: const Border(bottom: BorderSide(color: AppColors.glassBorder, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Super Admin Control",
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),

          // 🚀 NEW: Grouped buttons for Deploy Update and Log Out
          Row(
            children: [
              // The Fleet Update Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                icon: const Icon(Icons.system_update_alt_rounded),
                label: Text("Deploy Update", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                onPressed: () {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black.withOpacity(0.4),
                    builder: (context) => const DeployUpdateModal(),
                  );
                },
              ),
              const SizedBox(width: 16),

              // Original Logout Button
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                tooltip: 'Log Out',
                onPressed: () => _authService.signOut(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Documentation:
  /// Listens to Firebase and builds a list of Glass cards for each client.
  Widget _buildClientList() {
    return StreamBuilder<List<Tenant>>(
      stream: _adminService.getClientsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              "No clients found. Click 'New Client' to add one.",
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16),
            ),
          );
        }

        final clients = snapshot.data!;

        return ListView.builder(
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final client = clients[index];
            return Card(
              color: AppColors.glassBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.glassBorder),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: const Icon(Icons.storefront_rounded, color: Colors.white),
                ),
                title: Text(
                  client.companyName,
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.contactEmail, style: GoogleFonts.poppins(color: Colors.white70)),
                    const SizedBox(height: 4),
                    // Displaying the exact Expiry Date
                    Text(
                      "License Expires: ${client.licenseEndDate.day}/${client.licenseEndDate.month}/${client.licenseEndDate.year}",
                      style: GoogleFonts.poppins(
                        // If it's expired, turn it RED. Otherwise, keep it Amber.
                        color: client.licenseEndDate.isBefore(DateTime.now())
                            ? Colors.redAccent
                            : Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // THE NEW ACTION MENU
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Chip
                    Chip(
                      label: Text(client.isActive ? "Active" : "Paused", style: const TextStyle(color: Colors.white, fontSize: 12)),
                      backgroundColor: client.isActive ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
                    ),
                    const SizedBox(width: 8),
                    // Three-dot Menu for Actions
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF4A00E0), // Matching your theme
                      onSelected: (value) async {
                        if (value == 'pause') {
                          await _adminService.toggleClientStatus(client.id, client.isActive);
                        } else if (value == 'edit') {
                          // TODO: Open Edit Modal
                          print("Edit clicked for ${client.companyName}");
                        } else if (value == 'delete') {
                          // Added a confirmation dialog before permanent deletion
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF4A00E0),
                              title: const Text("Delete Client?", style: TextStyle(color: Colors.white)),
                              content: const Text("This action cannot be undone.", style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: Colors.white))),
                                TextButton(
                                  onPressed: () async {
                                    await _adminService.deleteClient(client.id);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text("DELETE", style: TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit Profile & License', style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                          value: 'pause',
                          child: Text(client.isActive ? 'Pause Account' : 'Unpause Account', style: const TextStyle(color: Colors.white)),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('Delete Client', style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}