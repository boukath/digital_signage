// File: lib/features/client_dashboard/presentation/screens/screen_assignment_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';

class ScreenAssignmentScreen extends StatefulWidget {
  const ScreenAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<ScreenAssignmentScreen> createState() => _ScreenAssignmentScreenState();
}

class _ScreenAssignmentScreenState extends State<ScreenAssignmentScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentClientId;
  final TextEditingController _pinController = TextEditingController();
  bool _isPairing = false;

  @override
  void initState() {
    super.initState();
    _fetchClientId();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
  /// Verifies the 6-digit PIN against the 'pairing_codes' collection.
  /// If valid, assigns the screen to the client and marks it as paired.
  Future<void> _pairScreen() async {
    final pin = _pinController.text.trim();

    if (pin.length != 6) {
      _showSnackBar("Please enter a valid 6-digit PIN.", Colors.redAccent);
      return;
    }

    if (_currentClientId == null) return;

    setState(() => _isPairing = true);

    try {
      // 1. Look for a matching pending code
      final query = await _firestore
          .collection('pairing_codes')
          .where('pin', isEqualTo: pin)
          .where('status', isEqualTo: 'pending')
          .get();

      if (query.docs.isEmpty) {
        _showSnackBar("Invalid or expired PIN. Please check the TV screen.", Colors.redAccent);
        setState(() => _isPairing = false);
        return;
      }

      final pairingDoc = query.docs.first;
      final screenId = pairingDoc.id; // The hardware ID of the Kiosk

      // 2. Add this screen to the client's personal screens collection
      await _firestore
          .collection('clients')
          .doc(_currentClientId)
          .collection('screens')
          .doc(screenId)
          .set({
        'name': 'Screen ${screenId.substring(0, 4)}', // Default name
        'pairedAt': FieldValue.serverTimestamp(),
        'status': 'online',
        'pendingCommand': null, // Initialize with no pending commands
      });

      // 3. Mark the code as paired so the Kiosk knows it was successful
      await pairingDoc.reference.update({
        'status': 'paired',
        'clientId': _currentClientId,
      });

      _pinController.clear();
      _showSnackBar("Screen paired successfully!", Colors.green);

    } catch (e) {
      _showSnackBar("Error pairing screen: $e", Colors.redAccent);
    }

    setState(() => _isPairing = false);
  }

  /// Documentation:
  /// Sends a remote command directly to the specific hardware kiosk via Firestore.
  Future<void> _sendCommandToHardware(String screenId, String command, String friendlyName) async {
    if (_currentClientId == null) return;

    try {
      await _firestore
          .collection('clients')
          .doc(_currentClientId)
          .collection('screens')
          .doc(screenId)
          .update({
        'pendingCommand': command,
        'commandSentAt': FieldValue.serverTimestamp(),
      });

      _showSnackBar("$friendlyName command sent to screen.", Colors.green);
    } catch (e) {
      _showSnackBar("Error sending command: $e", Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Screen Assignment",
            style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              children: [
                // LEFT PANEL: Active Screens List
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassBackground,
                      border: Border.all(color: AppColors.glassBorder),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Active Screens", style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Expanded(child: _buildActiveScreensList()),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 24),

                // RIGHT PANEL: PIN Entry Card
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassBackground,
                      border: Border.all(color: AppColors.glassBorder),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tv_rounded, size: 64, color: AppColors.backgroundGradientStart),
                        const SizedBox(height: 16),
                        Text(
                          "Pair New Screen",
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Enter the 6-digit PIN displayed on your physical screen.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
                        ),
                        const SizedBox(height: 32),

                        // Beautiful PIN Input Field
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            counterText: "", // Hides the '0/6' counter
                            filled: true,
                            fillColor: Colors.black26,
                            hintText: "000000",
                            hintStyle: GoogleFonts.poppins(color: Colors.white24, letterSpacing: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.backgroundGradientStart, width: 2)),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Pair Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isPairing ? null : _pairScreen,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.backgroundGradientStart,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isPairing
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text("Verify & Pair", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScreensList() {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).collection('screens').orderBy('pairedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final screens = snapshot.data!.docs;

        if (screens.isEmpty) {
          return Center(
            child: Text("No screens paired yet.", style: GoogleFonts.poppins(color: Colors.white54)),
          );
        }

        return ListView.builder(
          itemCount: screens.length,
          itemBuilder: (context, index) {
            final screenData = screens[index].data() as Map<String, dynamic>;
            final isOnline = screenData['status'] == 'online';
            final screenId = screens[index].id;

            return Card(
              color: Colors.white.withOpacity(0.05),
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.connected_tv, color: isOnline ? Colors.greenAccent : Colors.redAccent),
                ),
                title: Text(screenData['name'] ?? 'Unknown Screen', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  screenData['pendingCommand'] != null
                      ? "Status: Executing command..."
                      : "ID: $screenId",
                  style: GoogleFonts.poppins(
                      color: screenData['pendingCommand'] != null ? Colors.orangeAccent : Colors.white54,
                      fontSize: 12
                  ),
                ),
                // NEW: Replaced standard IconButton with an interactive Dropdown Menu
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF2C2C4E), // A dark elegant color for the menu background
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onSelected: (value) {
                    if (value == 'force_sync') _sendCommandToHardware(screenId, 'force_sync', 'Force Sync');
                    if (value == 'clear_cache') _sendCommandToHardware(screenId, 'clear_cache', 'Clear Cache');
                    if (value == 'reboot') _sendCommandToHardware(screenId, 'reboot', 'Reboot');
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'force_sync',
                      child: Row(
                        children: [
                          const Icon(Icons.sync, color: Colors.white70, size: 20),
                          const SizedBox(width: 12),
                          Text('Force Sync Playlist', style: GoogleFonts.poppins(color: Colors.white)),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'clear_cache',
                      child: Row(
                        children: [
                          const Icon(Icons.cleaning_services, color: Colors.white70, size: 20),
                          const SizedBox(width: 12),
                          Text('Clear Media Cache', style: GoogleFonts.poppins(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem<String>(
                      value: 'reboot',
                      child: Row(
                        children: [
                          const Icon(Icons.restart_alt, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 12),
                          Text('Reboot Kiosk', style: GoogleFonts.poppins(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
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