import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class TelemetryData {
  final int battery;
  final String network;
  final bool isOnline;
  final int? lastActive;

  const TelemetryData({
    required this.battery,
    required this.network,
    required this.isOnline,
    this.lastActive,
  });
}

class TelemetryService {
  static final Battery _battery = Battery();
  static final Connectivity _connectivity = Connectivity();
  static StreamSubscription? _batterySub;
  static StreamSubscription? _connectivitySub;
  static final Map<String, StreamController<TelemetryData>> _partnerTelemetryStreams = {};

  /// Starts listening to device battery and network state
  static void startTelemetrySync(String uid) {
    _batterySub?.cancel();
    _connectivitySub?.cancel();

    _updateTelemetry(uid);

    _batterySub = _battery.onBatteryStateChanged.listen((_) {
      _updateTelemetry(uid);
    });

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

      final data = TelemetryData(
        battery: batteryLevel,
        network: networkType,
        isOnline: networkType != 'none',
        lastActive: DateTime.now().millisecondsSinceEpoch,
      );

      if (_partnerTelemetryStreams.containsKey(uid) && !_partnerTelemetryStreams[uid]!.isClosed) {
        _partnerTelemetryStreams[uid]!.add(data);
      }
    } catch (_) {}
  }

  static Stream<TelemetryData> streamPartnerTelemetry(String partnerUid) {
    final controller = _partnerTelemetryStreams.putIfAbsent(
      partnerUid,
      () => StreamController<TelemetryData>.broadcast(),
    );
    return controller.stream;
  }

  static void dispose() {
    _batterySub?.cancel();
    _connectivitySub?.cancel();
    for (final c in _partnerTelemetryStreams.values) {
      c.close();
    }
    _partnerTelemetryStreams.clear();
  }
}
