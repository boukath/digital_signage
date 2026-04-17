// File: lib/features/client_dashboard/data/b2_storage_service.dart

import 'dart:typed_data';
import 'package:minio/minio.dart';

/// Documentation:
/// This service handles uploading heavy media (Images/MP4s) directly to Backblaze B2.
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
  /// Uploads a file to Backblaze B2 and returns the public URL so the Kiosk can play it.
  Future<String?> uploadMedia(String fileName, Uint8List fileBytes, String clientId) async {
    try {
      // 1. Organize files in the bucket by the client's ID so they don't mix up
      final String safePath = 'signage_media/$clientId/$fileName';

      // 2. Upload the raw bytes to Backblaze
      await _minio.putObject(
        _bucketName,
        safePath,
        Stream.value(fileBytes),
      );

      // 3. Generate the public URL so our physical screens can download it later
      final String publicUrl = 'https://$_bucketName.s3.eu-central-003.backblazeb2.com/$safePath';
      return publicUrl;

    } catch (e) {
      print('Backblaze Upload Error: $e');
      return null;
    }
  }
}