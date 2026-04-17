// File: lib/features/client_dashboard/domain/catalog_item.dart

class CatalogItem {
  final String id;
  final String title;
  final String description;
  final String category;
  final double price;
  final String currency;
  final String mediaUrl;
  final String mediaType;
  final bool inStock;
  final String qrActionUrl;

  // Analytics Tracking Counters!
  final int viewCount;
  final int qrScanCount;

  CatalogItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    this.currency = 'DZD',
    required this.mediaUrl,
    required this.mediaType,
    this.inStock = true,
    this.qrActionUrl = '',
    this.viewCount = 0,
    this.qrScanCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id, // The ID is saved directly inside the map for Option B
      'title': title,
      'description': description,
      'category': category,
      'price': price,
      'currency': currency,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'inStock': inStock,
      'qrActionUrl': qrActionUrl,
      'viewCount': viewCount,
      'qrScanCount': qrScanCount,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  // ✅ OPTION B FIX: Removed "String documentId" from the parameters.
  // Because it's an array, it doesn't have a Document ID. It pulls 'id' from the map.
  factory CatalogItem.fromMap(Map<String, dynamic> map) {
    return CatalogItem(
      id: map['id'] ?? '', // 👈 Pulls the ID directly from the array map
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Uncategorized',
      price: (map['price'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'DZD',
      mediaUrl: map['mediaUrl'] ?? '',
      mediaType: map['mediaType'] ?? 'image',
      inStock: map['inStock'] ?? true,
      qrActionUrl: map['qrActionUrl'] ?? '',
      viewCount: map['viewCount'] ?? 0,
      qrScanCount: map['qrScanCount'] ?? 0,
    );
  }
}