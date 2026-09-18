import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';

class TelemetryService {
  static final Battery _battery = Battery();
  static final Connectivity _connectivity = Connectivity();
  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  static StreamSubscription? _batterySub;
  static StreamSubscription? _connectivitySub;

  /// Starts listening to device battery and network state and syncs to RTDB
  static void startTelemetrySync(String uid) {
    _batterySub?.cancel();
    _connectivitySub?.cancel();

    _updateTelemetry(uid);

    // Battery state changes
    _batterySub = _battery.onBatteryStateChanged.listen((_) {
      _updateTelemetry(uid);
    });

    // Connectivity changes
    _connectivitySub = _connectivity.onConnectivityChanged.listen((_) {
      _updateTelemetry(uid);
    });
  }

  static Future<void> _updateTelemetry(String uid) async {
    try {
      int batteryLevel = 100;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      final connectivityResult = await _connectivity.checkConnectivity();
      String networkType = 'wifi';
      if (connectivityResult.contains(ConnectivityResult.mobile)) {
        networkType = 'cellular';
      } else if (connectivityResult.contains(ConnectivityResult.wifi)) {
        networkType = 'wifi';
      } else if (connectivityResult.contains(ConnectivityResult.none)) {
        networkType = 'none';
      }

      await _rtdb.ref('telemetry/$uid').update({
        'battery': batteryLevel,
        'network': networkType,
        'isOnline': networkType != 'none',
        'lastActive': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  static Stream<DatabaseEvent> streamPartnerTelemetry(String partnerUid) {
    return _rtdb.ref('telemetry/$partnerUid').onValue;
  }

  static void dispose() {
    _batterySub?.cancel();
    _connectivitySub?.cancel();
  }
}
