// File: lib/features/client_dashboard/data/b2_storage_service.dart

import 'dart:typed_data';
import 'package:minio/minio.dart';

/// Documentation:
/// This service handles uploading and deleting heavy media directly to/from Backblaze B2.
class B2StorageService {
  // Initialize the Minio client with your exact B2 S3 credentials
  final Minio _minio = Minio(
    endPoint: 's3.eu-central-003.backblazeb2.com',
    accessKey: '003788b1984ea070000000002',
    secretKey: 'K003ZyFXokrenOKtP9s3wyLR5/8DVRM',
    useSSL: true,
  );

  final String _bucketName = 'boitexinfo';

  /// Documentation:
  /// Uploads a file from RAM (Best for small files like images/thumbnails)
  Future<String?> uploadMedia(String fileName, Uint8List fileBytes, String clientId) async {
    try {
      final String safePath = 'signage_media/$clientId/$fileName';
      await _minio.putObject(_bucketName, safePath, Stream.value(fileBytes));
      return 'https://$_bucketName.s3.eu-central-003.backblazeb2.com/$safePath';
    } catch (e) {
      print('Backblaze Upload Error: $e');
      return null;
    }
  }

  /// Documentation:
  /// 🚀 NEW: Uploads a file via Stream (Best for large files like 4K Video/3D Models)
  /// Prevents Out-Of-Memory (OOM) crashes on mobile/desktop devices.
  Future<String?> uploadMediaStream(String fileName, Stream<Uint8List> fileStream, int fileSize, String clientId) async {
    try {
      final String safePath = 'signage_media/$clientId/$fileName';

      // We pass the stream directly to Minio, chunk by chunk
      await _minio.putObject(
        _bucketName,
        safePath,
        fileStream,
        size: fileSize,
      );

      return 'https://$_bucketName.s3.eu-central-003.backblazeb2.com/$safePath';
    } catch (e) {
      print('Backblaze Stream Upload Error: $e');
      return null;
    }
  }

  /// Documentation:
  /// 🗑️ Permanently deletes a file from Backblaze B2 to save server costs!
  Future<bool> deleteMedia(String fileName, String clientId) async {
    try {
      final String safePath = 'signage_media/$clientId/$fileName';
      await _minio.removeObject(_bucketName, safePath);
      print('✅ Successfully deleted $fileName from Backblaze B2');
      return true;
    } catch (e) {
      print('❌ Backblaze Delete Error: $e');
      return false;
    }
  }
}