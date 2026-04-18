// File: lib/features/kiosk_player/presentation/screens/interactive_catalog_view.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
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

  String? _selectedCategory;
  int _currentItemIndex = 0;

  // 📸 NEW: Tracks which gallery image is currently selected!
  int _currentGalleryIndex = 0;

  String? _localMediaPath;
  String _currentMediaType = 'image'; // Tracks type of currently viewed gallery item

  VideoPlayerController? _videoController;
  PageController? _pageController;

  Timer? _idleTimer;
  bool _showUI = true;
  AnimationController? _imageAnimationController;

  @override
  void initState() {
    super.initState();
    _startIdleTimer();
    _imageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _imageAnimationController?.dispose();
    _videoController?.dispose();
    _pageController?.dispose();
    super.dispose();
  }

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

  // 📸 UPDATED: Now resolves specific URLs from the gallery, not just the main item
  Future<void> _resolveMediaPath(String targetUrl, String targetType) async {
    setState(() {
      _localMediaPath = null;
      _currentMediaType = targetType;
    });

    if (targetUrl.isEmpty) return;

    try {
      String localPath = await _cacheService.getCachedMediaPath(targetUrl);
      if (mounted) {
        setState(() => _localMediaPath = 'file://$localPath');
        if (targetType == 'video' || localPath.toLowerCase().endsWith('.mp4')) {
          await _initializeVideo('file://$localPath');
        } else {
          _disposeVideo();
        }
      }
    } catch (e) {
      debugPrint("Falling back to network URL: $e");
      if (mounted) setState(() => _localMediaPath = targetUrl);
    }
  }

  Future<void> _initializeVideo(String localPath) async {
    _disposeVideo();
    final file = File(localPath.replaceAll('file://', ''));
    _videoController = VideoPlayerController.file(file);
    await _videoController!.initialize();
    _videoController!.setLooping(true);
    _videoController!.setVolume(0.0);
    _videoController!.play();
    if (mounted) setState(() {});
  }

  void _disposeVideo() {
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }
  }

  void _openCategory(String category, List<CatalogItem> categoryItems) {
    setState(() {
      _selectedCategory = category;
      _currentItemIndex = 0;
      _currentGalleryIndex = 0;
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
    setState(() {
      _currentItemIndex = index;
      _currentGalleryIndex = 0; // Reset gallery index when swiping to a new product
    });
    _userInteracted();
    _fireAnalyticsEvent(item.id, 'view');

    // Resolve the first item in the gallery (or fallback to primary media)
    final initialMedia = _getGalleryList(item).first;
    _resolveMediaPath(initialMedia['url'], initialMedia['type']);
  }

  // 📸 HELPER: Gets the gallery correctly without duplicating the main image
  List<Map<String, dynamic>> _getGalleryList(CatalogItem item) {
    // If the product has a cinematic gallery, use it exactly as saved!
    if (item.gallery.isNotEmpty) {
      return item.gallery;
    }

    // For backwards compatibility: If it's an old product created before
    // the gallery update, fallback to showing the single main image.
    return [
      {'url': item.mediaUrl, 'type': item.mediaType}
    ];
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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

              final Map<String, List<CatalogItem>> groupedItems = {};
              for (var item in catalogItems) {
                String cat = item.category.isNotEmpty ? item.category : 'Uncategorized';
                groupedItems.putIfAbsent(cat, () => []).add(item);
              }

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _selectedCategory == null
                    ? _buildCategoryGrid(groupedItems)
                    : _buildEditorialItemView(groupedItems[_selectedCategory]!),
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

                // 📸 THE FIX IS RIGHT HERE: Use thumbnailUrl if it's a video!
                String gridImage = previewItem.mediaType == 'image' ? previewItem.mediaUrl : previewItem.thumbnailUrl;

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
                          _buildPremiumThumbnail(gridImage), // 👈 Passing the resolved image
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

  // --- 2. THE NEW 60/40 EDITORIAL VIEW ---
  Widget _buildEditorialItemView(List<CatalogItem> items) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: items.length,
          onPageChanged: (index) => _onItemChanged(index, items[index]),
          itemBuilder: (context, index) {
            return _buildEditorialPage(items[index]);
          },
        ),

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
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white24, width: 1.0),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 18),
                          SizedBox(width: 12),
                          Text("COLLECTIONS", style: TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(items.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    height: _currentItemIndex == index ? 32 : 8,
                    width: 4,
                    decoration: BoxDecoration(
                      color: _currentItemIndex == index ? AppColors.textPrimary : AppColors.textPrimary.withOpacity(0.2),
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

  // --- 3. THE 60/40 PAGE LAYOUT WITH GALLERY STRIP ---
  Widget _buildEditorialPage(CatalogItem item) {
    bool isVideo = _currentMediaType == 'video';

    // Get the full list of media (Main Image + Gallery)
    final List<Map<String, dynamic>> activeGallery = _getGalleryList(item);

    return Row(
      children: [
        // LEFT 60%: Immersive Media Art Gallery
        Expanded(
          flex: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 📸 THE SMOOTH CROSSFADING MEDIA VIEWER
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                // The Key ensures Flutter knows when to trigger the fade animation
                child: Container(
                  key: ValueKey<String>(_localMediaPath ?? 'loading'),
                  child: _buildSmartMediaViewer(),
                ),
              ),

              // Shadow blending into the text panel
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 80,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xFF0A0A0A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),

              // 📸 NEW: THE CINEMATIC THUMBNAIL STRIP
              if (activeGallery.length > 1) // Only show if there's more than 1 image
                AnimatedOpacity(
                  opacity: _showUI ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 48.0, top: 120), // Kept below the back button
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(activeGallery.length, (index) {
                          bool isSelected = _currentGalleryIndex == index;
                          Map<String, dynamic> media = activeGallery[index];

                          // 📸 NEW FIX: Properly loading the video thumbnail for the strip!
                          String? thumbUrl = media['thumbnailUrl'];
                          String? bgUrl = media['type'] == 'image' ? media['url'] : (thumbUrl != null && thumbUrl.isNotEmpty ? thumbUrl : null);

                          return GestureDetector(
                            onTap: () {
                              _userInteracted();
                              if (_currentGalleryIndex != index) {
                                setState(() => _currentGalleryIndex = index);
                                _resolveMediaPath(media['url'], media['type']);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              width: 60,
                              height: 80,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.white24,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: isSelected ? [
                                    BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10)
                                  ] : [],
                                  image: bgUrl != null ? DecorationImage(
                                    image: NetworkImage(bgUrl),
                                    fit: BoxFit.cover,
                                    colorFilter: isSelected
                                        ? null
                                        : ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
                                  ) : null
                              ),
                              // Tiny icon overlay if it's a video or 3D model
                              child: media['type'] == 'video'
                                  ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24))
                                  : (media['type'] == '3d'
                                  ? const Center(child: Icon(Icons.view_in_ar, color: Colors.white, size: 24))
                                  : null),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // RIGHT 40%: The Editorial Typography Column
        Expanded(
          flex: 4,
          child: Container(
            color: const Color(0xFF0A0A0A),
            padding: const EdgeInsets.fromLTRB(48, 80, 80, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.category.toUpperCase(),
                  style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 4),
                ),
                const SizedBox(height: 16),

                Text(
                  item.title,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 56, fontWeight: FontWeight.bold, height: 1.1, letterSpacing: -1),
                ),
                const SizedBox(height: 24),

                Text(
                  "${item.price.toStringAsFixed(2)} ${item.currency}",
                  style: const TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: 1),
                ),

                if (!item.inStock) ...[
                  const SizedBox(height: 12),
                  const Text("CURRENTLY OUT OF STOCK", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2)),
                ],

                const SizedBox(height: 48),

                Text(
                  item.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 18, height: 1.6),
                ),

                const Spacer(),

                if (isVideo) ...[
                  _buildCompactVideoControls(),
                  const SizedBox(height: 48),
                ],

                if (item.qrActionUrl.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => _fireAnalyticsEvent(item.id, 'qr_scan'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8)
                          ),
                          child: QrImageView(data: item.qrActionUrl, version: QrVersions.auto, size: 100.0),
                        ),
                      ),
                      const SizedBox(width: 24),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("DISCOVER MORE", style: TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text("Scan this code with your phone camera to view full specifications or purchase instantly.", style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5)),
                          ],
                        ),
                      )
                    ],
                  )
              ],
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                GestureDetector(
                  onTap: () {
                    _userInteracted();
                    value.isPlaying ? _videoController!.pause() : _videoController!.play();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24)
                    ),
                    child: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary, size: 24),
                  ),
                ),
                const SizedBox(width: 24),
                Text(_formatDuration(position), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),

                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppColors.textPrimary,
                      inactiveTrackColor: AppColors.textPrimary.withOpacity(0.1),
                      thumbColor: AppColors.textPrimary,
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
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

                Text(_formatDuration(duration), style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
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

  // 📸 UPDATED: Now uses state variables `_localMediaPath` and `_currentMediaType` instead of hardcoding to the product item
  Widget _buildSmartMediaViewer() {
    if (_localMediaPath == null || _localMediaPath!.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }

    bool isVideo = _currentMediaType == 'video' || _localMediaPath!.toLowerCase().endsWith('.mp4');

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
              filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
              child: Container(color: Colors.black.withOpacity(0.6)),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _imageAnimationController!,
          builder: (context, child) {
            final scale = 1.0 + (_imageAnimationController!.value * 0.05);
            return Transform.scale(scale: scale, child: child);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: imageProvider, fit: BoxFit.cover),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
                child: Container(color: Colors.black.withOpacity(0.6)),
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _imageAnimationController!,
          builder: (context, child) {
            final double wave = math.sin(_imageAnimationController!.value * math.pi);
            final double cosWave = math.cos(_imageAnimationController!.value * math.pi);

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(wave * 0.015)
                ..rotateY(cosWave * 0.015)
                ..translate(0.0, wave * 15.0, 0.0),
              child: Padding(
                padding: const EdgeInsets.all(64.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
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