import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class AppThumbnailHelper {
  static Future<Uint8List?> extract(PlatformFile file) async {
    if (file.path == null) return null;

    // Uses the native hardware to extract the frame (Fastest)
    return await VideoThumbnail.thumbnailData(
      video: file.path!,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 600,
      quality: 75,
    );
  }
}