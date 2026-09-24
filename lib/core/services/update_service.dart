import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
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
  final bool isIOS;

  UpdateInfo({
    required this.hasUpdate,
    this.isBeta = false,
    required this.latestVersion,
    required this.currentVersion,
    this.releaseNotes,
    this.apkDownloadUrl,
    this.releasePageUrl,
    this.isIOS = false,
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
  /// Detects device ABI (64-bit vs 32-bit vs iOS) to select exact download asset.
  static Future<UpdateInfo?> checkForUpdate({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.20"
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

        String? downloadUrl;
        final isIOSDevice = Platform.isIOS;

        if (isIOSDevice) {
          downloadUrl = 'https://astra.croto.in';
        } else {
          final assets = selectedRelease['assets'] as List<dynamic>?;
          if (assets != null && assets.isNotEmpty) {
            List<String> abis = [];
            if (Platform.isAndroid) {
              try {
                final androidInfo = await DeviceInfoPlugin().androidInfo;
                abis = androidInfo.supportedAbis;
              } catch (_) {}
            }

            final is64Bit = abis.any((a) => a.contains('arm64') || a.contains('x86_64') || a.contains('64'));
            final is32Bit = abis.any((a) => a.contains('armeabi') || a.contains('v7a') || a.contains('32'));

            String? arm64Url;
            String? arm32Url;
            String? universalUrl;
            String? anyApkUrl;

            for (var asset in assets) {
              final name = (asset['name'] as String? ?? '').toLowerCase();
              final url = asset['browser_download_url'] as String?;
              if (name.endsWith('.apk') && url != null) {
                anyApkUrl ??= url;
                if (name.contains('arm64-v8a') || name.contains('arm64')) {
                  arm64Url = url;
                } else if (name.contains('armeabi-v7a') || name.contains('v7a')) {
                  arm32Url = url;
                } else if (name.contains('release.apk') || name.contains('universal')) {
                  universalUrl = url;
                }
              }
            }

            if (is64Bit && arm64Url != null) {
              downloadUrl = arm64Url;
            } else if (is32Bit && arm32Url != null) {
              downloadUrl = arm32Url;
            } else {
              downloadUrl = universalUrl ?? arm64Url ?? arm32Url ?? anyApkUrl ?? htmlUrl;
            }
          }
        }

        final isNewer = _compareVersions(cleanTag, currentVersion) > 0;

        return UpdateInfo(
          hasUpdate: isNewer,
          isBeta: isBetaRelease,
          latestVersion: cleanTag.isNotEmpty ? cleanTag : currentVersion,
          currentVersion: currentVersion,
          releaseNotes: releaseNotes,
          apkDownloadUrl: downloadUrl ?? htmlUrl,
          releasePageUrl: htmlUrl,
          isIOS: isIOSDevice,
        );
      }
    } catch (_) {}
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
