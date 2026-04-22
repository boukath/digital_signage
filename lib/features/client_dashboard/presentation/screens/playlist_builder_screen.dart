// File: lib/features/client_dashboard/presentation/screens/playlist_builder_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../domain/playlist_item.dart';
import '../widgets/live_preview_modal.dart';

class PlaylistBuilderScreen extends StatefulWidget {
  const PlaylistBuilderScreen({Key? key}) : super(key: key);

  @override
  State<PlaylistBuilderScreen> createState() => _PlaylistBuilderScreenState();
}

class _PlaylistBuilderScreenState extends State<PlaylistBuilderScreen> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentClientId;
  List<PlaylistItem> _currentPlaylist = [];
  bool _isSaving = false;

  // 👇 NEW: Variables for Multi-Playlist Support
  List<Map<String, dynamic>> _availablePlaylists = [];
  String _activePlaylistId = 'default_playlist';
  String _activePlaylistName = 'Default Playlist';

  @override
  void initState() {
    super.initState();
    _fetchClientIdAndPlaylists();
  }

  Future<void> _fetchClientIdAndPlaylists() async {
    final appUser = await _authService.userStateStream.first;
    if (mounted && appUser != null) {
      setState(() {
        _currentClientId = appUser.uid;
      });
      await _loadPlaylistsList();
    }
  }

  // 👇 NEW: Fetch all playlists this client has created
  Future<void> _loadPlaylistsList() async {
    if (_currentClientId == null) return;

    final snapshot = await _firestore
        .collection('clients')
        .doc(_currentClientId)
        .collection('playlists')
        .get();

    if (snapshot.docs.isEmpty) {
      // Create a default one if they have none
      await _createNewPlaylist('Default Playlist', id: 'default_playlist');
    } else {
      setState(() {
        _availablePlaylists = snapshot.docs.map((doc) => {
          'id': doc.id,
          'name': doc.data()['name'] ?? 'Unnamed Playlist'
        }).toList();

        // Select the first one automatically
        _activePlaylistId = _availablePlaylists.first['id'];
        _activePlaylistName = _availablePlaylists.first['name'];
      });
      _loadActivePlaylistItems();
    }
  }

  // 👇 NEW: Load the items for the currently selected playlist
  Future<void> _loadActivePlaylistItems() async {
    if (_currentClientId == null) return;

    final snapshot = await _firestore
        .collection('clients')
        .doc(_currentClientId)
        .collection('playlists')
        .doc(_activePlaylistId)
        .collection('items')
        .orderBy('orderIndex')
        .get();

    setState(() {
      _currentPlaylist = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // ensure ID is passed
        return PlaylistItem.fromMap(data);
      }).toList();
    });
  }

  // 👇 NEW: Create a brand new playlist
  Future<void> _createNewPlaylist(String name, {String? id}) async {
    final newId = id ?? 'playlist_${DateTime.now().millisecondsSinceEpoch}';

    await _firestore
        .collection('clients')
        .doc(_currentClientId)
        .collection('playlists')
        .doc(newId)
        .set({'name': name, 'createdAt': FieldValue.serverTimestamp()});

    await _loadPlaylistsList(); // Refresh the dropdown list

    setState(() {
      _activePlaylistId = newId;
      _activePlaylistName = name;
    });
    await _loadActivePlaylistItems(); // Will be empty!
  }

  // 👇 UPDATED: Save items into the specific playlist subcollection
  Future<void> _savePlaylist() async {
    if (_currentClientId == null) return;
    setState(() => _isSaving = true);

    final batch = _firestore.batch();
    final itemsRef = _firestore
        .collection('clients')
        .doc(_currentClientId)
        .collection('playlists')
        .doc(_activePlaylistId)
        .collection('items');

    // 1. Delete old items to ensure clean sync
    final oldDocs = await itemsRef.get();
    for (var doc in oldDocs.docs) {
      batch.delete(doc.reference);
    }

    // 2. Save new items with their proper Order Index!
    for (int i = 0; i < _currentPlaylist.length; i++) {
      final item = _currentPlaylist[i];
      final docRef = itemsRef.doc(item.id);

      final data = item.toMap();
      data['orderIndex'] = i; // 👈 Critical for Kiosk Player
      data['durationSeconds'] = item.durationInSeconds; // Ensure naming matches player

      batch.set(docRef, data);
    }

    await batch.commit();

    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Playlist '$_activePlaylistName' saved successfully!", style: GoogleFonts.poppins()), backgroundColor: Colors.green));
    }
  }

  void _showNewPlaylistDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.glassBackground,
            title: const Text("Create New Playlist", style: TextStyle(color: Colors.white)),
            content: TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "e.g., Weekend Promo", hintStyle: TextStyle(color: Colors.white54)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    _createNewPlaylist(nameController.text);
                    Navigator.pop(context);
                  }
                },
                child: const Text("Create"),
              )
            ],
          );
        }
    );
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  Future<void> _editSchedulePopup(int index) async {
    final item = _currentPlaylist[index];

    final TextEditingController durationController = TextEditingController(text: item.durationInSeconds.toString());
    TimeOfDay? tempStartTime = item.startTime != null ? TimeOfDay(hour: int.parse(item.startTime!.split(':')[0]), minute: int.parse(item.startTime!.split(':')[1])) : null;
    TimeOfDay? tempEndTime = item.endTime != null ? TimeOfDay(hour: int.parse(item.endTime!.split(':')[0]), minute: int.parse(item.endTime!.split(':')[1])) : null;
    List<int> tempDays = List.from(item.daysOfWeek);

    final Map<int, String> weekDays = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.glassBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.glassBorder)),
              title: Text("Advanced Scheduling", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.poppins(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Duration in Seconds",
                          labelStyle: GoogleFonts.poppins(color: Colors.white54),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.backgroundGradientStart)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("Play Window (Optional)", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                              onPressed: () async {
                                final time = await showTimePicker(context: context, initialTime: tempStartTime ?? const TimeOfDay(hour: 8, minute: 0));
                                if (time != null) setDialogState(() => tempStartTime = time);
                              },
                              child: Text(tempStartTime != null ? tempStartTime!.format(context) : "Start Time", style: GoogleFonts.poppins(color: Colors.white)),
                            ),
                          ),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("-", style: TextStyle(color: Colors.white))),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
                              onPressed: () async {
                                final time = await showTimePicker(context: context, initialTime: tempEndTime ?? const TimeOfDay(hour: 17, minute: 0));
                                if (time != null) setDialogState(() => tempEndTime = time);
                              },
                              child: Text(tempEndTime != null ? tempEndTime!.format(context) : "End Time", style: GoogleFonts.poppins(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      if (tempStartTime != null || tempEndTime != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setDialogState(() { tempStartTime = null; tempEndTime = null; }),
                            child: Text("Clear Times", style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12)),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text("Days of the Week", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text("If none selected, plays everyday.", style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: weekDays.entries.map((entry) {
                          final isSelected = tempDays.contains(entry.key);
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  tempDays.remove(entry.key);
                                } else {
                                  tempDays.add(entry.key);
                                }
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? AppColors.backgroundGradientStart : Colors.white12,
                                border: Border.all(color: isSelected ? AppColors.backgroundGradientEnd : Colors.white24),
                              ),
                              child: Center(
                                child: Text(entry.value, style: GoogleFonts.poppins(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final int? newDuration = int.tryParse(durationController.text);
                    if (newDuration != null && newDuration > 0) {
                      setState(() {
                        item.durationInSeconds = newDuration;
                        item.startTime = tempStartTime != null ? _formatTime(tempStartTime!) : null;
                        item.endTime = tempEndTime != null ? _formatTime(tempEndTime!) : null;
                        item.daysOfWeek = tempDays;
                      });
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.backgroundGradientStart, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: Text("Save Schedule", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _generateScheduleSubtitle(PlaylistItem item) {
    String sub = "${item.durationInSeconds}s";
    if (item.startTime != null && item.endTime != null) {
      sub += " • ${item.startTime} - ${item.endTime}";
    } else {
      sub += " • All Day";
    }
    if (item.daysOfWeek.isNotEmpty) {
      sub += " • ${item.daysOfWeek.length} Days/Wk";
    } else {
      sub += " • Everyday";
    }
    return sub;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Playlist Builder", style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),

              Row(
                children: [
                  // 👇 NEW: Dropdown to select which playlist to edit!
                  if (_availablePlaylists.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24)
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: Colors.grey[900],
                          value: _activePlaylistId,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                          items: _availablePlaylists.map((playlist) {
                            return DropdownMenuItem<String>(
                              value: playlist['id'],
                              child: Text(playlist['name']),
                            );
                          }).toList(),
                          onChanged: (String? newId) {
                            if (newId != null) {
                              setState(() {
                                _activePlaylistId = newId;
                                _activePlaylistName = _availablePlaylists.firstWhere((p) => p['id'] == newId)['name'];
                              });
                              _loadActivePlaylistItems();
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),

                  // 👇 NEW: Create New Playlist Button
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 32),
                    tooltip: "Create New Playlist",
                    onPressed: _showNewPlaylistDialog,
                  ),
                  const SizedBox(width: 24),

                  OutlinedButton.icon(
                    onPressed: _currentPlaylist.isEmpty ? null : () {
                      showDialog(context: context, builder: (_) => LivePreviewModal(playlist: _currentPlaylist));
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text("Live Preview", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 16),

                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePlaylist,
                    icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save_rounded),
                    label: Text(_isSaving ? "Saving..." : "Save Playlist", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.backgroundGradientStart,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.glassBackground, border: Border.all(color: AppColors.glassBorder), borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Media Pool", style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        Expanded(child: _buildMediaPool()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 1,
                  child: DragTarget<Map<String, dynamic>>(
                    onAcceptWithDetails: (details) {
                      setState(() {
                        _currentPlaylist.add(PlaylistItem(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          url: details.data['url'],
                          type: details.data['type'],
                          name: details.data['name'],
                          thumbnailUrl: details.data['thumbnailUrl'],
                        ));
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Container(
                        decoration: BoxDecoration(color: candidateData.isNotEmpty ? Colors.white.withOpacity(0.1) : AppColors.glassBackground, border: Border.all(color: candidateData.isNotEmpty ? AppColors.backgroundGradientStart : AppColors.glassBorder, width: candidateData.isNotEmpty ? 2 : 1), borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Active Playlist: $_activePlaylistName", style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            Expanded(child: _buildPlaylistView()),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPool() {
    if (_currentClientId == null) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('clients').doc(_currentClientId).collection('media').orderBy('uploadedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isVideo = data['type'] == 'video';
            final fileName = data['name'] ?? 'Unknown Media';
            final thumbUrl = data['thumbnailUrl'] ?? '';

            return Draggable<Map<String, dynamic>>(
              data: data,
              feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.7, child: _buildMediaCard(data['url'], isVideo, 120, thumbUrl, fileName))),
              childWhenDragging: Opacity(opacity: 0.3, child: _buildMediaCard(data['url'], isVideo, null, thumbUrl, fileName)),
              child: _buildMediaCard(data['url'], isVideo, null, thumbUrl, fileName),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistView() {
    if (_currentPlaylist.isEmpty) return Center(child: Text("Drop media here.", style: GoogleFonts.poppins(color: Colors.white54)));
    return ReorderableListView.builder(
      itemCount: _currentPlaylist.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (oldIndex < newIndex) newIndex -= 1;
          final item = _currentPlaylist.removeAt(oldIndex);
          _currentPlaylist.insert(newIndex, item);
        });
      },
      itemBuilder: (context, index) {
        final item = _currentPlaylist[index];
        final isVideo = item.type == 'video';
        final displayImageUrl = (isVideo && item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
            ? item.thumbnailUrl!
            : (!isVideo && item.url.isNotEmpty ? item.url : null);

        return Card(
          key: Key(item.id),
          color: Colors.white.withOpacity(0.05),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            onTap: () => _editSchedulePopup(index),
            leading: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                image: displayImageUrl != null ? DecorationImage(image: NetworkImage(displayImageUrl), fit: BoxFit.cover) : null,
              ),
              child: displayImageUrl == null ? Icon(isVideo ? Icons.play_circle : Icons.image, color: Colors.white) : null,
            ),
            title: Text(item.name ?? "Item ${index + 1}", style: GoogleFonts.poppins(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_generateScheduleSubtitle(item), style: GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w500)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => setState(() => _currentPlaylist.removeAt(index)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaCard(String url, bool isVideo, double? size, String? thumbUrl, String? fileName) {
    final displayUrl = (isVideo && thumbUrl != null && thumbUrl.isNotEmpty) ? thumbUrl : (!isVideo && url.isNotEmpty ? url : null);

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
          image: displayUrl != null ? DecorationImage(
              image: NetworkImage(displayUrl),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken)
          ) : null
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(isVideo ? Icons.play_circle_fill : Icons.image, color: Colors.white70, size: 32)),
          if (fileName != null)
            Positioned(
              bottom: 8, left: 8, right: 8,
              child: Text(
                fileName,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            )
        ],
      ),
    );
  }
}