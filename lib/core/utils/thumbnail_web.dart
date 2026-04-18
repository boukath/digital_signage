// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class AppThumbnailHelper {
  static Future<Uint8List?> extract(PlatformFile file) async {
    // 1. Ensure we actually have the video bytes from FilePicker
    if (file.bytes == null) {
      print("⚠️ Web Extractor: file.bytes is null! Make sure withData: kIsWeb is set in FilePicker.");
      return null;
    }

    print("🌐 Web Extractor: Starting extraction for ${file.name}...");
    final completer = Completer<Uint8List?>();

    try {
      // 2. Create local browser URL for the video
      final blob = html.Blob([file.bytes!], 'video/mp4');
      final url = html.Url.createObjectUrlFromBlob(blob);

      // 3. Create the video element
      final video = html.VideoElement()
        ..src = url
        ..autoplay = true // Autoplay muted forces the browser to load it
        ..muted = true
        ..style.display = 'none'; // Keep it invisible!

      // 🚨 CRITICAL FIX: Append to the DOM!
      // If we don't do this, Edge/Chrome will suspend the video and do nothing.
      html.document.body?.append(video);

      // 4. Wait for it to load, then jump to 1 second
      video.onLoadedData.listen((_) {
        print("🌐 Web Extractor: Video loaded. Seeking to 1 second...");
        // If the video is shorter than 1 second, jump to the middle instead
        video.currentTime = video.duration < 1.0 ? (video.duration / 2) : 1.0;
      });

      // 5. Once it finishes seeking, take the screenshot!
      video.onSeeked.listen((_) {
        print("🌐 Web Extractor: Seek complete. Drawing canvas...");
        try {
          final canvas = html.CanvasElement(width: video.videoWidth, height: video.videoHeight);
          canvas.context2D.drawImage(video, 0, 0);

          final dataUrl = canvas.toDataUrl('image/jpeg', 0.75);

          // Cleanup memory
          html.Url.revokeObjectUrl(url);
          video.remove(); // Remove from DOM

          // Convert Base64 back to Flutter bytes
          final base64String = dataUrl.split(',').last;
          print("✅ Web Extractor: Thumbnail successfully generated!");
          completer.complete(base64Decode(base64String));
        } catch (e) {
          print("⚠️ Web Extractor Canvas Error: $e");
          video.remove();
          completer.complete(null);
        }
      });

      // Handle corrupted videos
      video.onError.listen((e) {
        print("⚠️ Web Extractor Video Error: The browser couldn't read the video file.");
        video.remove();
        completer.complete(null);
      });

      // 6. Safety Timeout (Don't let the app hang forever)
      Future.delayed(const Duration(seconds: 8), () {
        if (!completer.isCompleted) {
          print("⚠️ Web Extractor: Timed out after 8 seconds. Cleaning up...");
          video.remove();
          completer.complete(null);
        }
      });

    } catch (e) {
      print("⚠️ Web Extractor Fatal Error: $e");
      completer.complete(null);
    }

    return completer.future;
  }
}