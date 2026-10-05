import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

const String kBackgroundLocationTask = 'astra_background_location_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  // Empty dispatcher: Background periodic location polling is disabled to eliminate
  // device battery drain and overheating.
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}

/// BackgroundLocationManager
///
/// Continuous background GPS tracking has been completely disabled
/// to prevent device overheating and battery drain.
/// Location is now strictly on-demand:
/// 1. When the user launches or opens the app.
/// 2. When the user or partner manually triggers a refresh.
class BackgroundLocationManager {
  static StreamSubscription<Position>? _continuousStreamSub;

  /// Disabled to prevent device heating and high battery consumption.
  static Future<void> startContinuousTracking(String uid) async {
    await stopContinuousTracking();
  }

  /// Stop and cancel any existing continuous tracking stream
  static Future<void> stopContinuousTracking() async {
    await _continuousStreamSub?.cancel();
    _continuousStreamSub = null;
  }

  /// Cancel any previously scheduled background periodic tasks on Android
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    try {
      await Workmanager().cancelByUniqueName('astra_periodic_location_sync');
      await Workmanager().cancelAll();
    } catch (e) {
      debugPrint('Workmanager cancel error: $e');
    }
  }
}
