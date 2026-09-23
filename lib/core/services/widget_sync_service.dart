import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class WidgetSyncService {
  static const String appGroupId = 'group.com.astra.always';

  // Android Widget Providers
  static const String friendDistanceWidgetProvider = 'FriendDistanceWidgetProvider';
  static const String partnerStatusWidgetProvider = 'PartnerStatusWidgetProvider';
  static const String pairOrbitWidgetProvider = 'PairOrbitWidgetProvider';

  static const String iosWidgetKind = 'FriendDistanceWidget';

  static String? _cachedFriendPhotoUrl;
  static String? _cachedFriendPhotoPath;
  static String? _cachedMyPhotoUrl;
  static String? _cachedMyPhotoPath;

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

  /// Download and cache profile image locally for widget consumption
  static Future<String?> _cacheImage(String? photoUrl, {required bool isMyProfile}) async {
    if (photoUrl == null || photoUrl.isEmpty) {
      return null;
    }

    if (isMyProfile) {
      if (photoUrl == _cachedMyPhotoUrl && _cachedMyPhotoPath != null) {
        final file = File(_cachedMyPhotoPath!);
        if (file.existsSync()) return _cachedMyPhotoPath;
      }
    } else {
      if (photoUrl == _cachedFriendPhotoUrl && _cachedFriendPhotoPath != null) {
        final file = File(_cachedFriendPhotoPath!);
        if (file.existsSync()) return _cachedFriendPhotoPath;
      }
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filename = isMyProfile ? 'widget_my_avatar.png' : 'widget_friend_avatar.png';
      final targetPath = '${directory.path}/$filename';
      final response = await http.get(Uri.parse(photoUrl)).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final file = File(targetPath);
        await file.writeAsBytes(response.bodyBytes);
        if (isMyProfile) {
          _cachedMyPhotoUrl = photoUrl;
          _cachedMyPhotoPath = targetPath;
        } else {
          _cachedFriendPhotoUrl = photoUrl;
          _cachedFriendPhotoPath = targetPath;
        }
        return targetPath;
      }
    } catch (e) {
      debugPrint('[WidgetSyncService] Error downloading widget avatar: $e');
    }
    return null;
  }

  /// Update all Astra widgets with latest details and telemetry
  static Future<void> updateAllWidgets({
    required String friendName,
    String? friendPhotoUrl,
    double? myLat,
    double? myLng,
    double? friendLat,
    double? friendLng,
    String? friendStatus,
    int? friendBattery,
    String? friendNetwork,
    String? myName,
    String? myPhotoUrl,
    int? myBattery,
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

      final friendPhotoPath = await _cacheImage(friendPhotoUrl, isMyProfile: false);
      final myPhotoPath = await _cacheImage(myPhotoUrl, isMyProfile: true);

      // Save Friend / Partner Info
      await HomeWidget.saveWidgetData<String>('friend_name', friendName);
      await HomeWidget.saveWidgetData<String>('friend_distance', distanceStr);
      await HomeWidget.saveWidgetData<String>(
        'friend_status',
        friendStatus ?? 'Astra Live',
      );
      if (friendBattery != null) {
        await HomeWidget.saveWidgetData<String>('friend_battery', '🔋 $friendBattery%');
      }
      if (friendNetwork != null) {
        final netLabel = friendNetwork.toLowerCase() == 'wifi'
            ? '📶 Wi-Fi'
            : (friendNetwork.toLowerCase() == 'cellular' ? '📶 Mobile' : '📶 Offline');
        await HomeWidget.saveWidgetData<String>('friend_network', netLabel);
      }
      if (friendPhotoPath != null) {
        await HomeWidget.saveWidgetData<String>('friend_photo_path', friendPhotoPath);
      }

      // Save User (Self) Info
      if (myName != null && myName.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('my_name', myName);
      }
      if (myBattery != null) {
        await HomeWidget.saveWidgetData<String>('my_battery', '🔋 $myBattery%');
      }
      if (myPhotoPath != null) {
        await HomeWidget.saveWidgetData<String>('my_photo_path', myPhotoPath);
      }

      // Trigger update on Android & iOS providers
      await Future.wait([
        HomeWidget.updateWidget(
          name: friendDistanceWidgetProvider,
          iOSName: iosWidgetKind,
        ),
        HomeWidget.updateWidget(
          name: partnerStatusWidgetProvider,
        ),
        HomeWidget.updateWidget(
          name: pairOrbitWidgetProvider,
        ),
      ]);

      debugPrint('[WidgetSyncService] All widgets updated: $friendName ($distanceStr)');
    } catch (e) {
      debugPrint('[WidgetSyncService] Failed to update widgets: $e');
    }
  }

  /// Automatically sync active partner's location & telemetry to all native widgets
  static void syncFromPartnerData({
    required Map<String, dynamic> partnerData,
    required double? myLat,
    required double? myLng,
    Map<String, dynamic>? partnerTelemetry,
    Map<String, dynamic>? myData,
    int? myBattery,
  }) {
    final friendName = (partnerData['name'] as String?)?.trim().isNotEmpty == true
        ? (partnerData['name'] as String).trim()
        : ((partnerData['displayName'] as String?)?.trim().isNotEmpty == true
            ? (partnerData['displayName'] as String).trim()
            : ((partnerData['phoneNumber'] as String?) ?? 'Partner'));
    final friendPhotoUrl = partnerData['photoUrl'] as String?;
    final pLat = (partnerData['latitude'] as num?)?.toDouble();
    final pLng = (partnerData['longitude'] as num?)?.toDouble();

    final friendBattery = (partnerTelemetry?['battery'] as num?)?.toInt();
    final friendNetwork = partnerTelemetry?['network'] as String?;

    final myName = (myData?['name'] as String?) ?? (myData?['displayName'] as String?) ?? 'You';
    final myPhotoUrl = myData?['photoUrl'] as String?;

    updateAllWidgets(
      friendName: friendName,
      friendPhotoUrl: friendPhotoUrl,
      myLat: myLat,
      myLng: myLng,
      friendLat: pLat,
      friendLng: pLng,
      friendBattery: friendBattery,
      friendNetwork: friendNetwork,
      myName: myName,
      myPhotoUrl: myPhotoUrl,
      myBattery: myBattery,
    );
  }
}
