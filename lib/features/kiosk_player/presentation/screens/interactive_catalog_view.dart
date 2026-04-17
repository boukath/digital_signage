import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math; // 👈 NEW: For 3D floating math calculations
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/local_cache_service.dart';
import '../../../client_dashboard/domain/catalog_item.dart';

class InteractiveCatalogView extends StatefulWidget {
  final String clientId;

  const InteractiveCatalogView({Key? key, required this.clientId}) : super(key: key);

  @override
  State<InteractiveCatalogView> createState() => _InteractiveCatalogViewState();
}

class _InteractiveCatalogViewState extends State<InteractiveCatalogView> with TickerProviderStateMixin {
  final LocalCacheService _cacheService = LocalCacheService();

  // State variables for navigation
  String? _selectedCategory;
  int _currentItemIndex = 0;

  // Media & UI State
  String? _localMediaPath;
  VideoPlayerController? _videoController;
  PageController? _pageController;

  // Idle Timer for Premium UI fade
  Timer? _idleTimer;
  bool _showUI = true;

  // 👈 NEW: Animation Controller for the 3D Image Float
  AnimationController? _imageAnimationController;

  @override
  void initState() {
    super.initState();
    _startIdleTimer();

    // Initialize the buttery 12-second repeating loop for images
    _imageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _imageAnimationController?.dispose(); // 👈 Clean up
    _videoController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  // --- INTERACTION & IDLE LOGIC ---

  void _userInteracted() {
    setState(() => _showUI = true);
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _selectedCategory != null) {
        setState(() => _showUI = false);
      }
    });
  }

  // --- ANALYTICS & CACHING ---

  Future<void> _fireAnalyticsEvent(String itemId, String eventType) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('clients').doc(widget.clientId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> catalog = data['catalog'] ?? [];

      int index = catalog.indexWhere((item) => item['id'] == itemId);
      if (index != -1) {
        if (eventType == 'view') {
          catalog[index]['viewCount'] = (catalog[index]['viewCount'] ?? 0) + 1;
        } else if (eventType == 'qr_scan') {
          catalog[index]['qrScanCount'] = (catalog[index]['qrScanCount'] ?? 0) + 1;
        }
        await docRef.update({'catalog': catalog});
      }
    } catch (e) {
      debugPrint('Analytics Ping Failed: $e');
    }
  }

  Future<void> _resolveMediaPath(CatalogItem item) async {
    setState(() => _localMediaPath = null);
    if (item.mediaUrl.isEmpty) return;

    try {
      String localPath = await _cacheService.getCachedMediaPath(item.mediaUrl);
      if (mounted) {
        setState(() => _localMediaPath = 'file://$localPath');
        if (item.mediaType == 'video' || localPath.toLowerCase().endsWith('.mp4')) {
          await _initializeVideo('file://$localPath');
        } else {
          _disposeVideo();
        }
      }
    } catch (e) {
      debugPrint("Falling back to network URL: $e");
      if (mounted) setState(() => _localMediaPath = item.mediaUrl);
    }
  }

  Future<void> _initializeVideo(String localPath) async {
    _disposeVideo();
    final file = File(localPath.replaceAll('file://', ''));
    _videoController = VideoPlayerController.file(file);
    await _videoController!.initialize();
    _videoController!.setLooping(true);
    _videoController!.setVolume(0.0); // Starts muted
    _videoController!.play();
    if (mounted) setState(() {});
  }

  void _disposeVideo() {
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }
  }

  // --- NAVIGATION HANDLERS ---

  void _openCategory(String category, List<CatalogItem> categoryItems) {
    setState(() {
      _selectedCategory = category;
      _currentItemIndex = 0;
      _pageController = PageController(initialPage: 0);
    });
    _userInteracted();
    if (categoryItems.isNotEmpty) {
      _onItemChanged(0, categoryItems[0]);
    }
  }

  void _closeCategory() {
    setState(() {
      _selectedCategory = null;
      _showUI = true;
    });
    _disposeVideo();
    _idleTimer?.cancel();
  }

  void _onItemChanged(int index, CatalogItem item) {
    setState(() => _currentItemIndex = index);
    _userInteracted();
    _fireAnalyticsEvent(item.id, 'view');
    _resolveMediaPath(item);
  }

  // --- HELPER: FORMAT DURATION ---
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  // --- BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Transparent to let the gradient shine
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.backgroundGradientStart, AppColors.backgroundGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: GestureDetector(
          onTap: _userInteracted,
          onPanDown: (_) => _userInteracted(),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('clients').doc(widget.clientId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;
              final List<dynamic> rawCatalog = data['catalog'] ?? [];
              final List<CatalogItem> catalogItems = rawCatalog.map((json) => CatalogItem.fromMap(json as Map<String, dynamic>)).toList();

              if (catalogItems.isEmpty) {
                return const Center(child: Text("Catalog is empty.", style: TextStyle(color: Colors.white54, fontSize: 24, letterSpacing: 2)));
              }

              // Group items by category
              final Map<String, List<CatalogItem>> groupedItems = {};
              for (var item in catalogItems) {
                String cat = item.category.isNotEmpty ? item.category : 'Uncategorized';
                groupedItems.putIfAbsent(cat, () => []).add(item);
              }

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _selectedCategory == null
                    ? _buildCategoryGrid(groupedItems)
                    : _buildImmersiveItemView(groupedItems[_selectedCategory]!),
              );
            },
          ),
        ),
      ),
    );
  }

  // --- 1. PREMIUM CATEGORY GRID ---
  Widget _buildCategoryGrid(Map<String, List<CatalogItem>> groupedItems) {
    final categories = groupedItems.keys.toList();

    return Padding(
      padding: const EdgeInsets.all(48.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "EXPLORE COLLECTIONS",
            style: TextStyle(color: AppColors.textPrimary, fontSize: 42, fontWeight: FontWeight.w300, letterSpacing: 8),
          ),
          const SizedBox(height: 48),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.8,
                crossAxisSpacing: 32,
                mainAxisSpacing: 32,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                String categoryName = categories[index];
                CatalogItem previewItem = groupedItems[categoryName]!.first;

                return GestureDetector(
                  onTap: () => _openCategory(categoryName, groupedItems[categoryName]!),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPremiumThumbnail(previewItem.mediaUrl),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.8)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 32,
                            left: 32,
                            right: 32,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  categoryName.toUpperCase(),
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w600, letterSpacing: 4),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "${groupedItems[categoryName]!.length} Items",
                                  style: const TextStyle(color: Colors.white70, fontSize: 18, letterSpacing: 2),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. IMMERSIVE FULL-SCREEN ITEM VIEW ---
  Widget _buildImmersiveItemView(List<CatalogItem> items) {
    bool isVideo = items[_currentItemIndex].mediaType == 'video' || items[_currentItemIndex].mediaUrl.toLowerCase().endsWith('.mp4');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Swipeable Media Layer
        PageView.builder(
          controller: _pageController,
          itemCount: items.length,
          onPageChanged: (index) => _onItemChanged(index, items[index]),
          itemBuilder: (context, index) {
            return _buildSmartMediaViewer(items[index]);
          },
        ),

        // Floating Back Button (Glassmorphism)
        AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: GestureDetector(
                onTap: _closeCategory,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.glassBackground,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: AppColors.glassBorder, width: 1.0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 18),
                          SizedBox(width: 12),
                          Text("BACK TO COLLECTIONS", style: TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 🎛️ COMPACT UNIFIED BOTTOM PANEL (Glassmorphism)
        AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.glassBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.glassBorder, width: 1.0),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isVideo) _buildCompactVideoControls(),
                        if (isVideo) const SizedBox(height: 12),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    items[_currentItemIndex].title,
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    items[_currentItemIndex].description,
                                    style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(50)),
                                        child: Text(
                                          "${items[_currentItemIndex].price.toStringAsFixed(2)} ${items[_currentItemIndex].currency}",
                                          style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      if (!items[_currentItemIndex].inStock)
                                        const Text("OUT OF STOCK", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            if (items[_currentItemIndex].qrActionUrl.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _fireAnalyticsEvent(items[_currentItemIndex].id, 'qr_scan'),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(16)),
                                        child: QrImageView(data: items[_currentItemIndex].qrActionUrl, version: QrVersions.auto, size: 80.0),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text("SCAN TO BUY", style: TextStyle(color: AppColors.textPrimary, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Thin Pagination Dots Indicator
        AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(items.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    height: _currentItemIndex == index ? 24 : 8,
                    width: 4,
                    decoration: BoxDecoration(
                      color: _currentItemIndex == index ? AppColors.textPrimary : AppColors.textPrimary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- 🎬 COMPACT VIDEO CONTROLS ---
  Widget _buildCompactVideoControls() {
    if (_videoController == null || !_videoController!.value.isInitialized) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: _videoController!,
      builder: (context, VideoPlayerValue value, child) {
        final position = value.position;
        final duration = value.duration;

        double maxVal = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
        double currentVal = position.inMilliseconds.toDouble().clamp(0.0, maxVal);

        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: AppColors.textPrimary, size: 36),
              onPressed: () {
                _userInteracted();
                value.isPlaying ? _videoController!.pause() : _videoController!.play();
              },
            ),
            const SizedBox(width: 16),
            Text(_formatDuration(position), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),

            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.textPrimary,
                  inactiveTrackColor: AppColors.textPrimary.withOpacity(0.2),
                  thumbColor: AppColors.textPrimary,
                  trackHeight: 3.0,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                ),
                child: Slider(
                  value: currentVal,
                  min: 0.0,
                  max: maxVal,
                  onChanged: (newValue) {
                    _userInteracted();
                    _videoController!.seekTo(Duration(milliseconds: newValue.toInt()));
                  },
                ),
              ),
            ),

            Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        );
      },
    );
  }

  // --- SMART MEDIA HANDLERS ---

  Widget _buildPremiumThumbnail(String url) {
    if (url.isEmpty) return Container(color: Colors.grey[900]);
    return Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey[900]));
  }

  Widget _buildSmartMediaViewer(CatalogItem item) {
    if (_localMediaPath == null || _localMediaPath!.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }

    bool isVideo = item.mediaType == 'video' || _localMediaPath!.toLowerCase().endsWith('.mp4');

    if (isVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0),
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ],
        );
      } else {
        return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
      }
    }

    ImageProvider imageProvider;
    if (_localMediaPath!.startsWith('file://')) {
      imageProvider = FileImage(File(_localMediaPath!.replaceAll('file://', '')));
    } else {
      imageProvider = NetworkImage(_localMediaPath!);
    }

    // 🌟 NEW: Premium 3D Gallery Suspension for Images 🌟
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. BREATHING AMBIENT BACKGROUND
        AnimatedBuilder(
          animation: _imageAnimationController!,
          builder: (context, child) {
            // Very slowly pulses the background blur to make it feel alive
            final scale = 1.0 + (_imageAnimationController!.value * 0.05);
            return Transform.scale(scale: scale, child: child);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: imageProvider, fit: BoxFit.cover),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0),
                child: Container(color: Colors.black.withOpacity(0.5)),
              ),
            ],
          ),
        ),

        // 2. 3D FLOATING FOREGROUND MEDIA
        AnimatedBuilder(
          animation: _imageAnimationController!,
          builder: (context, child) {
            // Creates a smooth, organic sine wave from -1.0 to 1.0
            final double wave = math.sin(_imageAnimationController!.value * math.pi);
            final double cosWave = math.cos(_imageAnimationController!.value * math.pi);

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // Add 3D Perspective
                ..rotateX(wave * 0.015) // Gentle vertical tilt
                ..rotateY(cosWave * 0.015) // Gentle horizontal tilt
                ..translate(0.0, wave * 15.0, 0.0), // Slowly float up and down by 15 pixels
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 180), // Keep it clear of the bottom UI panel
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16), // Premium rounded art gallery corners
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}