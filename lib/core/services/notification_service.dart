import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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

  await handleInlineReply(response);
}

/// Global helper to execute inline notification reply
Future<void> handleInlineReply(NotificationResponse response) async {
  if (response.actionId != 'reply_action') return;
  final replyText = response.input;
  if (replyText == null || replyText.trim().isEmpty) return;

  final payloadStr = response.payload;
  if (payloadStr == null) return;

  try {
    final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
    final conversationId = payload['conversationId'] as String?;
    final recipientId = payload['senderId'] as String?;
    final myUid = payload['myUid'] as String? ?? FirebaseAuth.instance.currentUser?.uid;

    if (conversationId != null && recipientId != null) {
      final chatService = ChatService();
      await chatService.sendMessage(
        conversationId: conversationId,
        recipientUid: recipientId,
        text: replyText.trim(),
        senderUidOverride: myUid,
      );

      if (response.id != null) {
        await _localNotifications.cancel(id: response.id!);
      }
      debugPrint('[NotificationService] Inline reply sent successfully: $replyText');
    }
  } catch (e) {
    debugPrint('[NotificationService] Error sending inline notification reply: $e');
  }
}

/// Helper to show local decrypted notification with WhatsApp style grouping & inline reply
Future<void> showLocalDecryptedNotification({
  required String messageId,
  required String senderName,
  required String senderId,
  required String conversationId,
  required String bodyText,
  String? myUid,
}) async {
  final groupKey = 'com.astra.always.CHAT_$conversationId';
  final person = Person(
    name: senderName,
    key: senderId,
  );

  final messagingStyle = MessagingStyleInformation(
    person,
    conversationTitle: senderName,
    groupConversation: false,
    messages: [
      Message(
        bodyText,
        DateTime.now(),
        person,
      ),
    ],
  );

  final androidDetails = AndroidNotificationDetails(
    'astra_chat_messages',
    'Astra Messages',
    channelDescription: 'End-to-end encrypted chat messages',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    icon: 'ic_notification',
    color: const Color(0xFF8B5CF6),
    category: AndroidNotificationCategory.message,
    styleInformation: messagingStyle,
    groupKey: groupKey,
    sound: const RawResourceAndroidNotificationSound('astra_chime'),
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 150, 80, 150]),
    actions: [
      const AndroidNotificationAction(
        'reply_action',
        'Reply',
        icon: DrawableResourceAndroidBitmap('ic_notification'),
        allowGeneratedReplies: true,
        showsUserInterface: false,
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

  final notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  final notifId = messageId.hashCode;
  final payloadJson = jsonEncode({
    'conversationId': conversationId,
    'senderId': senderId,
    'senderName': senderName,
    'myUid': myUid ?? FirebaseAuth.instance.currentUser?.uid ?? '',
    'type': 'chat_message',
  });

  await _localNotifications.show(
    id: notifId,
    title: senderName,
    body: bodyText,
    notificationDetails: notificationDetails,
    payload: payloadJson,
  );

  // Group summary notification for clean WhatsApp style bundling
  if (Platform.isAndroid) {
    final summaryDetails = AndroidNotificationDetails(
      'astra_chat_messages',
      'Astra Messages',
      channelDescription: 'End-to-end encrypted chat messages',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_notification',
      color: const Color(0xFF8B5CF6),
      groupKey: groupKey,
      setAsGroupSummary: true,
      category: AndroidNotificationCategory.message,
    );

    await _localNotifications.show(
      id: conversationId.hashCode,
      title: senderName,
      body: bodyText,
      notificationDetails: NotificationDetails(android: summaryDetails),
      payload: payloadJson,
    );
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

  await showLocalDecryptedNotification(
    messageId: messageId,
    senderName: senderName,
    senderId: senderId ?? '',
    conversationId: conversationId ?? '',
    bodyText: bodyText,
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
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription? _conversationsSub;
  static final Map<String, StreamSubscription> _convMsgSubs = {};
  static final Set<String> _processedMessageIds = {};

  /// Set by ChatScreen when open to avoid showing notification for active chat
  static String? activeConversationId;

  /// Initialize local notification plugins, FCM listeners, and tokens
  static Future<void> initialize() async {
    try {
      // 1. Initialize Flutter Local Notifications
      const androidInit = AndroidInitializationSettings('ic_notification');
      final darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        notificationCategories: [
          DarwinNotificationCategory(
            'astra_chat_category',
            actions: [
              DarwinNotificationAction.plain(
                'reply_action',
                'Reply',
                options: {
                  DarwinNotificationActionOption.foreground,
                },
              ),
            ],
            options: {
              DarwinNotificationCategoryOption.customDismissAction,
            },
          ),
        ],
      );
      final initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          if (response.actionId == 'reply_action') {
            handleInlineReply(response);
            return;
          }
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
            AndroidNotificationChannel(
              'astra_chat_messages',
              'Astra Messages',
              description: 'End-to-end encrypted chat messages',
              importance: Importance.max,
              sound: const RawResourceAndroidNotificationSound('astra_chime'),
              playSound: true,
              enableVibration: true,
              vibrationPattern: Int64List.fromList([0, 150, 80, 150]),
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

      // 4. Set FCM background handler (Android & iOS)
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (_) {}

      // 5. Auto-register device token and start realtime message watcher on auth changes
      _authSub?.cancel();
      _authSub = _auth.authStateChanges().listen((user) async {
        if (user != null) {
          await registerDeviceToken(user.uid);
          startRealtimeMessageWatcher(user.uid);
        } else {
          stopRealtimeMessageWatcher();
        }
      });

      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await registerDeviceToken(currentUser.uid);
        startRealtimeMessageWatcher(currentUser.uid);
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

  /// Start watching conversations for incoming messages in realtime (Foreground & Background fallback)
  static void startRealtimeMessageWatcher(String uid) {
    stopRealtimeMessageWatcher();

    _conversationsSub = _firestore
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((convSnapshot) {
      final activeConvIds = <String>{};

      for (final convDoc in convSnapshot.docs) {
        final convId = convDoc.id;
        activeConvIds.add(convId);

        if (!_convMsgSubs.containsKey(convId)) {
          _convMsgSubs[convId] = _firestore
              .collection('conversations')
              .doc(convId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .limit(1)
              .snapshots()
              .listen((msgSnapshot) async {
            if (msgSnapshot.docs.isEmpty) return;
            final msgDoc = msgSnapshot.docs.first;
            final msgData = msgDoc.data();
            final msgId = msgDoc.id;

            final recipientId = msgData['recipientId'] as String?;
            final senderId = msgData['senderId'] as String?;
            final timestamp = msgData['timestamp'] as int? ?? 0;

            final now = DateTime.now().millisecondsSinceEpoch;
            // Only notify for fresh incoming messages (< 25s) addressed to current user
            if (recipientId == uid &&
                senderId != null &&
                senderId != uid &&
                !_processedMessageIds.contains(msgId) &&
                (now - timestamp).abs() < 25000) {
              _processedMessageIds.add(msgId);

              // Don't show notification banner if user is currently inside this chat
              if (activeConversationId == convId) {
                return;
              }

              String senderName = 'Partner';
              try {
                final senderDoc =
                    await _firestore.collection('users').doc(senderId).get();
                if (senderDoc.exists) {
                  senderName =
                      (senderDoc.data()?['name'] as String?) ?? 'Partner';
                }
              } catch (_) {}

              final ciphertext = msgData['ciphertext'] as String?;
              final iv = msgData['iv'] as String?;
              final keyVersion = msgData['keyVersion'] as int? ?? 1;

              String bodyText = 'New message received';
              if (ciphertext != null && iv != null) {
                try {
                  final decrypted = await CryptoService.decryptMessage(
                    ciphertextBase64: ciphertext,
                    ivBase64: iv,
                    conversationId: convId,
                    messageId: msgId,
                    senderId: senderId,
                    keyVersion: keyVersion,
                  );
                  if (decrypted.isNotEmpty) {
                    bodyText = decrypted;
                  }
                } catch (_) {
                  bodyText = 'New encrypted message';
                }
              }

              await showLocalDecryptedNotification(
                messageId: msgId,
                senderName: senderName,
                senderId: senderId,
                conversationId: convId,
                bodyText: bodyText,
              );
            }
          });
        }
      }

      _convMsgSubs.removeWhere((id, sub) {
        if (!activeConvIds.contains(id)) {
          sub.cancel();
          return true;
        }
        return false;
      });
    });
  }

  /// Stop watching conversations
  static void stopRealtimeMessageWatcher() {
    _conversationsSub?.cancel();
    _conversationsSub = null;
    for (final sub in _convMsgSubs.values) {
      sub.cancel();
    }
    _convMsgSubs.clear();
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
    _authSub?.cancel();
    stopRealtimeMessageWatcher();
  }
}

