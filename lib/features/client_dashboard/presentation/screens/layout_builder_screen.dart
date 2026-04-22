// File: lib/features/client_dashboard/presentation/screens/layout_builder_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/layout_model.dart';
import '../../data/layout_service.dart';
import '../../../../features/auth/data/auth_service.dart';

class LayoutBuilderScreen extends StatefulWidget {
  const LayoutBuilderScreen({Key? key}) : super(key: key);

  @override
  State<LayoutBuilderScreen> createState() => _LayoutBuilderScreenState();
}

class _LayoutBuilderScreenState extends State<LayoutBuilderScreen> {
  bool isLandscape = true;
  List<ZoneModel> zones = [];

  final LayoutService _layoutService = LayoutService();
  final AuthService _authService = AuthService();
  bool _isSaving = false;

  List<Map<String, dynamic>> _clientPlaylists = [];
  // 👇 NEW: List to hold all their uploaded videos and photos!
  List<Map<String, dynamic>> _clientMedia = [];
  String? _currentClientId;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // Fetch BOTH Playlists and Raw Media
  Future<void> _fetchData() async {
    final user = await _authService.userStateStream.first;
    if (user != null) {
      _currentClientId = user.uid;

      // 1. Fetch Playlists
      final playlistSnapshot = await FirebaseFirestore.instance
          .collection('clients')
          .doc(_currentClientId)
          .collection('playlists')
          .get();

      // 2. Fetch Media Pool (Videos & Photos)
      final mediaSnapshot = await FirebaseFirestore.instance
          .collection('clients')
          .doc(_currentClientId)
          .collection('media')
          .orderBy('uploadedAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _clientPlaylists = playlistSnapshot.docs.map((doc) => {
            'id': doc.id,
            'name': doc.data()['name'] ?? 'Unnamed Playlist'
          }).toList();

          _clientMedia = mediaSnapshot.docs.map((doc) => doc.data()).toList();
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPlaylistItems(String playlistId) async {
    if (_currentClientId == null) return [];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('clients')
          .doc(_currentClientId)
          .collection('playlists')
          .doc(playlistId)
          .collection('items')
          .orderBy('orderIndex')
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      return [];
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  void _addNewZone() {
    setState(() {
      Color randomColor = Colors.primaries[zones.length % Colors.primaries.length].withOpacity(0.8);
      zones.add(
        ZoneModel(
          id: 'zone_${zones.length + 1}',
          x: 50,
          y: 50,
          width: 200,
          height: 150,
          colorHex: _colorToHex(randomColor),
          zoneType: 'playlist',
        ),
      );
    });
  }

  void _openZoneSettings(ZoneModel zone) {
    // Determine what is currently selected to highlight it in the UI
    String? tempSelectedPlaylistId = zone.zoneType == 'playlist' ? zone.contentId : null;
    String? tempSelectedMediaUrl = zone.zoneType == 'single_media' ? zone.contentId : null;

    if (_clientPlaylists.isNotEmpty && zone.zoneType == 'playlist' && (tempSelectedPlaylistId == null || !_clientPlaylists.any((p) => p['id'] == tempSelectedPlaylistId))) {
      tempSelectedPlaylistId = _clientPlaylists.first['id'];
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text('Configure Box: ${zone.id}', style: const TextStyle(color: Colors.white)),
                content: SizedBox(
                  width: 450,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ==========================================
                        // OPTION 1: ASSIGN A PLAYLIST
                        // ==========================================
                        const Text("Option 1: Assign a Playlist (Multiple Looping Files)", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),

                        if (_clientPlaylists.isEmpty)
                          const Text("No playlists found. Go to 'Screensaver' to create one!", style: TextStyle(color: Colors.redAccent))
                        else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(8),
                              // Highlight if this option is currently selected
                              border: tempSelectedPlaylistId != null ? Border.all(color: Colors.blueAccent, width: 2) : null,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                dropdownColor: Colors.black87,
                                value: tempSelectedPlaylistId,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                                isExpanded: true,
                                items: _clientPlaylists.map((playlist) {
                                  return DropdownMenuItem<String>(
                                    value: playlist['id'],
                                    child: Text(playlist['name']),
                                  );
                                }).toList(),
                                onChanged: (newId) {
                                  setDialogState(() {
                                    tempSelectedPlaylistId = newId;
                                    tempSelectedMediaUrl = null; // Clear single media selection
                                  });
                                },
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),
                        const Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white24)),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("OR", style: TextStyle(color: Colors.white54))),
                            Expanded(child: Divider(color: Colors.white24)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ==========================================
                        // OPTION 2: ASSIGN A SINGLE MEDIA FILE
                        // ==========================================
                        const Text("Option 2: Assign a Single Video or Image", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),

                        if (_clientMedia.isEmpty)
                          const Text("No media uploaded. Go to 'Media' to upload files!", style: TextStyle(color: Colors.redAccent))
                        else
                          Container(
                            height: 120, // Height for the media picker grid
                            width: double.infinity,
                            decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12)
                            ),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _clientMedia.length,
                              padding: const EdgeInsets.all(8),
                              itemBuilder: (context, index) {
                                final media = _clientMedia[index];
                                final isVideo = media['type'] == 'video';
                                final url = media['url'];
                                final isSelected = tempSelectedMediaUrl == url;

                                final displayUrl = (isVideo && media['thumbnailUrl'] != null && media['thumbnailUrl'].isNotEmpty)
                                    ? media['thumbnailUrl']
                                    : (!isVideo && url != null ? url : null);

                                return GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      tempSelectedMediaUrl = url;
                                      tempSelectedPlaylistId = null; // Clear playlist selection
                                    });
                                  },
                                  child: Container(
                                    width: 100,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(8),
                                      // Highlight blue if tapped!
                                      border: isSelected ? Border.all(color: Colors.blueAccent, width: 3) : Border.all(color: Colors.transparent),
                                      image: displayUrl != null
                                          ? DecorationImage(
                                          image: NetworkImage(displayUrl),
                                          fit: BoxFit.cover,
                                          colorFilter: isVideo ? ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken) : null
                                      )
                                          : null,
                                    ),
                                    child: displayUrl == null
                                        ? Icon(isVideo ? Icons.play_circle : Icons.image, color: Colors.white54)
                                        : (isVideo ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28)) : null),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel", style: TextStyle(color: Colors.white54))
                  ),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      onPressed: () {
                        // Apply whichever one was selected back to the actual Zone!
                        setState(() {
                          if (tempSelectedPlaylistId != null) {
                            zone.zoneType = 'playlist';
                            zone.contentId = tempSelectedPlaylistId;
                          } else if (tempSelectedMediaUrl != null) {
                            // We use 'single_media' to tell the Kiosk this is a direct file link
                            zone.zoneType = 'single_media';
                            zone.contentId = tempSelectedMediaUrl;
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: const Text("Save Box Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ),
                ],
              );
            }
        );
      },
    );
  }

  Future<void> _saveCurrentLayout() async {
    setState(() => _isSaving = true);
    final layout = LayoutModel(
      layoutId: 'layout_001',
      name: isLandscape ? 'Horizontal Promo Layout' : 'Vertical Menu Layout',
      isLandscape: isLandscape,
      zones: zones,
    );

    try {
      await _layoutService.saveLayout(layout);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Layout Saved to Cloud Successfully!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Error saving layout: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Layout Builder', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E2C),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            icon: Icon(isLandscape ? Icons.stay_current_landscape : Icons.stay_current_portrait, color: Colors.blueAccent),
            label: Text(isLandscape ? 'Vertical Canvas' : 'Horizontal Canvas', style: const TextStyle(color: Colors.blueAccent)),
            onPressed: () => setState(() { isLandscape = !isLandscape; zones.clear(); }),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_box),
            label: const Text('Add Zone'),
            onPressed: _addNewZone,
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload, color: Colors.white),
            label: Text(_isSaving ? 'Saving...' : 'Save & Publish', style: const TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: _isSaving ? null : _saveCurrentLayout,
          ),
          const SizedBox(width: 20),
        ],
      ),
      backgroundColor: Colors.grey[900],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: AspectRatio(
            aspectRatio: isLandscape ? 16 / 9 : 9 / 16,
            child: Container(
              color: Colors.black,
              child: Stack(
                children: zones.map((zone) {

                  // Text to show what is assigned to the box
                  String assignedName = "No Content Assigned";
                  if (zone.zoneType == 'playlist' && zone.contentId != null) {
                    try {
                      assignedName = "Playlist:\n" + _clientPlaylists.firstWhere((p) => p['id'] == zone.contentId)['name'];
                    } catch(e) {
                      assignedName = "Unknown Playlist";
                    }
                  } else if (zone.zoneType == 'single_media') {
                    assignedName = "Single Media File";
                  }

                  return Positioned(
                    left: zone.x,
                    top: zone.y,
                    width: zone.width,
                    height: zone.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onPanUpdate: (details) => setState(() { zone.x += details.delta.dx; zone.y += details.delta.dy; }),
                          child: Container(
                            decoration: BoxDecoration(
                                color: _hexToColor(zone.colorHex),
                                border: Border.all(color: Colors.white, width: 2)
                            ),
                            child: Center(
                              child: Text(
                                'Zone: ${zone.id}\n$assignedName',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: Material(
                            color: Colors.black54, shape: const CircleBorder(),
                            child: IconButton(icon: const Icon(Icons.settings, color: Colors.white, size: 20), onPressed: () => _openZoneSettings(zone), tooltip: 'Configure Box'),
                          ),
                        ),
                        Positioned(
                          right: -10, bottom: -10,
                          child: GestureDetector(
                            onPanUpdate: (details) => setState(() {
                              zone.width = (zone.width + details.delta.dx).clamp(50.0, double.infinity);
                              zone.height = (zone.height + details.delta.dy).clamp(50.0, double.infinity);
                            }),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeDownRight,
                              child: Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}