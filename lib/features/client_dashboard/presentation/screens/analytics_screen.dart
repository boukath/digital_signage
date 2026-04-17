// File: lib/features/client_dashboard/presentation/screens/analytics_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../domain/catalog_item.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
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

  // Temporary function to inject test data
  Future<void> _injectTestData() async {
    if (_currentClientId == null) return;

    // Grab all catalog items
    final snapshot = await _firestore
        .collection('clients')
        .doc(_currentClientId)
        .collection('catalog_items')
        .get();

    // Loop through and update them with fake analytics numbers!
    for (var doc in snapshot.docs) {
      await doc.reference.update({
        'viewCount': 150, // Sets all to 150 views
        'qrScanCount': 12, // Sets all to 12 scans
      });
    }

    print("TEST DATA INJECTED!");
  }

  @override
  Widget build(BuildContext context) {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Touch Analytics", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          Text("Real-time customer engagement from your physical screens.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 32),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Order by viewCount descending to create a leaderboard automatically
              stream: _firestore.collection('clients').doc(_currentClientId).collection('catalog_items')
                  .orderBy('viewCount', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text("Error loading analytics.", style: GoogleFonts.poppins(color: Colors.redAccent)));

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(child: Text("No catalog items to track yet.", style: GoogleFonts.poppins(color: Colors.white54)));
                }

                // Parse items and calculate total metrics
                final items = docs.map((doc) => CatalogItem.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();

                int totalViews = 0;
                int totalScans = 0;
                for (var item in items) {
                  totalViews += item.viewCount;
                  totalScans += item.qrScanCount;
                }

                // Get the top performer for the progress bar relative sizing
                final highestViews = items.first.viewCount > 0 ? items.first.viewCount : 1;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. KPI Top Cards
                    Row(
                      children: [
                        Expanded(child: _buildKpiCard("Total Product Views", totalViews.toString(), Icons.touch_app, Colors.blueAccent)),
                        const SizedBox(width: 24),
                        Expanded(child: _buildKpiCard("Total QR Scans", totalScans.toString(), Icons.qr_code_scanner, Colors.orangeAccent)),
                        const SizedBox(width: 24),
                        Expanded(child: _buildKpiCard("Top Performer", items.first.viewCount > 0 ? items.first.title : "N/A", Icons.emoji_events, Colors.amberAccent)),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 2. Leaderboard List
                    Text("Product Leaderboard", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.all(8),
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            // Calculate percentage for the visual progress bar
                            final double percentage = item.viewCount / highestViews;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  // Rank number
                                  SizedBox(
                                    width: 30,
                                    child: Text("#${index + 1}", style: GoogleFonts.poppins(color: index < 3 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),

                                  // Thumbnail
                                  CircleAvatar(
                                    backgroundColor: Colors.black45,
                                    backgroundImage: item.mediaType == 'image' ? NetworkImage(item.mediaUrl) : null,
                                    child: item.mediaType == 'video' ? const Icon(Icons.play_arrow, color: Colors.white, size: 16) : (item.mediaType == '3d' ? const Icon(Icons.view_in_ar, color: Colors.white, size: 16) : null),
                                  ),
                                  const SizedBox(width: 16),

                                  // Title and Bar
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.title, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Stack(
                                          children: [
                                            Container(height: 8, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4))),
                                            AnimatedContainer(
                                              duration: const Duration(milliseconds: 500),
                                              height: 8,
                                              // We use FractionallySizedBox to fill the width based on the percentage
                                              width: MediaQuery.of(context).size.width * 0.3 * percentage,
                                              decoration: BoxDecoration(
                                                  gradient: const LinearGradient(colors: [AppColors.backgroundGradientStart, AppColors.backgroundGradientEnd]),
                                                  borderRadius: BorderRadius.circular(4)
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),

                                  // Exact Numbers
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("${item.viewCount} Views", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text("${item.qrScanCount} Scans", style: GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 12)),
                                    ],
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}