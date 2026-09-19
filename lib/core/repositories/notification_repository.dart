import 'dart:async';
import '../network/api_client.dart';

class NotificationRepository {
  final AstraApiClient _apiClient;

  NotificationRepository({AstraApiClient? apiClient})
      : _apiClient = apiClient ?? AstraApiClient();

  Future<void> registerDeviceToken({
    required String deviceId,
    required String platform,
    required String fcmToken,
    String? appVersion,
  }) async {
    await _apiClient.registerDevice(
      deviceId: deviceId,
      platform: platform,
      fcmToken: fcmToken,
      appVersion: appVersion,
    );
  }

  Future<void> unregisterDevice(String deviceId) async {
    await _apiClient.removeDevice(deviceId);
  }
}
