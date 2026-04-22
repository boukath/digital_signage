// File: lib/features/kiosk_player/presentation/widgets/media_zone_player.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../client_dashboard/domain/playlist_item.dart';
import '../../data/local_cache_service.dart';

class MediaZonePlayer extends StatefulWidget {
  final String clientId;
  final String zoneId;
  final String assignedPlaylistId; // 👈 NEW: Accepts the specific playlist ID!

  const MediaZonePlayer({
    Key? key,
    required this.clientId,
    required this.zoneId,
    this.assignedPlaylistId = 'default_playlist', // Fallback just in case
  }) : super(key: key);

  @override
  State<MediaZonePlayer> createState() => _MediaZonePlayerState();
}

class _MediaZonePlayerState extends State<MediaZonePlayer> {
  final LocalCacheService _cacheService = LocalCacheService();

  List<PlaylistItem> _playlist = [];
  Map<String, String> _localMediaPaths = {};

  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  Timer? _imageTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAndCachePlaylist();
  }

  Future<void> _fetchAndCachePlaylist() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('playlists')
      // 👇 NEW: Now uses the dynamic playlist assigned from the Layout Builder!
          .doc(widget.assignedPlaylistId)
          .collection('items')
          .orderBy('orderIndex')
          .get();

      if (snapshot.docs.isNotEmpty) {
        List<PlaylistItem> fetchedItems = snapshot.docs.map<PlaylistItem>((doc) {
          final data = doc.data();
          return PlaylistItem(
            id: doc.id,
            url: data['url'] ?? '',
            type: data['type'] ?? 'image',
            durationInSeconds: data['durationSeconds'] ?? 10,
          );
        }).toList();

        Map<String, String> newPaths = {};
        for (var item in fetchedItems) {
          try {
            final localPath = await _cacheService.getCachedMediaPath(item.url);
            newPaths[item.url] = localPath;
          } catch (e) {
            debugPrint("❌ [ZONE CACHE] Failed to cache ${item.url}: $e");
          }
        }

        if (mounted) {
          setState(() {
            _playlist = fetchedItems;
            _localMediaPaths = newPaths;
            _isLoading = false;
          });
          _playCurrentItem();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching playlist for Zone ${widget.zoneId}: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _playCurrentItem() async {
    if (_playlist.isEmpty || !mounted) return;

    _imageTimer?.cancel();
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }

    final currentItem = _playlist[_currentIndex];
    final localPath = _localMediaPaths[currentItem.url];

    if (localPath == null || !File(localPath).existsSync()) {
      _imageTimer = Timer(const Duration(seconds: 1), _moveToNextItem);
      return;
    }

    final File mediaFile = File(localPath);

    if (currentItem.type == 'video') {
      _videoController = VideoPlayerController.file(mediaFile);

      try {
        await _videoController!.initialize();
        if (!mounted) return;

        _videoController!.setVolume(0.0);
        _videoController!.play();

        _videoController!.addListener(() {
          if (_videoController!.value.isInitialized &&
              _videoController!.value.position >= _videoController!.value.duration &&
              !_videoController!.value.isPlaying) {
            _moveToNextItem();
          }
        });

        setState(() {});
      } catch (e) {
        debugPrint("❌ [ZONE PLAY] Video Error: $e");
        _moveToNextItem();
      }
    }
    else {
      setState(() {});

      _imageTimer = Timer(Duration(seconds: currentItem.durationInSeconds), () {
        _moveToNextItem();
      });
    }
  }

  void _moveToNextItem() {
    if (!mounted) return;
    _currentIndex++;
    if (_currentIndex >= _playlist.length) {
      _currentIndex = 0;
    }
    _playCurrentItem();
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_playlist.isEmpty) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.playlist_remove, color: Colors.white54, size: 40),
        ),
      );
    }

    final currentItem = _playlist[_currentIndex];
    final localPath = _localMediaPaths[currentItem.url];

    if (localPath == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(seconds: 1),
      child: currentItem.type == 'video' && _videoController != null && _videoController!.value.isInitialized
          ? SizedBox.expand(
        key: ValueKey('${currentItem.id}_video'),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      )
          : SizedBox.expand(
        key: ValueKey('${currentItem.id}_image'),
        child: Image.file(
          File(localPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: 40),
          ),
        ),
      ),
    );
  }
}