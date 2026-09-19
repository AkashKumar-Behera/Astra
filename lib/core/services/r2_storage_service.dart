import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class R2StorageService {
  static const String _accountId = String.fromEnvironment(
    'R2_ACCOUNT_ID',
    defaultValue: 'f23f3e07dabd435ea66c31dc314b3984',
  );
  static const String _accessKeyId = String.fromEnvironment(
    'R2_ACCESS_KEY_ID',
    defaultValue: 'e667abb894140529feaefab073da0dc6',
  );
  static const String _secretAccessKey = String.fromEnvironment(
    'R2_SECRET_ACCESS_KEY',
    defaultValue: '95bbcff0c38f6f10603f20834296c2f0a568cf6c9afe078b8a0b64c9b145f74c',
  );
  static const String _bucketName = String.fromEnvironment('R2_BUCKET_NAME', defaultValue: 'r2bucket');
  static const String _publicUrl = String.fromEnvironment(
    'R2_PUBLIC_URL',
    defaultValue: 'https://pub-b286618087c54a10bbc88f75dade11a1.r2.dev',
  );

  /// Check whether R2 is configured in the environment
  static bool get isConfigured =>
      _accountId.isNotEmpty && _accessKeyId.isNotEmpty && _secretAccessKey.isNotEmpty;

  /// Upload file from File path to Cloudflare R2 and return the Public URL
  static Future<String?> uploadFile({
    required File file,
    required String remotePath,
    String? contentType,
  }) async {
    final bytes = await file.readAsBytes();
    return uploadBytes(
      bytes: bytes,
      remotePath: remotePath,
      contentType: contentType ?? _guessContentType(file.path),
    );
  }

  /// Upload raw bytes to Cloudflare R2 using AWS Signature Version 4
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String remotePath,
    String contentType = 'application/octet-stream',
  }) async {
    if (!isConfigured) {
      debugPrint('R2StorageService: R2 credentials missing in environment.');
      return null;
    }

    try {
      final sanitizedPath = remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
      final host = '$_accountId.r2.cloudflarestorage.com';
      final endpoint = 'https://$host/$_bucketName/$sanitizedPath';

      final now = DateTime.now().toUtc();
      final amzDate = _formatAmzDate(now);
      final dateStamp = _formatDateStamp(now);
      const region = 'auto';
      const service = 's3';

      final payloadHash = sha256.convert(bytes).toString();

      // Headers to sign
      final headers = <String, String>{
        'host': host,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': payloadHash,
        'content-type': contentType,
      };

      // Canonical URI and Query
      final canonicalUri = '/$_bucketName/$sanitizedPath';
      const canonicalQueryString = '';

      // Canonical Headers
      final sortedHeaderKeys = headers.keys.toList()..sort();
      final canonicalHeaders =
          sortedHeaderKeys.map((k) => '$k:${headers[k]!.trim()}\n').join();
      final signedHeaders = sortedHeaderKeys.join(';');

      final canonicalRequest = [
        'PUT',
        canonicalUri,
        canonicalQueryString,
        canonicalHeaders,
        signedHeaders,
        payloadHash,
      ].join('\n');

      final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();

      // String to Sign
      const algorithm = 'AWS4-HMAC-SHA256';
      final credentialScope = '$dateStamp/$region/$service/aws4_request';
      final stringToSign = [
        algorithm,
        amzDate,
        credentialScope,
        canonicalRequestHash,
      ].join('\n');

      // Signature Calculation
      final kDate = _hmacSha256(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
      final kRegion = _hmacSha256(kDate, region);
      final kService = _hmacSha256(kRegion, service);
      final kSigning = _hmacSha256(kService, 'aws4_request');
      final signature = _hmacSha256Hex(kSigning, stringToSign);

      final authorizationHeader =
          '$algorithm Credential=$_accessKeyId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';

      // Send HTTP PUT request to Cloudflare R2
      final response = await http.put(
        Uri.parse(endpoint),
        headers: {
          'Host': host,
          'x-amz-date': amzDate,
          'x-amz-content-sha256': payloadHash,
          'Content-Type': contentType,
          'Authorization': authorizationHeader,
        },
        body: bytes,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        final publicCdnUrl = '$_publicUrl/$sanitizedPath';
        debugPrint('R2 Upload Success: $publicCdnUrl');
        return publicCdnUrl;
      } else {
        debugPrint('R2 Upload Failed [${response.statusCode}]: ${response.body}');
        return null;
      }
    } catch (e, stack) {
      debugPrint('R2StorageService Upload Error: $e\n$stack');
      return null;
    }
  }

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  static String _hmacSha256Hex(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).toString();
  }

  static String _formatAmzDate(DateTime d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${twoDigits(d.month)}${twoDigits(d.day)}T${twoDigits(d.hour)}${twoDigits(d.minute)}${twoDigits(d.second)}Z';
  }

  static String _formatDateStamp(DateTime d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${twoDigits(d.month)}${twoDigits(d.day)}';
  }

  static String _guessContentType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
      case 'm4a':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
