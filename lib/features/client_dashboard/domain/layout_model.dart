// File: lib/features/client_dashboard/domain/layout_model.dart

class ZoneModel {
  String id;
  double x;
  double y;
  double width;
  double height;
  String colorHex;

  // Content Linking Variables
  String zoneType;
  String? contentId;

  ZoneModel({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.colorHex,
    this.zoneType = 'playlist',
    this.contentId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'colorHex': colorHex,
      'zoneType': zoneType,
      'contentId': contentId,
    };
  }

  factory ZoneModel.fromMap(Map<String, dynamic> map) {
    return ZoneModel(
      id: map['id'] ?? '',
      x: (map['x'] ?? 0).toDouble(),
      y: (map['y'] ?? 0).toDouble(),
      width: (map['width'] ?? 0).toDouble(),
      height: (map['height'] ?? 0).toDouble(),
      colorHex: map['colorHex'] ?? '#FFFFFF',
      zoneType: map['zoneType'] ?? 'playlist',
      contentId: map['contentId'],
    );
  }
}

// 👇 THIS IS WHAT WAS MISSING!
// The actual LayoutModel that holds all the zones together.
class LayoutModel {
  String layoutId;
  String name;
  bool isLandscape;
  List<ZoneModel> zones;

  LayoutModel({
    required this.layoutId,
    required this.name,
    required this.isLandscape,
    required this.zones,
  });

  Map<String, dynamic> toMap() {
    return {
      'layoutId': layoutId,
      'name': name,
      'isLandscape': isLandscape,
      'zones': zones.map((z) => z.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}