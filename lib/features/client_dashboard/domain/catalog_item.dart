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

  // NEW: Analytics Tracking Counters!
  final int viewCount;    // How many times a customer tapped this item
  final int qrScanCount;  // How many times they clicked/scanned the QR code

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
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'price': price,
      'currency': currency,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'inStock': inStock,
      'qrActionUrl': qrActionUrl,
      // We only include these when creating.
      // When updating via Kiosk, we use FieldValue.increment()
      'viewCount': viewCount,
      'qrScanCount': qrScanCount,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  factory CatalogItem.fromMap(Map<String, dynamic> map, String documentId) {
    return CatalogItem(
      id: documentId,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Uncategorized',
      price: (map['price'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'DZD',
      mediaUrl: map['mediaUrl'] ?? '',
      mediaType: map['mediaType'] ?? 'image',
      inStock: map['inStock'] ?? true,
      qrActionUrl: map['qrActionUrl'] ?? '',
      // Default to 0 if the field doesn't exist yet
      viewCount: map['viewCount'] ?? 0,
      qrScanCount: map['qrScanCount'] ?? 0,
    );
  }
}