import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../firebase_options.dart';
import 'location_rtdb_service.dart';
import 'websocket_service.dart';

const String kBackgroundLocationTask = 'astra_background_location_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return Future.value(true);
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return Future.value(true);
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return Future.value(true);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      await LocationRtdbService.updateLocation(
        uid: user.uid,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {}

    return Future.value(true);
  });
}

class BackgroundLocationManager {
  static StreamSubscription<Position>? _continuousStreamSub;

  /// Start persistent live background location tracking
  ///
  /// - Android: Uses Android Foreground Service with persistent status notification
  ///   to ensure OS never kills the GPS stream when minimized or screen locked.
  /// - iOS: Uses AppleSettings with `allowBackgroundLocationUpdates: true` and
  ///   `showBackgroundLocationIndicator: true` to keep GPS and network alive.
  static Future<void> startContinuousTracking(String uid) async {
    await stopContinuousTracking();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      late final LocationSettings settings;

      if (Platform.isAndroid) {
        settings = AndroidSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 15,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 20),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: '✦ Astra Orbit Active',
            notificationText: 'Live location syncing with partner',
            enableWakeLock: false,
            notificationIcon: AndroidResource(name: 'ic_notification'),
          ),
        );
      } else if (Platform.isIOS) {
        settings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        settings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
      }

      _continuousStreamSub = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen((position) async {
        try {
          await LocationRtdbService.updateLocation(
            uid: uid,
            latitude: position.latitude,
            longitude: position.longitude,
          );

          WebSocketService.sendLocationUpdate(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          );
        } catch (e) {
          debugPrint('Error writing live background coordinates: $e');
        }
      }, onError: (err) {
        debugPrint('Geolocator position stream error: $err');
      });
    } catch (e) {
      debugPrint('BackgroundLocationManager.startContinuousTracking error: $e');
    }
  }

  /// Stop continuous tracking stream
  static Future<void> stopContinuousTracking() async {
    await _continuousStreamSub?.cancel();
    _continuousStreamSub = null;
  }

  /// Initialize periodic Workmanager fallback (Android only)
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        'astra_periodic_location_sync',
        kBackgroundLocationTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {}
  }
}
