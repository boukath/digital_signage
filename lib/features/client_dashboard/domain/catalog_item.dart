// File: lib/features/client_dashboard/domain/catalog_item.dart

class CatalogItem {
  final String id;
  final String title;
  final String description;
  final String department; // 👈 NEW: Top-level grouping (e.g., "MEN", "WOMEN")
  final String category;   // Sub-level grouping (e.g., "T-Shirts", "Sneakers")
  final double price;
  final String currency;

  // Primary Media
  final String mediaUrl;
  final String mediaType;
  final String thumbnailUrl; // Stores the cover image for videos/3D

  final List<Map<String, dynamic>> gallery;

  final bool inStock;
  final String qrActionUrl;

  final int viewCount;
  final int qrScanCount;

  CatalogItem({
    required this.id,
    required this.title,
    required this.description,
    this.department = 'General', // 👈 Default for backward compatibility
    required this.category,
    required this.price,
    this.currency = 'DZD',
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl = '', // Default to empty
    this.gallery = const [],
    this.inStock = true,
    this.qrActionUrl = '',
    this.viewCount = 0,
    this.qrScanCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'department': department, // 👈 Saved to Firestore
      'category': category,
      'price': price,
      'currency': currency,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'thumbnailUrl': thumbnailUrl,
      'gallery': gallery,
      'inStock': inStock,
      'qrActionUrl': qrActionUrl,
      'viewCount': viewCount,
      'qrScanCount': qrScanCount,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  factory CatalogItem.fromMap(Map<String, dynamic> map) {
    return CatalogItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      department: map['department'] ?? 'General', // 👈 Loaded safely from Firestore
      category: map['category'] ?? 'Uncategorized',
      price: (map['price'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'DZD',
      mediaUrl: map['mediaUrl'] ?? '',
      mediaType: map['mediaType'] ?? 'image',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      gallery: map['gallery'] != null
          ? List<Map<String, dynamic>>.from(map['gallery'])
          : [],
      inStock: map['inStock'] ?? true,
      qrActionUrl: map['qrActionUrl'] ?? '',
      viewCount: map['viewCount'] ?? 0,
      qrScanCount: map['qrScanCount'] ?? 0,
    );
  }
}