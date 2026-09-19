import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../features/chat/chat_screen.dart';
import '../network/api_client.dart';
import '../repositories/notification_repository.dart';
import 'chat_service.dart';

/// Top-level background message handler required by firebase_messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Silent / background notification receipt
  // Plaintext is NEVER in the payload. Only routing metadata is received.
}

/// NotificationService
///
/// Production FCM Push Notification infrastructure for Astra Chat using the Astra VPS Backend.
///
/// Features:
/// - Secure per-user device token registration via `POST /api/v1/devices`
/// - Token refresh lifecycle synchronization
/// - Token cleanup upon sign out
/// - Safe notification payload routing (verifies participant identity before navigating)
/// - Zero plaintext message content or encryption keys in notification payloads
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final AstraApiClient _apiClient = AstraApiClient(
    tokenProvider: () async => _auth.currentUser?.getIdToken(),
  );
  static final NotificationRepository _notifRepo = NotificationRepository(apiClient: _apiClient);

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Initialize FCM listeners, permissions, and token registration
  static Future<void> initialize() async {
    try {
      // 1. Request notification permissions (iOS / Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      // 2. Set background message handler (Android only; iOS uses APNs background processing)
      if (Platform.isAndroid) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        } catch (_) {}
      }

      // 3. Register current device token if user is signed in
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await registerDeviceToken(currentUser.uid);
      }

      // 4. Listen to token refreshes
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          await _saveDeviceToken(uid, newToken);
        }
      });

      // 5. Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Foreground notification received - UI updates naturally via WebSocket
      });

      // 6. Handle notification click when app is opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        handleNotificationRouting(message.data);
      });

      // 7. Handle notification click when app was launched from terminated state
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        handleNotificationRouting(initialMessage.data);
      }
    } catch (e) {
      debugPrint('NotificationService.initialize ignored non-fatal error: $e');
    }
  }

  /// Get stable unique hardware/app device ID
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return 'android_${androidInfo.id}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return 'ios_${iosInfo.identifierForVendor ?? "unknown"}';
    }
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Register current device token with VPS
  static Future<void> registerDeviceToken(String uid) async {
    try {
      if (Platform.isIOS) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) return;
      }
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _saveDeviceToken(uid, token);
    } catch (_) {}
  }

  static Future<void> _saveDeviceToken(String uid, String token) async {
    try {
      final deviceId = await getDeviceId();
      await _notifRepo.registerDeviceToken(
        deviceId: deviceId,
        platform: Platform.operatingSystem,
        fcmToken: token,
      );
    } catch (_) {}
  }

  /// Remove current device token upon user logout
  static Future<void> unregisterDeviceToken(String uid) async {
    try {
      final deviceId = await getDeviceId();
      await _notifRepo.unregisterDevice(deviceId);
    } catch (_) {}
  }

  /// Validate notification payload and route to the correct conversation
  static Future<void> handleNotificationRouting(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (type != 'chat_message' && type != 'chat.message') return;

    final conversationId = (data['conversationId'] ?? data['conversation_id']) as String?;
    final senderId = (data['senderId'] ?? data['sender_id']) as String?;
    final currentUid = _auth.currentUser?.uid;

    if (conversationId == null || senderId == null || currentUid == null) {
      return;
    }

    // Security validation: verify current user is a participant using canonical ID
    final expectedConvId = ChatService.getConversationId(currentUid, senderId);
    if (conversationId != expectedConvId) {
      return;
    }

    final partnerName = (data['sender_name'] as String?) ?? 'Friend';

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          partnerUid: senderId,
          partnerName: partnerName,
        ),
      ),
    );
  }

  /// Build standard generic FCM notification payload
  static Map<String, dynamic> buildGenericNotificationPayload({
    required String conversationId,
    required String senderId,
    required String messageId,
    String title = 'New message',
    String body = 'You received a new Astra encrypted message.',
  }) {
    return {
      'notification': {
        'title': title,
        'body': body,
      },
      'data': {
        'type': 'chat_message',
        'conversationId': conversationId,
        'senderId': senderId,
        'messageId': messageId,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    };
  }

  /// Dispose listeners
  static void dispose() {
    _tokenRefreshSub?.cancel();
  }
}
