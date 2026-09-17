import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final bool hasUpdate;
  final bool isBeta;
  final String latestVersion;
  final String currentVersion;
  final String? releaseNotes;
  final String? apkDownloadUrl;
  final String? releasePageUrl;

  UpdateInfo({
    required this.hasUpdate,
    this.isBeta = false,
    required this.latestVersion,
    required this.currentVersion,
    this.releaseNotes,
    this.apkDownloadUrl,
    this.releasePageUrl,
  });
}

class UpdateService {
  static const String _githubRepo = 'AkashKumar-Behera/Astra';
  static const String _releasesListUrl =
      'https://api.github.com/repos/$_githubRepo/releases';
  static const String _betaTestingKey = 'include_beta_updates';

  /// Check if user has opted into beta testing updates
  static Future<bool> isBetaEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_betaTestingKey) ?? false;
  }

  /// Toggle beta testing channel
  static Future<void> setBetaEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_betaTestingKey, enabled);
  }

  /// Performs a fast check against GitHub Releases API with strict timeout.
  /// If beta is false: filters for stable releases only (ignoring pre-releases/beta tags).
  /// If beta is true: includes latest beta / pre-releases.
  static Future<UpdateInfo?> checkForUpdate({
    Duration timeout = const Duration(milliseconds: 1600),
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"
      final betaEnabled = await isBetaEnabled();

      final response = await http
          .get(
            Uri.parse(_releasesListUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final releases = jsonDecode(response.body) as List<dynamic>;
        if (releases.isEmpty) return null;

        Map<String, dynamic>? selectedRelease;

        for (var r in releases) {
          final isPrerelease = (r['prerelease'] as bool? ?? false);
          final tagName = (r['tag_name'] as String? ?? '').toLowerCase();
          final isBetaTag = isPrerelease ||
              tagName.contains('beta') ||
              tagName.contains('alpha') ||
              tagName.contains('dev');

          if (!betaEnabled && isBetaTag) {
            // User only wants stable releases, skip beta/dev tags
            continue;
          }

          selectedRelease = r as Map<String, dynamic>;
          break;
        }

        if (selectedRelease == null) return null;

        final rawTag = selectedRelease['tag_name'] as String? ?? '';
        final cleanTag = rawTag.replaceAll(RegExp(r'[^0-9.]'), '');
        final isBetaRelease = (selectedRelease['prerelease'] as bool? ?? false) ||
            rawTag.toLowerCase().contains('beta');
        final releaseNotes = selectedRelease['body'] as String? ?? '';
        final htmlUrl = selectedRelease['html_url'] as String? ?? '';

        String? apkUrl;
        final assets = selectedRelease['assets'] as List<dynamic>?;
        if (assets != null) {
          for (var asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String?;
              break;
            }
          }
        }

        final isNewer = _compareVersions(cleanTag, currentVersion) > 0;

        return UpdateInfo(
          hasUpdate: isNewer,
          isBeta: isBetaRelease,
          latestVersion: rawTag.isNotEmpty ? rawTag : currentVersion,
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
