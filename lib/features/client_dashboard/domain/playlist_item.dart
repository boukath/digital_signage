// File: lib/features/client_dashboard/domain/playlist_item.dart

class PlaylistItem {
  final String id;
  final String url;
  final String type;

  // 👇 NEW: Added properties for video thumbnails and display names
  final String? name;
  final String? thumbnailUrl;

  int durationInSeconds;

  // Scheduling Properties
  String? startTime; // Stored as "HH:mm", null means all day
  String? endTime;   // Stored as "HH:mm", null means all day
  List<int> daysOfWeek; // 1 = Monday, 7 = Sunday. Empty list means everyday.

  PlaylistItem({
    required this.id,
    required this.url,
    required this.type,
    this.name,             // 👈 NEW
    this.thumbnailUrl,     // 👈 NEW
    this.durationInSeconds = 10,
    this.startTime,
    this.endTime,
    this.daysOfWeek = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'type': type,
      'name': name,                 // 👈 NEW
      'thumbnailUrl': thumbnailUrl, // 👈 NEW
      'durationInSeconds': durationInSeconds,
      'startTime': startTime,
      'endTime': endTime,
      'daysOfWeek': daysOfWeek,
    };
  }

  factory PlaylistItem.fromMap(Map<String, dynamic> map) {
    return PlaylistItem(
      id: map['id'] ?? '',
      url: map['url'] ?? '',
      type: map['type'] ?? 'image',
      name: map['name'],                 // 👈 NEW
      thumbnailUrl: map['thumbnailUrl'], // 👈 NEW
      durationInSeconds: map['durationInSeconds'] ?? 10,
      startTime: map['startTime'],
      endTime: map['endTime'],
      // Safely parse the dynamic list from Firestore into a List<int>
      daysOfWeek: map['daysOfWeek'] != null ? List<int>.from(map['daysOfWeek']) : [],
    );
  }
}