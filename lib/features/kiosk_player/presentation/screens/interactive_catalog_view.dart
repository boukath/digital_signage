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

  // --- 🌟 NEW: 3-TIER NAVIGATION STATE ---
  String? _selectedDepartment;     // LEVEL 1: e.g., "MEN"
  String? _selectedCategoryFilter; // LEVEL 2: Sub-filter e.g., "T-Shirts"
  CatalogItem? _selectedProduct;   // LEVEL 3: The actual product

  int _currentGalleryIndex = 0;
  String? _localMediaPath;
  String _currentMediaType = 'image';

  VideoPlayerController? _videoController;

  // Controllers for the premium carousels
  late PageController _deptPageController;
  late PageController _aislePageController;

  Timer? _idleTimer;
  bool _showUI = true;
  AnimationController? _imageAnimationController;

  @override
  void initState() {
    super.initState();
    _deptPageController = PageController();
    // viewportFraction 0.5 allows us to see the items on the left and right!
    _aislePageController = PageController(viewportFraction: 0.5);

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
    _deptPageController.dispose();
    _aislePageController.dispose();
    super.dispose();
  }

  void _userInteracted() {
    setState(() => _showUI = true);
    _startIdleTimer();
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _selectedDepartment != null) {
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

    // 👇 FIXED: SET VOLUME TO 1.0 SO IT PLAYS SOUND BY DEFAULT
    _videoController!.setVolume(1.0);

    _videoController!.play();
    if (mounted) setState(() {});
  }

  void _disposeVideo() {
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }
  }

  // --- 🌟 SMART NAVIGATION LOGIC ---

  void _openDepartment(String department) {
    setState(() {
      _selectedDepartment = department;
      _selectedCategoryFilter = null;
      _selectedProduct = null;
    });
    _userInteracted();
  }

  void _openProduct(CatalogItem item) {
    setState(() {
      _selectedProduct = item;
      _currentGalleryIndex = 0;
    });
    _userInteracted();
    _fireAnalyticsEvent(item.id, 'view');

    // Trigger the heavy media to load immediately
    final initialMedia = _getGalleryList(item).first;
    _resolveMediaPath(initialMedia['url'], initialMedia['type']);
  }

  void _goBack() {
    _userInteracted();
    _disposeVideo(); // Stop any playing video

    setState(() {
      if (_selectedProduct != null) {
        // If in Fitting Room, go back to Aisle
        _selectedProduct = null;
      } else if (_selectedDepartment != null) {
        // If in Aisle, go back to Lookbook
        _selectedDepartment = null;
        _selectedCategoryFilter = null;
      }
    });
  }

  List<Map<String, dynamic>> _getGalleryList(CatalogItem item) {
    if (item.gallery.isNotEmpty) return item.gallery;
    return [{'url': item.mediaUrl, 'type': item.mediaType}];
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
      backgroundColor: Colors.black,
      body: GestureDetector(
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
            final List<dynamic> rawDepartments = data['departments'] ?? []; // 👈 NEW

            // 👈 NEW: Map Department Name -> Background Image URL
            final Map<String, String> departmentBackgrounds = {};
            for (var dept in rawDepartments) {
              departmentBackgrounds[dept['name']] = dept['imageUrl'] ?? '';
            }

            final List<CatalogItem> catalogItems = rawCatalog.map((json) => CatalogItem.fromMap(json as Map<String, dynamic>)).toList();

            if (catalogItems.isEmpty) {
              return const Center(child: Text("Catalog is empty.", style: TextStyle(color: Colors.white54, fontSize: 24, letterSpacing: 2)));
            }

            // 🌟 Group by DEPARTMENT instead of Category
            final Map<String, List<CatalogItem>> groupedByDept = {};
            for (var item in catalogItems) {
              String dept = item.department.isNotEmpty ? item.department : 'General';
              groupedByDept.putIfAbsent(dept, () => []).add(item);
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _selectedDepartment == null
              // 👇 Pass the new backgrounds map here
                  ? _buildLevel1Lookbook(groupedByDept, departmentBackgrounds)
                  : (_selectedProduct == null
                  ? _buildLevel2Aisle(groupedByDept[_selectedDepartment]!)
                  : _buildLevel3FittingRoom(_selectedProduct!)),
            );
          },
        ),
      ),
    );
  }

  // =========================================================================
  // LEVEL 1: THE LOOKBOOK (Vertical Parallax Carousel)
  // =========================================================================

  // 👇 Added the map to the parameters here
  Widget _buildLevel1Lookbook(Map<String, List<CatalogItem>> groupedByDept, Map<String, String> departmentBackgrounds) {
    final departments = groupedByDept.keys.toList();

    return Stack(
      children: [
        PageView.builder(
          controller: _deptPageController,
          scrollDirection: Axis.vertical, // Vertical scrolling feels more premium here
          itemCount: departments.length,
          itemBuilder: (context, index) {
            final deptName = departments[index];
            final deptItems = groupedByDept[deptName]!;

            // Use the first item's image as the Fallback Hero cover
            final previewItem = deptItems.first;

            // 🌟 THE MAGIC HAPPENS HERE 🌟
            // Try to get the dedicated cover. If it doesn't exist, fallback to the old product image!
            final String defaultBg = previewItem.mediaType == 'image' ? previewItem.mediaUrl : previewItem.thumbnailUrl;

            final String bgUrl = departmentBackgrounds[deptName]?.isNotEmpty == true
                ? departmentBackgrounds[deptName]!
                : defaultBg;

            return GestureDetector(
              onTap: () => _openDepartment(deptName),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // --- PARALLAX BACKGROUND ---
                  AnimatedBuilder(
                    animation: _deptPageController,
                    builder: (context, child) {
                      double pageOffset = 0;
                      if (_deptPageController.position.haveDimensions) {
                        pageOffset = _deptPageController.page! - index;
                      }
                      return Transform.translate(
                        // Shift the image vertically based on scroll position
                        offset: Offset(0, pageOffset * MediaQuery.of(context).size.height * 0.4),
                        child: Image.network(
                          bgUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
                        ),
                      );
                    },
                  ),

                  // --- DARK GRADIENT OVERLAY ---
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.8)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  // --- MASSIVE TYPOGRAPHY ---
                  Align(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          deptName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 120,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 20,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.white),
                              borderRadius: BorderRadius.circular(30)
                          ),
                          child: Text(
                            "EXPLORE ${deptItems.length} ITEMS",
                            style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 4, fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        ),

        // Custom Scroll Indicator
        Positioned(
          right: 48,
          top: 0,
          bottom: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.keyboard_arrow_up, color: Colors.white54),
                const SizedBox(height: 8),
                const Text("SWIPE", style: TextStyle(color: Colors.white54, letterSpacing: 4, fontSize: 10)),
                const SizedBox(height: 8),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              ],
            ),
          ),
        )
      ],
    );
  }

  // =========================================================================
  // LEVEL 2: THE AISLE (Horizontal Dynamic Carousel)
  // =========================================================================
  Widget _buildLevel2Aisle(List<CatalogItem> deptItems) {
    // Extract unique categories within this department for the filter chips
    final Set<String> categories = {"All"};
    categories.addAll(deptItems.map((e) => e.category));

    // Apply the filter
    final List<CatalogItem> displayItems = _selectedCategoryFilter == null || _selectedCategoryFilter == "All"
        ? deptItems
        : deptItems.where((i) => i.category == _selectedCategoryFilter).toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A24), Color(0xFF0A0A0A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER & NAVIGATION ---
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 64, 48, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _goBack,
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
                          SizedBox(width: 8),
                          Text("BACK TO DEPARTMENTS", style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _selectedDepartment!.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w300, letterSpacing: 8),
                    ),
                  ],
                ),

                // --- CATEGORY FILTER CHIPS ---
                Row(
                  children: categories.map((cat) {
                    bool isSelected = (_selectedCategoryFilter ?? "All") == cat;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategoryFilter = cat;
                        });
                        _userInteracted();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(left: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          border: Border.all(color: isSelected ? Colors.white : Colors.white24),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          cat.toUpperCase(),
                          style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                )
              ],
            ),
          ),
          const SizedBox(height: 64),

          // --- HORIZONTAL CAROUSEL ---
          Expanded(
            child: displayItems.isEmpty
                ? const Center(child: Text("No items match this filter.", style: TextStyle(color: Colors.white54, fontSize: 18)))
                : PageView.builder(
              controller: _aislePageController,
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final item = displayItems[index];
                final bgUrl = item.mediaType == 'image' ? item.mediaUrl : item.thumbnailUrl;

                return AnimatedBuilder(
                  animation: _aislePageController,
                  builder: (context, child) {
                    double value = 1.0;
                    if (_aislePageController.position.haveDimensions) {
                      value = _aislePageController.page! - index;
                      value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0); // Scale down side items
                    }

                    // The active item is fully opaque, side items are faded
                    final opacity = (value - 0.7) / 0.3;

                    return Center(
                      child: Transform.scale(
                        scale: Curves.easeOut.transform(value),
                        child: Opacity(
                          opacity: opacity.clamp(0.3, 1.0),
                          child: GestureDetector(
                            onTap: () => _openProduct(item),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 20))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(bgUrl, fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.grey[800])),

                                    // Gradient at bottom for text
                                    Container(
                                      decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                                            begin: Alignment.center,
                                            end: Alignment.bottomCenter,
                                          )
                                      ),
                                    ),

                                    // Item Info
                                    Positioned(
                                      bottom: 32,
                                      left: 32,
                                      right: 32,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 8),
                                          Text("${item.price.toStringAsFixed(2)} ${item.currency}", style: const TextStyle(color: Colors.white70, fontSize: 18)),
                                        ],
                                      ),
                                    ),

                                    // Video/3D Badge
                                    if (item.mediaType != 'image')
                                      Positioned(
                                        top: 24,
                                        right: 24,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                          child: Icon(item.mediaType == 'video' ? Icons.play_arrow : Icons.view_in_ar, color: Colors.white),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // LEVEL 3: THE FITTING ROOM (60/40 Split Cinematic View)
  // =========================================================================
  Widget _buildLevel3FittingRoom(CatalogItem item) {
    bool isVideo = _currentMediaType == 'video';
    final List<Map<String, dynamic>> activeGallery = _getGalleryList(item);

    return Stack(
      children: [
        Row(
          children: [
            // LEFT 60%: Immersive Media Viewer
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 800),
                    child: Container(
                      key: ValueKey<String>(_localMediaPath ?? 'loading'),
                      child: _buildSmartMediaViewer(),
                    ),
                  ),

                  // Shadow blending into text panel
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

                  // Cinematic Thumbnail Strip
                  if (activeGallery.length > 1)
                    AnimatedOpacity(
                      opacity: _showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 48.0, top: 120),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(activeGallery.length, (index) {
                              bool isSelected = _currentGalleryIndex == index;
                              Map<String, dynamic> media = activeGallery[index];
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
                                      border: Border.all(color: isSelected ? Colors.white : Colors.white24, width: isSelected ? 2 : 1),
                                      boxShadow: isSelected ? [BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10)] : [],
                                      image: bgUrl != null ? DecorationImage(
                                        image: NetworkImage(bgUrl),
                                        fit: BoxFit.cover,
                                        colorFilter: isSelected ? null : ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
                                      ) : null
                                  ),
                                  child: media['type'] == 'video'
                                      ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24))
                                      : (media['type'] == '3d' ? const Center(child: Icon(Icons.view_in_ar, color: Colors.white, size: 24)) : null),
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
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
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
        ),

        // BACK BUTTON OVERLAY
        AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: GestureDetector(
                onTap: _goBack,
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
                          Text("BACK TO AISLE", style: TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
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
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary, size: 24),
                  ),
                ),
                const SizedBox(width: 12), // 👈 Adjusted spacing

                // 👇 VOLUME TOGGLE BUTTON
                GestureDetector(
                  onTap: () {
                    _userInteracted();
                    // If volume is 0.0 (muted), turn it up to 1.0. If not, mute it.
                    bool isMuted = value.volume == 0.0;
                    _videoController!.setVolume(isMuted ? 1.0 : 0.0);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                    child: Icon(
                        value.volume == 0.0 ? Icons.volume_off : Icons.volume_up,
                        color: AppColors.textPrimary,
                        size: 24
                    ),
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

  // --- SMART MEDIA VIEWER ---
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