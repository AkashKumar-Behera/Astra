import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final String? releaseNotes;
  final String? apkDownloadUrl;
  final String? releasePageUrl;

  UpdateInfo({
    required this.hasUpdate,
    required this.latestVersion,
    required this.currentVersion,
    this.releaseNotes,
    this.apkDownloadUrl,
    this.releasePageUrl,
  });
}

class UpdateService {
  static const String _githubRepo = 'AkashKumar-Behera/Astra';
  static const String _releasesApiUrl =
      'https://api.github.com/repos/$_githubRepo/releases/latest';

  /// Performs a fast check against GitHub Releases API with strict timeout.
  /// Does not block user if network is slow or offline.
  static Future<UpdateInfo?> checkForUpdate({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final response = await http
          .get(
            Uri.parse(_releasesApiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String? ?? '')
            .replaceAll(RegExp(r'[^0-9.]'), '');
        final releaseNotes = data['body'] as String? ?? '';
        final htmlUrl = data['html_url'] as String? ?? '';

        String? apkUrl;
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null) {
          for (var asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
        }

        final isNewer = _compareVersions(tagName, currentVersion) > 0;

        return UpdateInfo(
          hasUpdate: isNewer,
          latestVersion: tagName.isNotEmpty ? tagName : currentVersion,
          currentVersion: currentVersion,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkUrl ?? htmlUrl,
          releasePageUrl: htmlUrl,
        );
      }
    } catch (_) {
      // Offline, timeout, or API rate limit: fail silently and proceed
    }
    return null;
  }

  /// Returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  static int _compareVersions(String v1, String v2) {
    try {
      final v1Parts = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final v2Parts = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = v1Parts.length > v2Parts.length ? v1Parts.length : v2Parts.length;
      for (int i = 0; i < maxLen; i++) {
        final p1 = i < v1Parts.length ? v1Parts[i] : 0;
        final p2 = i < v2Parts.length ? v2Parts[i] : 0;
        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }
    } catch (_) {}
    return 0;
  }
}
