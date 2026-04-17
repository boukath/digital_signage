// File: lib/features/client_dashboard/presentation/widgets/live_preview_modal.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/playlist_item.dart';

class LivePreviewModal extends StatefulWidget {
  final List<PlaylistItem> playlist;

  const LivePreviewModal({Key? key, required this.playlist}) : super(key: key);

  @override
  State<LivePreviewModal> createState() => _LivePreviewModalState();
}

class _LivePreviewModalState extends State<LivePreviewModal> {
  int _currentIndex = 0;
  Timer? _playbackTimer;
  VideoPlayerController? _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.playlist.isNotEmpty) {
      _playCurrentItem();
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  /// Documentation:
  /// Handles the logic for playing the current item in the array.
  /// Sets up a timer to auto-advance based on the user's custom duration.
  Future<void> _playCurrentItem() async {
    // 1. Clean up any existing video controller
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }

    setState(() => _isPlaying = false);

    final currentItem = widget.playlist[_currentIndex];

    // 2. Setup Video if needed
    if (currentItem.type == 'video' && currentItem.url.isNotEmpty) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(currentItem.url));
      await _videoController!.initialize();
      _videoController!.setLooping(true); // Loop if duration > video length
      _videoController!.play();
    }

    setState(() => _isPlaying = true);

    // 3. Start the duration countdown
    _playbackTimer = Timer(Duration(seconds: currentItem.durationInSeconds), () {
      _moveToNextItem();
    });
  }

  /// Documentation:
  /// Advances to the next item, or loops back to the start.
  void _moveToNextItem() {
    if (!mounted) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.playlist.length;
    });
    _playCurrentItem();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) return const SizedBox.shrink();

    final currentItem = widget.playlist[_currentIndex];

    return Dialog.fullscreen(
      backgroundColor: Colors.black.withOpacity(0.95), // Deep immersive background
      child: Stack(
        children: [
          // 1. The Main Media Display Area
          Center(
            child: !_isPlaying
                ? const CircularProgressIndicator(color: AppColors.backgroundGradientStart)
                : currentItem.type == 'video' && _videoController != null && _videoController!.value.isInitialized
                ? AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            )
                : Image.network(
              currentItem.url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const CircularProgressIndicator(color: AppColors.backgroundGradientStart);
              },
            ),
          ),

          // 2. Glassmorphism Status Overlay (Top Left)
          Positioned(
            top: 32,
            left: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.glassBackground,
                border: Border.all(color: AppColors.glassBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.live_tv_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Text("LIVE PREVIEW", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("Playing Item ${_currentIndex + 1} of ${widget.playlist.length}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                  Text("Duration: ${currentItem.durationInSeconds}s", style: GoogleFonts.poppins(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),

          // 3. Close Button (Top Right)
          Positioned(
            top: 32,
            right: 32,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 36),
              onPressed: () => Navigator.pop(context),
              tooltip: "Close Simulator",
            ),
          ),

          // 4. Progress Bar at the absolute bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              // Just a continuous loading bar to show the system is active
              backgroundColor: Colors.transparent,
              color: AppColors.backgroundGradientStart,
            ),
          )
        ],
      ),
    );
  }
}