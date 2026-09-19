import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

/// Result of an explicit partner location refresh attempt
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

class LocationRtdbService {
  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  static StreamSubscription<DatabaseEvent>? _locationRequestSub;

  /// Default threshold for considering a location "Live" (3 minutes)
  static const Duration liveThreshold = Duration(minutes: 3);

  /// Determine if a location timestamp is considered fresh/live
  static bool isLocationFresh(int? updatedAtMillis, {Duration threshold = liveThreshold}) {
    if (updatedAtMillis == null || updatedAtMillis <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - updatedAtMillis;
    return diff >= 0 && diff <= threshold.inMilliseconds;
  }

  /// Format location timestamp into honest, human-readable freshness label
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

  /// Update current user's live coordinates in RTDB
  static Future<void> updateLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final ref = _rtdb.ref('locations/$uid');
      await ref.set({
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  /// Listen to partner's live coordinates via RTDB stream
  static Stream<DatabaseEvent> streamPartnerLocation(String partnerUid) {
    return _rtdb.ref('locations/$partnerUid').onValue;
  }

  /// One-time fetch of partner coordinates from RTDB
  static Future<Map<String, dynamic>?> getPartnerLocation(String partnerUid) async {
    try {
      final snap = await _rtdb.ref('locations/$partnerUid').get();
      if (snap.exists && snap.value != null) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        return {
          'latitude': (data['latitude'] as num?)?.toDouble(),
          'longitude': (data['longitude'] as num?)?.toDouble(),
          'updatedAt': (data['updatedAt'] as num?)?.toInt(),
        };
      }
    } catch (_) {}
    return null;
  }

  /// Request a partner to update their location by writing a ping request to `/location_requests/{partnerUid}`
  static Future<void> sendLocationRequest({
    required String targetUid,
    required String requestedByUid,
  }) async {
    try {
      final ref = _rtdb.ref('location_requests/$targetUid');
      await ref.set({
        'requestedBy': requestedByUid,
        'timestamp': ServerValue.timestamp,
        'requestId': 'req_${DateTime.now().millisecondsSinceEpoch}',
      });
    } catch (_) {}
  }

  /// Perform a full Refresh Location flow:
  /// 1. Immediately read partner's latest known RTDB location
  /// 2. Send a location request ping to partner
  /// 3. Wait up to `timeout` for a fresh location timestamp
  /// 4. Return result with honest status
  static Future<LocationRefreshResult> refreshPartnerLocation({
    required String partnerUid,
    required String myUid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final initial = await getPartnerLocation(partnerUid);
    final initialUpdatedAt = initial?['updatedAt'] as int?;

    // Send the location request ping
    await sendLocationRequest(targetUid: partnerUid, requestedByUid: myUid);

    // Wait for a fresh timestamp from the stream
    final completer = Completer<LocationRefreshResult>();

    final sub = streamPartnerLocation(partnerUid).listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final lat = (data['latitude'] as num?)?.toDouble();
          final lng = (data['longitude'] as num?)?.toDouble();
          final updated = (data['updatedAt'] as num?)?.toInt();

          if (updated != null && (initialUpdatedAt == null || updated > initialUpdatedAt)) {
            if (!completer.isCompleted) {
              completer.complete(
                LocationRefreshResult(
                  isFresh: isLocationFresh(updated),
                  isSuccess: true,
                  latitude: lat,
                  longitude: lng,
                  updatedAt: updated,
                  statusLabel: formatLocationFreshness(updated),
                ),
              );
            }
          }
        } catch (_) {}
      }
    });

    try {
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          // Timeout occurred: return last known location without claiming it's live
          final lat = initial?['latitude'] as double?;
          final lng = initial?['longitude'] as double?;
          final updated = initialUpdatedAt;
          final fresh = isLocationFresh(updated);

          return LocationRefreshResult(
            isFresh: fresh,
            isSuccess: false,
            latitude: lat,
            longitude: lng,
            updatedAt: updated,
            statusLabel: formatLocationFreshness(updated),
          );
        },
      );
      await sub.cancel();
      return result;
    } catch (_) {
      await sub.cancel();
      return LocationRefreshResult(
        isFresh: isLocationFresh(initialUpdatedAt),
        isSuccess: false,
        latitude: initial?['latitude'] as double?,
        longitude: initial?['longitude'] as double?,
        updatedAt: initialUpdatedAt,
        statusLabel: formatLocationFreshness(initialUpdatedAt),
      );
    }
  }

  /// Start listening for incoming location requests targeted to current user.
  /// When a ping is received, automatically updates RTDB with fresh GPS coordinates.
  static void startLocationRequestListener(String myUid) {
    _locationRequestSub?.cancel();
    _locationRequestSub = _rtdb.ref('location_requests/$myUid').onValue.listen((event) async {
      if (event.snapshot.value != null) {
        try {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final timestamp = (data['timestamp'] as num?)?.toInt();

          // Only respond to recent requests (last 30 seconds)
          if (timestamp != null) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if ((now - timestamp).abs() < 30000) {
              final permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.always ||
                  permission == LocationPermission.whileInUse) {
                final pos = await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.medium,
                    timeLimit: Duration(seconds: 8),
                  ),
                );
                await updateLocation(
                  uid: myUid,
                  latitude: pos.latitude,
                  longitude: pos.longitude,
                );
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  /// Stop location request listener
  static void disposeLocationRequestListener() {
    _locationRequestSub?.cancel();
    _locationRequestSub = null;
  }
}
