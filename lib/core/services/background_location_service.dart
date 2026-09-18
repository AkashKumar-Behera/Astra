import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../../firebase_options.dart';
import 'location_rtdb_service.dart';

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
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      await Workmanager().registerPeriodicTask(
        'astra_periodic_location_sync',
        kBackgroundLocationTask,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }
}
