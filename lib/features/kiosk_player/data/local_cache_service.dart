import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class LocalCacheService {
  /// Takes a cloud URL, checks if it's downloaded, downloads it if not,
  /// and returns the local file path ready for the video player or 3D viewer.
  Future<String> getCachedMediaPath(String cloudUrl) async {
    // 1. Get the local Windows Application Documents directory
    final directory = await getApplicationDocumentsDirectory();

    // We create a dedicated folder just for our signage media
    final String cacheDirPath = '${directory.path}\\DigitalSignageCache';
    final Directory cacheDir = Directory(cacheDirPath);

    // Create the cache folder if it doesn't exist yet
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // 2. Create a unique safe filename based on the URL
    // We use the URL's hash code so if the same file is used in multiple playlists,
    // it still only downloads once.
    final String safeFileName = _generateSafeFileName(cloudUrl);
    final String localFilePath = '$cacheDirPath\\$safeFileName';
    final File localFile = File(localFilePath);

    // 3. The Cache Check: Does it already exist locally?
    if (await localFile.exists()) {
      print("⚡ LOADED FROM CACHE: $localFilePath");
      return localFilePath; // Return the local path immediately
    }

    // 4. The Download: It's not local, so we fetch it from Backblaze B2
    print("☁️ DOWNLOADING FROM CLOUD: $cloudUrl");
    try {
      final response = await http.get(Uri.parse(cloudUrl));

      if (response.statusCode == 200) {
        // Write the downloaded bytes to the Windows hard drive
        await localFile.writeAsBytes(response.bodyBytes);
        print("✅ CACHED SUCCESSFULLY: $localFilePath");

        return localFilePath; // Return the new local path
      } else {
        throw Exception('Failed to download media. Status Code: ${response.statusCode}');
      }
    } catch (e) {
      print("❌ ERROR DOWNLOADING MEDIA: $e");
      rethrow;
    }
  }

  /// Helper method to generate a clean, safe filename from a cloud URL
  String _generateSafeFileName(String url) {
    try {
      final uri = Uri.parse(url);
      // Grabs the actual filename (e.g., 'promo_video.mp4') ignoring query parameters
      final String originalFileName = uri.pathSegments.last;

      // Prepends a unique hash to prevent naming collisions if two files
      // have the same name in different folders on Backblaze.
      return '${url.hashCode}_$originalFileName';
    } catch (e) {
      // Fallback if URL parsing fails for some reason
      return '${url.hashCode}.bin';
    }
  }

  /// Optional: A method to clear the cache if the hard drive gets too full
  /// (This will be useful later when you trigger the "Clear Cache" remote command)
  Future<void> clearCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final Directory cacheDir = Directory('${directory.path}\\DigitalSignageCache');

      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        print("🧹 Local cache cleared successfully.");
      }
    } catch (e) {
      print("❌ Error clearing cache: $e");
    }
  }
}