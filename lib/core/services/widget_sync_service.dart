import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class WidgetSyncService {
  static const String appGroupId = 'group.com.astra.always';
  static const String androidWidgetProvider = 'FriendDistanceWidgetProvider';
  static const String iosWidgetKind = 'FriendDistanceWidget';

  static String? _cachedPhotoUrl;
  static String? _cachedPhotoLocalPath;

  /// Initialize HomeWidget settings
  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (e) {
      debugPrint('[WidgetSyncService] Init error: $e');
    }
  }

  /// Format distance between user and friend
  static String formatDistance(double meters) {
    if (meters < 0) return '-- km';
    if (meters < 1000) {
      return '${meters.round()} m away';
    } else {
      final km = meters / 1000.0;
      if (km < 10) {
        return '${km.toStringAsFixed(1)} km away';
      } else {
        return '${km.round()} km away';
      }
    }
  }

  /// Download and cache friend profile image locally for widget consumption
  static Future<String?> _cacheFriendImage(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) {
      return null;
    }

    if (photoUrl == _cachedPhotoUrl && _cachedPhotoLocalPath != null) {
      final file = File(_cachedPhotoLocalPath!);
      if (file.existsSync()) return _cachedPhotoLocalPath;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final targetPath = '${directory.path}/widget_avatar.png';
      final response = await http.get(Uri.parse(photoUrl)).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final file = File(targetPath);
        await file.writeAsBytes(response.bodyBytes);
        _cachedPhotoUrl = photoUrl;
        _cachedPhotoLocalPath = targetPath;
        return targetPath;
      }
    } catch (e) {
      debugPrint('[WidgetSyncService] Error downloading widget avatar: $e');
    }
    return null;
  }

  /// Update widget with latest friend details and location coordinates
  static Future<void> updateFriendDistanceWidget({
    required String friendName,
    String? photoUrl,
    double? myLat,
    double? myLng,
    double? friendLat,
    double? friendLng,
    String? freshnessStatus,
  }) async {
    try {
      String distanceStr = '-- km';
      if (myLat != null && myLng != null && friendLat != null && friendLng != null) {
        final double distanceMeters = Geolocator.distanceBetween(
          myLat,
          myLng,
          friendLat,
          friendLng,
        );
        distanceStr = formatDistance(distanceMeters);
      }

      final localPhotoPath = await _cacheFriendImage(photoUrl);

      // Save key-values to native shared storage
      await HomeWidget.saveWidgetData<String>('friend_name', friendName);
      await HomeWidget.saveWidgetData<String>('friend_distance', distanceStr);
      await HomeWidget.saveWidgetData<String>(
        'friend_status',
        freshnessStatus ?? 'Astra Live',
      );
      if (localPhotoPath != null) {
        await HomeWidget.saveWidgetData<String>('friend_photo_path', localPhotoPath);
      }

      // Trigger update on Android & iOS
      await HomeWidget.updateWidget(
        name: androidWidgetProvider,
        iOSName: iosWidgetKind,
      );
      debugPrint('[WidgetSyncService] Widget updated: $friendName -> $distanceStr');
    } catch (e) {
      debugPrint('[WidgetSyncService] Failed to update widget: $e');
    }
  }

  /// Automatically sync active partner's location to native widget
  static void syncFromPartnerData({
    required Map<String, dynamic> partnerData,
    required double? myLat,
    required double? myLng,
  }) {
    final name = (partnerData['name'] as String?)?.trim().isNotEmpty == true
        ? (partnerData['name'] as String).trim()
        : ((partnerData['displayName'] as String?)?.trim().isNotEmpty == true
            ? (partnerData['displayName'] as String).trim()
            : ((partnerData['phoneNumber'] as String?) ?? 'Friend'));
    final photoUrl = partnerData['photoUrl'] as String?;
    final pLat = (partnerData['latitude'] as num?)?.toDouble();
    final pLng = (partnerData['longitude'] as num?)?.toDouble();

    updateFriendDistanceWidget(
      friendName: name,
      photoUrl: photoUrl,
      myLat: myLat,
      myLng: myLng,
      friendLat: pLat,
      friendLng: pLng,
    );
  }
}
