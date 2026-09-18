import 'package:firebase_database/firebase_database.dart';

class LocationRtdbService {
  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

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
          'updatedAt': data['updatedAt'],
        };
      }
    } catch (_) {}
    return null;
  }
}
