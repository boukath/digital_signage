// File: lib/features/client_dashboard/presentation/screens/client_dashboard.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';

// Import all 6 screens
import 'overview_screen.dart';
import 'media_manager_screen.dart';
import 'playlist_builder_screen.dart';
import 'catalog_builder_screen.dart';
import 'analytics_screen.dart'; // NEW: Analytics Screen imported
import 'screen_assignment_screen.dart';

/// Documentation:
/// This is the main shell for Level 2 (The Client Dashboard).
/// It uses a NavigationRail to switch between the different tools the client needs,
/// styled with our 2026 Glassmorphism theme.
class ClientDashboard extends StatefulWidget {
  const ClientDashboard({Key? key}) : super(key: key);

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();

  // Exactly 6 Pages in the correct order
  late final List<Widget> _pages = [
    const OverviewScreen(),           // Index 0
    const MediaManagerScreen(),       // Index 1
    const PlaylistBuilderScreen(),    // Index 2 (Screensaver)
    const CatalogBuilderScreen(),     // Index 3 (Catalog)
    const AnalyticsScreen(),          // Index 4 (Analytics)
    const ScreenAssignmentScreen(),   // Index 5 (Screens)
  ];

  @override
  Widget build(BuildContext context) {
    // Safety check: If for any reason the index goes out of bounds, reset it to 0
    if (_selectedIndex >= _pages.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      // We wrap the entire body in our vibrant gradient
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
              // 1. Custom Glass Top Bar (Matching the Super Admin Panel)
              _buildTopBar(),

              // 2. Main Area: Side Navigation + Tab Content
              Expanded(
                child: Row(
                  children: [
                    _buildSideMenu(),

                    // The Main Content Area for the selected tab
                    Expanded(
                      child: _pages[_selectedIndex],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Documentation:
  /// A beautiful custom top bar matching the Super Admin dashboard design.
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: AppColors.glassBackground,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Client Portal",
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Log Out',
            onPressed: () => _authService.signOut(),
          ),
        ],
      ),
    );
  }

  /// Documentation:
  /// The Glassmorphism side navigation menu.
  Widget _buildSideMenu() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.glassBackground,
        border: Border(right: BorderSide(color: AppColors.glassBorder, width: 1)),
      ),
      child: NavigationRail(
        // We set the rail itself to transparent so the glass container shows through
        backgroundColor: Colors.transparent,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        // Updated colors to pop against the purple/magenta gradient
        selectedIconTheme: const IconThemeData(color: Colors.white, size: 32),
        unselectedIconTheme: const IconThemeData(color: Colors.white54, size: 28),
        selectedLabelTextStyle: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        unselectedLabelTextStyle: GoogleFonts.poppins(color: Colors.white54),
        labelType: NavigationRailLabelType.all,

        // Exactly 6 Destinations (Matching the _pages list perfectly)
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: Text('Overview'), // Index 0
          ),
          NavigationRailDestination(
            icon: Icon(Icons.perm_media_outlined),
            selectedIcon: Icon(Icons.perm_media),
            label: Text('Media'), // Index 1
          ),
          NavigationRailDestination(
            icon: Icon(Icons.featured_play_list_outlined),
            selectedIcon: Icon(Icons.featured_play_list),
            label: Text('Screensaver'), // Index 2
          ),
          NavigationRailDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: Text('Catalog'), // Index 3
          ),
          NavigationRailDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: Text('Analytics'), // Index 4 (NEW)
          ),
          NavigationRailDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv),
            label: Text('Screens'), // Index 5
          ),
        ],
      ),
    );
  }
}