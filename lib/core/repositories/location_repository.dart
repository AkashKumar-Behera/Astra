import 'dart:async';
import '../network/api_client.dart';
import '../network/websocket_client.dart';

class LocationRefreshResult {
  final bool isFresh;
  final bool isSuccess;
  final double? latitude;
  final double? longitude;
  final int? updatedAt;
  final String statusLabel;

  const LocationRefreshResult({
    required this.isFresh,
    required this.isSuccess,
    this.latitude,
    this.longitude,
    this.updatedAt,
    required this.statusLabel,
  });
}

class LocationRepository {
  final AstraApiClient _apiClient;
  final AstraWebSocketClient? _wsClient;

  static const Duration liveThreshold = Duration(minutes: 3);

  final Map<String, StreamController<Map<String, dynamic>>> _locationStreams = {};
  StreamSubscription? _wsLocationSub;

  LocationRepository({
    AstraApiClient? apiClient,
    AstraWebSocketClient? wsClient,
  })  : _apiClient = apiClient ?? AstraApiClient(),
        _wsClient = wsClient {
    _initWsListener();
  }

  void _initWsListener() {
    if (_wsClient != null) {
      _wsLocationSub = _wsClient.on('location.response').listen((event) {
        final payload = event.payload;
        final uid = payload['user_id'] as String?;
        if (uid != null && _locationStreams.containsKey(uid)) {
          _locationStreams[uid]!.add(payload);
        }
      });
    }
  }

  static bool isLocationFresh(int? updatedAtMillis, {Duration threshold = liveThreshold}) {
    if (updatedAtMillis == null || updatedAtMillis <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - updatedAtMillis;
    return diff >= 0 && diff <= threshold.inMilliseconds;
  }

  static String formatLocationFreshness(int? updatedAtMillis) {
    if (updatedAtMillis == null || updatedAtMillis <= 0) {
      return 'Location unavailable';
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMillis = now - updatedAtMillis;

    if (diffMillis < 0) {
      return 'Live • Just now';
    }

    final diffSeconds = diffMillis ~/ 1000;
    if (diffSeconds < 60) {
      return 'Live • Just now';
    }

    final diffMinutes = diffSeconds ~/ 60;
    if (diffMinutes < 3) {
      return 'Live • ${diffMinutes}m ago';
    } else if (diffMinutes < 60) {
      return 'Last Known • ${diffMinutes}m ago';
    }

    final diffHours = diffMinutes ~/ 60;
    if (diffHours < 24) {
      return 'Last Known • ${diffHours}h ago';
    }

    final diffDays = diffHours ~/ 24;
    return 'Last Known • ${diffDays}d ago';
  }

  /// Update current user location via REST / WebSocket
  Future<Map<String, dynamic>> updateLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? deviceId,
  }) async {
    if (_wsClient != null && _wsClient.isConnected) {
      _wsClient.sendEnvelope('location.update', {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (deviceId != null) 'device_id': deviceId,
      });
    }
    return await _apiClient.updateLocation(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      deviceId: deviceId,
    );
  }

  /// Get partner's last known location
  Future<Map<String, dynamic>?> getPartnerLocation(String partnerUid) async {
    try {
      final loc = await _apiClient.getUserLocation(partnerUid);
      if (loc != null) {
        final updatedAtRaw = loc['updated_at'];
        int? updatedAt;
        if (updatedAtRaw is String) {
          updatedAt = DateTime.tryParse(updatedAtRaw)?.millisecondsSinceEpoch;
        } else if (updatedAtRaw is num) {
          updatedAt = updatedAtRaw.toInt();
        }

        return {
          'latitude': (loc['latitude'] as num?)?.toDouble(),
          'longitude': (loc['longitude'] as num?)?.toDouble(),
          'updatedAt': updatedAt,
        };
      }
    } catch (_) {}
    return null;
  }

  /// Request fresh location and await response with timeout
  Future<LocationRefreshResult> refreshPartnerLocation({
    required String partnerUid,
    required String myUid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final initial = await getPartnerLocation(partnerUid);
    final initialUpdatedAt = initial?['updatedAt'] as int?;

    // Send location request via WebSocket if available
    if (_wsClient != null && _wsClient.isConnected) {
      _wsClient.sendEnvelope('location.request', {
        'target_user_id': partnerUid,
      });
    }

    // Return current known location with honest freshness indicator
    final lat = initial?['latitude'] as double?;
    final lng = initial?['longitude'] as double?;
    final fresh = isLocationFresh(initialUpdatedAt);

    return LocationRefreshResult(
      isFresh: fresh,
      isSuccess: initial != null,
      latitude: lat,
      longitude: lng,
      updatedAt: initialUpdatedAt,
      statusLabel: formatLocationFreshness(initialUpdatedAt),
    );
  }

  /// Send Miss You notification to friend
  Future<void> sendMissYou(String friendId) async {
    if (_wsClient != null && _wsClient.isConnected) {
      _wsClient.sendEnvelope('miss_you.send', {'friend_id': friendId});
    }
    await _apiClient.sendMissYou(friendId);
  }

  Stream<Map<String, dynamic>> streamPartnerLocation(String partnerUid) {
    final controller = _locationStreams.putIfAbsent(
      partnerUid,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );

    // Initial fetch
    getPartnerLocation(partnerUid).then((loc) {
      if (loc != null && !controller.isClosed) {
        controller.add(loc);
      }
    });

    return controller.stream;
  }

  void dispose() {
    _wsLocationSub?.cancel();
    for (final c in _locationStreams.values) {
      c.close();
    }
    _locationStreams.clear();
  }
}
