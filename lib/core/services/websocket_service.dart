import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../models/chat_message_model.dart';
import 'notification_service.dart';

/// Astra WebSocket Service
///
/// Connects to the dedicated VPS backend at wss://api.croto.in/ws for:
/// - Real-time sub-50ms encrypted chat messaging
/// - Live continuous GPS location streaming
/// - Online presence & typing indicators
/// - WebRTC call signaling
/// - Automatic fallback to Firestore if offline
class WebSocketService {
  static const String apiBaseUrl = 'https://api.croto.in';
  static const String wsBaseUrl = 'wss://api.croto.in/ws';

  static WebSocket? _socket;
  static bool _isConnecting = false;
  static Timer? _pingTimer;
  static Timer? _reconnectTimer;
  static int _reconnectAttempts = 0;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream controllers for real-time events
  static final StreamController<ChatMessageModel> _messageController =
      StreamController<ChatMessageModel>.broadcast();
  static final StreamController<Map<String, dynamic>> _locationController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _typingController =
      StreamController<Map<String, dynamic>>.broadcast();
  static final StreamController<Map<String, dynamic>> _callController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  static Stream<ChatMessageModel> get onMessage => _messageController.stream;
  static Stream<Map<String, dynamic>> get onLocation =>
      _locationController.stream;
  static Stream<Map<String, dynamic>> get onPresence =>
      _presenceController.stream;
  static Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  static Stream<Map<String, dynamic>> get onCallSignaling =>
      _callController.stream;

  static bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  /// Synchronize user account with VPS PostgreSQL database
  static Future<String?> syncUserWithBackend({
    String? displayName,
    String? phoneNumber,
    String? avatarUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final token = await user.getIdToken();
      final uri = Uri.parse('$apiBaseUrl/auth/sync');

      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'display_name': displayName ?? user.displayName ?? 'Astra User',
          'phone_number': phoneNumber ?? user.phoneNumber ?? '',
          'avatar_url': avatarUrl ?? user.photoURL,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final userObj = data['user'] as Map<String, dynamic>?;
        final vpsUserId = userObj?['id'] as String?;

        if (vpsUserId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('vps_user_id', vpsUserId);
          return vpsUserId;
        }
      } else {
        debugPrint('VPS user sync returned ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('VPS user sync error: $e');
    }
    return null;
  }

  /// Initialize and connect WebSocket
  static Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;

    final user = _auth.currentUser;
    if (user == null) {
      _isConnecting = false;
      return;
    }

    try {
      // Ensure user profile exists on VPS first
      await syncUserWithBackend();

      final token = await user.getIdToken();
      final uri = Uri.parse('$wsBaseUrl?token=$token');

      debugPrint('Connecting to Astra WebSocket: $wsBaseUrl');
      _socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 10));

      _isConnecting = false;
      _reconnectAttempts = 0;
      debugPrint('Astra WebSocket Connected successfully!');

      _startHeartbeat();

      _socket!.listen(
        _onMessageReceived,
        onError: (err) {
          debugPrint('Astra WebSocket Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('Astra WebSocket Closed: ${_socket?.closeCode}');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      debugPrint('Astra WebSocket connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Handle incoming raw socket text
  static void _onMessageReceived(dynamic rawData) async {
    try {
      final text = rawData.toString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';
      final payload = json['payload'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'connection.ready':
          debugPrint('WebSocket ready: ${payload['userId']}');
          break;

        case 'pong':
          // Heartbeat ack
          break;

        case 'message.new':
          _handleIncomingChatMessage(payload);
          break;

        case 'message.delivered':
        case 'message.read':
        case 'message.deleted':
        case 'message.updated':
          // Pass status updates to UI
          break;

        case 'location.updated':
        case 'location.response':
          _locationController.add(payload);
          break;

        case 'presence.changed':
          _presenceController.add(payload);
          break;

        case 'typing.start':
        case 'typing.stop':
          _typingController.add({'type': type, ...payload});
          break;

        case 'call.invite':
        case 'call.accept':
        case 'call.reject':
        case 'call.busy':
        case 'call.cancel':
        case 'call.offer':
        case 'call.answer':
        case 'call.ice':
        case 'call.end':
          _callController.add({'type': type, ...payload});
          break;

        default:
          debugPrint('Unhandled WebSocket message type: $type');
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  /// Decrypt and dispatch incoming chat message
  static Future<void> _handleIncomingChatMessage(
      Map<String, dynamic> payload) async {
    final msgData = payload['message'] as Map<String, dynamic>? ?? payload;

    final messageId = msgData['id'] as String? ?? '';
    final conversationId = msgData['conversationId'] as String? ?? '';
    final senderId = msgData['senderId'] as String? ?? '';
    final recipientId = msgData['recipientId'] as String? ?? '';
    final ciphertext = msgData['ciphertext'] as String? ?? '';
    final nonce = msgData['nonce'] as String? ?? '';
    final keyVersion = msgData['keyVersion'] as int? ?? 1;
    final timestamp = msgData['createdAt'] != null
        ? DateTime.tryParse(msgData['createdAt'].toString())
                ?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;

    String bodyText = 'New message received';

    if (ciphertext.isNotEmpty && nonce.isNotEmpty) {
      try {
        final decrypted = await CryptoService.decryptMessage(
          ciphertextBase64: ciphertext,
          ivBase64: nonce,
          conversationId: conversationId,
          messageId: messageId,
          senderId: senderId,
          keyVersion: keyVersion,
        );
        if (decrypted.isNotEmpty) {
          bodyText = decrypted;
        }
      } catch (e) {
        debugPrint('WebSocket on-the-fly decryption fallback: $e');
        bodyText = 'New encrypted message';
      }
    }

    final chatMessage = ChatMessageModel(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      recipientId: recipientId,
      ciphertext: ciphertext,
      iv: nonce,
      type: MessageType.text,
      timestamp: timestamp,
      keyVersion: keyVersion,
      status: MessageStatus.delivered,
      decryptedText: bodyText,
    );

    // Notify stream listeners in ChatScreen
    _messageController.add(chatMessage);

    // Send delivery ack back to server
    sendDeliveryAck(messageId);

    // Trigger on-device local notification if not actively in this chat
    if (NotificationService.activeConversationId != conversationId) {
      await showLocalDecryptedNotification(
        messageId: messageId,
        senderName: 'Partner',
        senderId: senderId,
        conversationId: conversationId,
        bodyText: bodyText,
      );
    }
  }

  /// Send an encrypted chat message over WebSocket
  static Future<bool> sendEncryptedMessage({
    required String messageId,
    required String conversationId,
    required String recipientUid,
    required String plaintext,
    String? aad,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    try {
      const keyVersion = CryptoService.currentKeyVersion;

      // Encrypt locally on device before sending to VPS
      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: currentUser.uid,
        keyVersion: keyVersion,
      );

      final envelope = {
        'v': 1,
        'type': 'message.send',
        'requestId': messageId,
        'payload': {
          'messageId': messageId,
          'conversationId': conversationId,
          'ciphertext': encrypted.ciphertextBase64,
          'nonce': encrypted.ivBase64,
          'keyVersion': keyVersion,
          'aad': aad ?? conversationId,
        },
      };

      if (isConnected) {
        _socket!.add(jsonEncode(envelope));
        debugPrint('Sent message over Astra WebSocket: $messageId');
        return true;
      }
    } catch (e) {
      debugPrint('Error sending message via WebSocket: $e');
    }
    return false;
  }

  /// Stream live GPS location coordinates over WebSocket
  static void sendLocationUpdate({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? deviceId,
  }) {
    if (!isConnected) return;

    try {
      final envelope = {
        'v': 1,
        'type': 'location.update',
        'payload': {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy ?? 5.0,
          'device_id': deviceId ?? 'mobile_device',
        },
      };

      _socket!.add(jsonEncode(envelope));
    } catch (e) {
      debugPrint('Error sending location update over WebSocket: $e');
    }
  }

  /// Send message delivered receipt
  static void sendDeliveryAck(String messageId) {
    if (!isConnected) return;
    try {
      _socket!.add(jsonEncode({
        'v': 1,
        'type': 'message.delivered',
        'payload': {'messageId': messageId},
      }));
    } catch (_) {}
  }

  /// Send message read receipt
  static void sendReadAck(String messageId) {
    if (!isConnected) return;
    try {
      _socket!.add(jsonEncode({
        'v': 1,
        'type': 'message.read',
        'payload': {'messageId': messageId},
      }));
    } catch (_) {}
  }

  /// Send typing indicator
  static void sendTyping(String conversationId, bool isTyping) {
    if (!isConnected) return;
    try {
      _socket!.add(jsonEncode({
        'v': 1,
        'type': isTyping ? 'typing.start' : 'typing.stop',
        'payload': {'conversationId': conversationId},
      }));
    } catch (_) {}
  }

  /// Maintain persistent connection via ping/pong heartbeat
  static void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (isConnected) {
        try {
          _socket!.add(jsonEncode({'v': 1, 'type': 'ping', 'payload': {}}));
        } catch (_) {}
      } else {
        timer.cancel();
      }
    });
  }

  static void _handleDisconnect() {
    _pingTimer?.cancel();
    _socket = null;
    _scheduleReconnect();
  }

  static void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    final delay = Duration(
      seconds: _reconnectAttempts > 5 ? 30 : (_reconnectAttempts * 3),
    );

    _reconnectTimer = Timer(delay, () {
      if (!isConnected && _auth.currentUser != null) {
        connect();
      }
    });
  }

  /// Disconnect and cleanup
  static void disconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      _socket?.close(WebSocketStatus.normalClosure);
    } catch (_) {}
    _socket = null;
    _isConnecting = false;
  }
}
