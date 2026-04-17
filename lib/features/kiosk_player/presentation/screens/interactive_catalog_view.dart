import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart'; // ✅ ADDED: Video Player Import

import '../../../../core/constants/app_colors.dart';
import '../../data/local_cache_service.dart';
import '../../../client_dashboard/domain/catalog_item.dart';

class InteractiveCatalogView extends StatefulWidget {
  final String clientId;

  const InteractiveCatalogView({Key? key, required this.clientId}) : super(key: key);

  @override
  State<InteractiveCatalogView> createState() => _InteractiveCatalogViewState();
}

class _InteractiveCatalogViewState extends State<InteractiveCatalogView> {
  CatalogItem? _selectedItem;
  final LocalCacheService _cacheService = LocalCacheService();
  String? _localMediaPath;

  // ✅ ADDED: Video Player Controller
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
  }

  // ✅ ADDED: Prevent memory leaks when closing screen
  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _fireAnalyticsEvent(String itemId, String eventType) async {
    try {
      final analyticsDocRef = FirebaseFirestore.instance
          .collection('clients')
          .doc(widget.clientId)
          .collection('analytics')
          .doc(itemId);

      if (eventType == 'view') {
        await analyticsDocRef.set({
          'viewCount': FieldValue.increment(1),
          'lastViewed': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (eventType == 'qr_scan') {
        await analyticsDocRef.set({
          'qrScanCount': FieldValue.increment(1),
          'lastScanned': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      debugPrint('Analytics safely incremented: $eventType for $itemId');
    } catch (e) {
      debugPrint('Analytics Ping Failed: $e');
    }
  }

  // ✅ ADDED: Video Initialization Logic
  Future<void> _initializeVideo(String localPath) async {
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }

    final file = File(localPath.replaceAll('file://', ''));
    _videoController = VideoPlayerController.file(file);

    await _videoController!.initialize();
    _videoController!.setLooping(true);
    _videoController!.setVolume(0.0); // Muted by default so it doesn't blast audio
    _videoController!.play();

    if (mounted) {
      setState(() {});
    }
  }

  /// Resolves the URL: returns the local file path if cached, otherwise the network URL.
  Future<void> _resolveMediaPath(String mediaUrl) async {
    setState(() => _localMediaPath = null);
    try {
      String localPath = await _cacheService.getCachedMediaPath(mediaUrl);
      if (mounted) {
        setState(() => _localMediaPath = 'file://$localPath');

        // ✅ ADDED: Check if we need to initialize a video after downloading
        if (_selectedItem?.mediaType == 'video' || localPath.toLowerCase().endsWith('.mp4')) {
          await _initializeVideo('file://$localPath');
        }
      }
    } catch (e) {
      debugPrint("Falling back to network URL: $e");
      if (mounted) {
        setState(() => _localMediaPath = mediaUrl);
      }
    }
  }

  void _onItemSelected(CatalogItem item) {
    setState(() {
      _selectedItem = item;
    });

    _fireAnalyticsEvent(item.id, 'view');

    if (item.mediaUrl.isNotEmpty) {
      _resolveMediaPath(item.mediaUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          // ✅ FIX: Matched exactly to your AppColors
          colors: [AppColors.backgroundGradientStart, AppColors.backgroundGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clients')
            .doc(widget.clientId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading catalog", style: TextStyle(color: Colors.white)));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            // ✅ FIX: Using Colors.white for the loader
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List<dynamic> rawCatalog = data['catalog'] ?? [];

          final List<CatalogItem> catalogItems = rawCatalog.map((json) {
            final map = json as Map<String, dynamic>;
            return CatalogItem.fromMap(map, map['id'] ?? '');
          }).toList();

          if (catalogItems.isEmpty) {
            return const Center(
              child: Text("Catalog is empty.", style: TextStyle(color: Colors.white, fontSize: 24)),
            );
          }

          if (_selectedItem == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onItemSelected(catalogItems.first);
            });
          }

          return Row(
            children: [
              Expanded(
                flex: 1,
                child: _buildSidebar(catalogItems),
              ),
              Expanded(
                flex: 3,
                child: _buildMainView(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(List<CatalogItem> items) {
    return Container(
      margin: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: AppColors.glassBackground, // ✅ FIX: Using glassBackground
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder), // ✅ FIX: Using glassBorder
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = _selectedItem?.id == item.id;

          return GestureDetector(
            onTap: () => _onItemSelected(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // ✅ FIX: Using glassBorder for selected background
                color: isSelected ? AppColors.glassBorder : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  // ✅ FIX: White border for selection
                  color: isSelected ? Colors.white : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 20,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (!item.inStock)
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainView() {
    final item = _selectedItem;
    if (item == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      child: Column(
        children: [
          // THE MEDIA CANVAS
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.glassBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _localMediaPath == null
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _buildMediaViewer(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // PRODUCT DETAILS & QR CODE
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.glassBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              // ✅ FIX: Using glassBackground and glassBorder
                              color: AppColors.glassBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Text(
                              "${item.price.toStringAsFixed(2)} ${item.currency}",
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.description,
                        style: const TextStyle(color: Colors.white70, fontSize: 20),
                      ),
                      const SizedBox(height: 16),
                      if (!item.inStock)
                        const Text(
                          "Currently Out of Stock",
                          style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),

                // QR CODE
                if (item.qrActionUrl.isNotEmpty)
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () => _fireAnalyticsEvent(item.id, 'qr_scan'),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: item.qrActionUrl,
                            version: QrVersions.auto,
                            size: 150.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Scan to Buy",
                        style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                      )
                    ],
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ ADDED: Video playback support alongside image fallback
  Widget _buildMediaViewer() {
    if (_localMediaPath == null || _localMediaPath!.isEmpty) {
      return const Center(child: Icon(Icons.image_not_supported, color: Colors.white24, size: 100));
    }

    bool isVideo = _selectedItem?.mediaType == 'video' || _localMediaPath!.toLowerCase().endsWith('.mp4');

    if (isVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        );
      } else {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
    }

    // Existing Image Logic
    if (_localMediaPath!.startsWith('file://')) {
      final file = File(_localMediaPath!.replaceAll('file://', ''));
      if (!file.existsSync()) {
        return const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 100));
      }
      return Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 100)),
      );
    } else {
      return Image.network(
        _localMediaPath!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 100)),
      );
    }
  }
}