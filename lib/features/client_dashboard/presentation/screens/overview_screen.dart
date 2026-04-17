// File: lib/features/client_dashboard/presentation/screens/overview_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../features/auth/domain/app_user.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({Key? key}) : super(key: key);

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentClientId;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  /// Documentation:
  /// Fetches the logged-in client's ID and user profile to display license info.
  Future<void> _fetchUserData() async {
    final appUser = await _authService.userStateStream.first;
    if (mounted) {
      setState(() {
        _currentUser = appUser;
        _currentClientId = appUser?.uid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentClientId == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Welcome Back!",
            style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            "Here is the real-time status of your digital signage network.",
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.white54),
          ),
          const SizedBox(height: 32),

          // The Grid of Stat Cards
          Expanded(
            child: GridView.count(
              crossAxisCount: 3, // 3 cards across
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
              childAspectRatio: 1.5, // Makes the cards wider than they are tall
              children: [
                _buildActiveScreensStat(),
                _buildMediaLibraryStat(),
                _buildPlaylistStat(),
                _buildLicenseStatusCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- STAT CARD BUILDERS ---

  /// Documentation:
  /// Listens to the 'screens' subcollection to count paired screens.
  Widget _buildActiveScreensStat() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).collection('screens').snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _StatCard(
          title: "Active Screens",
          value: count.toString(),
          icon: Icons.tv_rounded,
          color: Colors.blueAccent,
        );
      },
    );
  }

  /// Documentation:
  /// Listens to the 'media' subcollection to count uploaded files.
  Widget _buildMediaLibraryStat() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).collection('media').snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _StatCard(
          title: "Media Library",
          value: count.toString(),
          icon: Icons.perm_media_rounded,
          color: Colors.purpleAccent,
        );
      },
    );
  }

  /// Documentation:
  /// Listens to the client document to count how many items are in their active playlist array.
  Widget _buildPlaylistStat() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (data.containsKey('playlist')) {
            count = (data['playlist'] as List).length;
          }
        }
        return _StatCard(
          title: "Items in Playlist",
          value: count.toString(),
          icon: Icons.featured_play_list_rounded,
          color: Colors.orangeAccent,
        );
      },
    );
  }

  /// Documentation:
  /// Displays the client's license expiration date from the Auth model.
  Widget _buildLicenseStatusCard() {
    String daysRemainingText = "Calculating...";
    Color statusColor = Colors.greenAccent;

    if (_currentUser?.licenseEndDate != null) {
      final difference = _currentUser!.licenseEndDate!.difference(DateTime.now()).inDays;
      if (difference < 0) {
        daysRemainingText = "Expired";
        statusColor = Colors.redAccent;
      } else if (difference <= 7) {
        daysRemainingText = "$difference Days (Expiring Soon)";
        statusColor = Colors.orangeAccent;
      } else {
        daysRemainingText = "$difference Days Remaining";
      }
    } else {
      daysRemainingText = "Lifetime License";
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassBackground,
        border: Border.all(color: AppColors.glassBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(Icons.verified_user_rounded, color: statusColor, size: 28),
              ),
              const SizedBox(width: 16),
              Text("License Status", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(daysRemainingText, style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          if (_currentUser?.isPaused == true) ...[
            const SizedBox(height: 8),
            Text("ACCOUNT PAUSED BY ADMIN", style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }
}

/// Documentation:
/// A beautiful, reusable Glassmorphism card for displaying statistics.
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassBackground,
        border: Border.all(color: AppColors.glassBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Text(title, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}