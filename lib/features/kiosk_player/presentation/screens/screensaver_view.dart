import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ✅ Added Auth Import

import '../../../client_dashboard/domain/playlist_item.dart';
import '../../data/local_cache_service.dart';

class ScreensaverView extends StatefulWidget {
  final String clientId;
  final bool isPaused;

  const ScreensaverView({super.key, required this.clientId, required this.isPaused});

  @override
  State<ScreensaverView> createState() => _ScreensaverViewState();
}

class _ScreensaverViewState extends State<ScreensaverView> {
  final LocalCacheService _cacheService = LocalCacheService();
  StreamSubscription? _playlistSubscription;

  List<PlaylistItem> _activePlaylist = [];
  Map<String, String> _localMediaPaths = {};
  int _currentIndex = 0;
  bool _isLoading = true;
  String _currentPlaylistHash = "initial_hash";

  VideoPlayerController? _videoController;
  Timer? _imageTimer;

  @override
  void initState() {
    super.initState();
    print("🟡 [BOOT] ScreensaverView Initialized.");
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _listenToPlaylist();
    });
  }

  @override
  void didUpdateWidget(ScreensaverView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused && !oldWidget.isPaused) {
      _pauseMedia();
    } else if (!widget.isPaused && oldWidget.isPaused) {
      _resumeMedia();
    }
  }

  Future<void> _listenToPlaylist() async {
    // 🛡️ JUST-IN-TIME AUTHENTICATION SHIELD 🛡️
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        print("🟡 [AUTH] Kiosk is missing auth token! Signing in anonymously...");
        await FirebaseAuth.instance.signInAnonymously();
        print("🟢 [AUTH] Success! Kiosk UID: ${FirebaseAuth.instance.currentUser?.uid}");
      } else {
        print("🟢 [AUTH] Kiosk already authenticated.");
      }
    } catch (e) {
      print("❌ [AUTH] Fatal Error signing in: $e");
      return; // Abort listening if auth fails to protect the C++ thread
    }

    print("🟡 [DB] Listening to Client Document for Playlist Array...");

    // ✅ FIX: Listen to the DOCUMENT, not a non-existent subcollection!
    final docRef = FirebaseFirestore.instance
        .collection('clients')
        .doc(widget.clientId);

    _playlistSubscription = docRef.snapshots().listen((docSnapshot) async {
      if (!mounted) return;

      try {
        print("📡 [DB] Snapshot triggered!");

        if (!docSnapshot.exists || docSnapshot.data() == null) {
          print("⚠️ [DB] Client document missing! Waiting...");
          return;
        }

        final data = docSnapshot.data()!;

        // Extract the array from the document
        final List<dynamic> playlistArray = data['playlist'] ?? [];
        print("📡 [DB] Found playlist array with ${playlistArray.length} items.");

        List<PlaylistItem> rawItems = playlistArray
            .map((item) => PlaylistItem.fromMap(item as Map<String, dynamic>))
            .toList();

        // Prevent C++ thread contention if the playlist hasn't actually changed
        String newHash = rawItems.map((e) => '${e.url}_${e.durationInSeconds}').join('|');
        if (newHash == _currentPlaylistHash) return;

        print("✅ [DB] Successfully parsed new Playlist!");
        _currentPlaylistHash = newHash;

        await _processAndCachePlaylist(rawItems);

      } catch (e, stacktrace) {
        // ✅ AGGRESSIVE ERROR CATCHING: Print instead of crashing Windows
        print("❌ [DB] FATAL DATA MAPPING ERROR: $e");
        print(stacktrace);
      }
    }, onError: (error) {
      print("❌ [DB] Firestore Stream Error: $error");
    });
  }

  Future<void> _processAndCachePlaylist(List<PlaylistItem> allItems) async {
    print("🟡 [CACHE] Processing and validating day-parting...");
    final validItems = allItems.where((item) => _isItemScheduledNow(item)).toList();

    if (validItems.isEmpty) {
      if (mounted) {
        setState(() {
          _activePlaylist = [];
          _isLoading = false;
        });
      }
      return;
    }

    Map<String, String> newPaths = {};
    List<PlaylistItem> successfullyCachedItems = [];

    for (var item in validItems) {
      try {
        final localPath = await _cacheService.getCachedMediaPath(item.url);
        if (File(localPath).existsSync()) {
          newPaths[item.url] = localPath;
          successfullyCachedItems.add(item);
        }
      } catch (e) {
        print("❌ [CACHE] Failed to cache ${item.url}: $e");
      }
    }

    if (!mounted) return;

    setState(() {
      _activePlaylist = successfullyCachedItems;
      _localMediaPaths = newPaths;
      _isLoading = false;
      _currentIndex = 0;
    });

    _playCurrentMedia();
  }

  bool _isItemScheduledNow(PlaylistItem item) {
    final now = DateTime.now();
    if (item.daysOfWeek.isNotEmpty && !item.daysOfWeek.contains(now.weekday)) return false;

    if (item.startTime != null && item.endTime != null &&
        item.startTime!.isNotEmpty && item.endTime!.isNotEmpty) {
      try {
        final startParts = item.startTime!.split(':');
        final endParts = item.endTime!.split(':');

        final startHour = int.parse(startParts[0]);
        final startMin = int.parse(startParts[1]);
        final endHour = int.parse(endParts[0]);
        final endMin = int.parse(endParts[1]);

        final nowTimeDouble = now.hour + (now.minute / 60.0);
        final startTimeDouble = startHour + (startMin / 60.0);
        final endTimeDouble = endHour + (endMin / 60.0);

        if (nowTimeDouble < startTimeDouble || nowTimeDouble > endTimeDouble) return false;
      } catch (e) {
        print("⚠️ [TIME] Error parsing Day-Parting time: $e");
      }
    }
    return true;
  }

  Future<void> _playCurrentMedia() async {
    print("🟡 [PLAY-1] Starting playback cycle for index: $_currentIndex");
    _disposeCurrentMedia();

    if (_activePlaylist.isEmpty || widget.isPaused || !mounted) return;

    final currentItem = _activePlaylist[_currentIndex];
    final localPath = _localMediaPaths[currentItem.url];

    if (localPath == null) {
      Future.delayed(const Duration(seconds: 1), _nextMedia);
      return;
    }

    File mediaFile = File(localPath);
    if (!mediaFile.existsSync() || mediaFile.lengthSync() < 1024) {
      print("❌ [PLAY-4] File missing or corrupted zero-byte file! Skipping.");
      if (mediaFile.existsSync()) mediaFile.deleteSync();
      Future.delayed(const Duration(seconds: 1), _nextMedia);
      return;
    }

    bool isVideo = currentItem.type == 'video' ||
        currentItem.url.toLowerCase().endsWith('.mp4') ||
        currentItem.url.toLowerCase().endsWith('.mov') ||
        currentItem.url.toLowerCase().endsWith('.avi');

    if (isVideo) {
      print("🟡 [PLAY-6] Instantiating VideoPlayerController...");
      final controller = VideoPlayerController.file(mediaFile);
      _videoController = controller;

      setState(() {}); // Trigger loading spinner on UI

      try {
        await controller.initialize();
        if (!mounted || _videoController != controller) {
          controller.dispose();
          return;
        }

        if (!widget.isPaused) {
          controller.play();
        }

        controller.addListener(_videoListener);
        setState(() {}); // Remove spinner, show video
      } catch (e) {
        print("❌ [PLAY-ERROR] Video Initialize Exception: $e");
        Future.delayed(const Duration(seconds: 2), _nextMedia);
      }
    } else {
      print("🖼️ [PLAY-IMG] Showing Image.");
      setState(() {});
      int duration = currentItem.durationInSeconds > 0 ? currentItem.durationInSeconds : 5;
      _imageTimer = Timer(Duration(seconds: duration), _nextMedia);
    }
  }

  void _videoListener() {
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        _videoController!.value.position >= _videoController!.value.duration &&
        !_videoController!.value.isPlaying) {

      _videoController!.removeListener(_videoListener);
      _nextMedia();
    }
  }

  void _nextMedia() {
    if (!mounted) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _activePlaylist.length;
    });
    _playCurrentMedia();
  }

  void _pauseMedia() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.pause();
    }
    _imageTimer?.cancel();
  }

  void _resumeMedia() {
    if (_activePlaylist.isEmpty) return;

    final currentItem = _activePlaylist[_currentIndex];
    bool isVideo = currentItem.type == 'video' || currentItem.url.toLowerCase().endsWith('.mp4');

    if (isVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController!.play();
      }
    } else {
      int duration = currentItem.durationInSeconds > 0 ? currentItem.durationInSeconds : 5;
      _imageTimer = Timer(Duration(seconds: duration), _nextMedia);
    }
  }

  void _disposeCurrentMedia() {
    _imageTimer?.cancel();
    if (_videoController != null) {
      final oldController = _videoController!;
      _videoController = null;
      oldController.removeListener(_videoListener);

      Future.delayed(const Duration(seconds: 1), () {
        try {
          oldController.dispose();
        } catch(e) {}
      });
    }
  }

  @override
  void dispose() {
    _playlistSubscription?.cancel();
    _disposeCurrentMedia();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_activePlaylist.isEmpty) {
      return const Center(
        child: Text(
          "No content scheduled for right now.",
          style: TextStyle(color: Colors.white54, fontSize: 24),
        ),
      );
    }

    final currentItem = _activePlaylist[_currentIndex];
    final localPath = _localMediaPaths[currentItem.url];

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: _buildMediaWidget(currentItem, localPath),
      ),
    );
  }

  Widget _buildMediaWidget(PlaylistItem item, String? localPath) {
    if (localPath == null) return const SizedBox.shrink();

    bool isVideo = item.type == 'video' ||
        item.url.toLowerCase().endsWith('.mp4') ||
        item.url.toLowerCase().endsWith('.mov') ||
        item.url.toLowerCase().endsWith('.avi');

    if (isVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        );
      } else {
        return const SizedBox(
          width: 1920,
          height: 1080,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      }
    } else {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox(
            width: 1920, height: 1080,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 100)),
          );
        },
      );
    }
  }
}