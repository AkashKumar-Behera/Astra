import 'dart:async';
import '../network/api_client.dart';
import '../repositories/location_repository.dart';

export '../repositories/location_repository.dart' show LocationRefreshResult;

class LocationRtdbService {
  static final AstraApiClient _apiClient = AstraApiClient();
  static final LocationRepository _locationRepo = LocationRepository(apiClient: _apiClient);

  /// Default threshold for considering a location "Live" (3 minutes)
  static const Duration liveThreshold = LocationRepository.liveThreshold;

  /// Determine if a location timestamp is considered fresh/live
  static bool isLocationFresh(int? updatedAtMillis, {Duration threshold = liveThreshold}) {
    return LocationRepository.isLocationFresh(updatedAtMillis, threshold: threshold);
  }

  /// Format location timestamp into honest, human-readable freshness label
  static String formatLocationFreshness(int? updatedAtMillis) {
    return LocationRepository.formatLocationFreshness(updatedAtMillis);
  }

  /// Update current user's live coordinates on the VPS
  static Future<void> updateLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _locationRepo.updateLocation(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {}
  }

  /// Listen to partner's live coordinates via stream
  static Stream<Map<String, dynamic>> streamPartnerLocation(String partnerUid) {
    return _locationRepo.streamPartnerLocation(partnerUid);
  }

  /// One-time fetch of partner coordinates from VPS
  static Future<Map<String, dynamic>?> getPartnerLocation(String partnerUid) async {
    return await _locationRepo.getPartnerLocation(partnerUid);
  }

  /// Request a partner to update their location
  static Future<void> sendLocationRequest({
    required String targetUid,
    required String requestedByUid,
  }) async {
    try {
      await _locationRepo.refreshPartnerLocation(
        partnerUid: targetUid,
        myUid: requestedByUid,
      );
    } catch (_) {}
  }

  /// Perform a full Refresh Location flow:
  /// 1. Immediately reads partner's latest known VPS location
  /// 2. Returns result with honest freshness status
  static Future<LocationRefreshResult> refreshPartnerLocation({
    required String partnerUid,
    required String myUid,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return await _locationRepo.refreshPartnerLocation(
      partnerUid: partnerUid,
      myUid: myUid,
      timeout: timeout,
    );
  }

  /// Start listening for incoming location requests
  static void startLocationRequestListener(String myUid) {
    // Handled seamlessly via AstraWebSocketClient
  }

  /// Stop location request listener
  static void disposeLocationRequestListener() {
    // Handled seamlessly via AstraWebSocketClient
  }
}
