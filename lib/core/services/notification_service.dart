import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../../features/chat/chat_screen.dart';
import '../crypto/crypto_service.dart';
import 'chat_service.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Top-level background notification response handler for Direct Reply
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  // Handle direct inline reply from notification bar
  if (response.actionId == 'reply_action') {
    final replyText = response.input;
    if (replyText == null || replyText.trim().isEmpty) return;

    final payloadStr = response.payload;
    if (payloadStr == null) return;

    try {
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final conversationId = payload['conversationId'] as String?;
      final recipientId = payload['senderId'] as String?;

      if (conversationId != null && recipientId != null) {
        final chatService = ChatService();
        await chatService.sendMessage(
          conversationId: conversationId,
          recipientUid: recipientId,
          text: replyText.trim(),
        );

        // Cancel notification once reply is sent
        if (response.id != null) {
          await _localNotifications.cancel(id: response.id!);
        }
      }
    } catch (e) {
      debugPrint('Error sending inline notification reply: $e');
    }
  }
}

/// Top-level background message handler for FCM
///
/// Decrypts encrypted message payloads locally on device and displays
/// rich notifications with True Decrypted Text and Direct Reply action.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  final data = message.data;
  if (data['type'] != 'chat_message') return;

  final ciphertext = data['ciphertext'] as String?;
  final iv = data['iv'] as String?;
  final conversationId = data['conversationId'] as String?;
  final senderId = data['senderId'] as String?;
  final senderName = data['senderName'] as String? ?? 'Partner';
  final messageId = data['messageId'] as String? ?? '';
  final keyVersion = int.tryParse(data['keyVersion'] as String? ?? '1') ?? 1;

  String bodyText = 'New message received';

  if (ciphertext != null &&
      iv != null &&
      conversationId != null &&
      senderId != null) {
    try {
      final decrypted = await CryptoService.decryptMessage(
        ciphertextBase64: ciphertext,
        ivBase64: iv,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        keyVersion: keyVersion,
      );
      if (decrypted.isNotEmpty) {
        bodyText = decrypted;
      }
    } catch (e) {
      debugPrint('Background notification decryption fallback: $e');
      bodyText = 'New encrypted message';
    }
  }

  // Display rich local notification
  const androidDetails = AndroidNotificationDetails(
    'astra_chat_messages',
    'Astra Messages',
    channelDescription: 'End-to-end encrypted chat messages',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    icon: 'ic_notification',
    color: Color(0xFF6C5CE7),
    category: AndroidNotificationCategory.message,
    actions: [
      AndroidNotificationAction(
        'reply_action',
        'Reply',
        icon: DrawableResourceAndroidBitmap('ic_notification'),
        inputs: [
          AndroidNotificationActionInput(
            label: 'Type a message...',
          ),
        ],
      ),
    ],
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    categoryIdentifier: 'astra_chat_category',
  );

  const notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  final notifId = messageId.hashCode;
  final payloadJson = jsonEncode({
    'conversationId': conversationId,
    'senderId': senderId,
    'senderName': senderName,
    'type': 'chat_message',
  });

  await _localNotifications.show(
    id: notifId,
    title: senderName,
    body: bodyText,
    notificationDetails: notificationDetails,
    payload: payloadJson,
  );
}

/// Production NotificationService for Astra
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Initialize local notification plugins, FCM listeners, and tokens
  static Future<void> initialize() async {
    try {
      // 1. Initialize Flutter Local Notifications
      const androidInit = AndroidInitializationSettings('ic_notification');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null) {
            try {
              final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
              handleNotificationRouting(payload);
            } catch (_) {}
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      // 2. Create Android high priority notification channel
      if (Platform.isAndroid) {
        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              'astra_chat_messages',
              'Astra Messages',
              description: 'End-to-end encrypted chat messages',
              importance: Importance.max,
            ),
          );
        }
      }

      // 3. Request permissions (iOS and Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      // 4. Set FCM background handler
      if (Platform.isAndroid) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        } catch (_) {}
      }

      // 5. Register current device token
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await registerDeviceToken(currentUser.uid);
      }

      // 6. Listen to token refreshes
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          await _saveDeviceToken(uid, newToken);
        }
      });

      // 7. Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        // Trigger on-device local notification even if app is foregrounded
        await firebaseMessagingBackgroundHandler(message);
      });

      // 8. Handle notification click when app is opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        handleNotificationRouting(message.data);
      });

      // 9. Handle notification click when app was launched from terminated state
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

  /// Register device token with robust iOS APNs polling retry loop
  static Future<void> registerDeviceToken(String uid) async {
    try {
      if (Platform.isIOS) {
        // Wait up to 6 seconds for iOS APNs token to arrive from Apple
        String? apnsToken;
        for (int i = 0; i < 10; i++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) break;
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }

      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _saveDeviceToken(uid, token);
    } catch (e) {
      debugPrint('registerDeviceToken error: $e');
    }
  }

  static Future<void> _saveDeviceToken(String uid, String token) async {
    try {
      final deviceId = await getDeviceId();
      final deviceRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId);

      await deviceRef.set({
        'deviceId': deviceId,
        'fcmToken': token,
        'platform': Platform.operatingSystem,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// Remove device token upon logout
  static Future<void> unregisterDeviceToken(String uid) async {
    try {
      final deviceId = await getDeviceId();
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .delete();
    } catch (_) {}
  }

  /// Route to chat screen when notification is tapped
  static Future<void> handleNotificationRouting(
      Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (type != 'chat_message') return;

    final conversationId = data['conversationId'] as String?;
    final senderId = data['senderId'] as String?;
    final currentUid = _auth.currentUser?.uid;

    if (conversationId == null || senderId == null || currentUid == null) {
      return;
    }

    final expectedConvId = ChatService.getConversationId(currentUid, senderId);
    if (conversationId != expectedConvId) {
      return;
    }

    try {
      final senderDoc =
          await _firestore.collection('users').doc(senderId).get();
      final senderData = senderDoc.data() ?? {};
      final partnerName = (senderData['name'] as String?) ?? 'Friend';
      final partnerPhoto = senderData['photoUrl'] as String?;

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            partnerUid: senderId,
            partnerName: partnerName,
            partnerPhoto: partnerPhoto,
          ),
        ),
      );
    } catch (_) {}
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

  static void dispose() {
    _tokenRefreshSub?.cancel();
  }
}
