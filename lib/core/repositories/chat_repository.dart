import 'dart:async';
import 'package:flutter/foundation.dart';
import '../crypto/crypto_service.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import '../network/api_client.dart';
import '../network/websocket_client.dart';

class ChatRepository {
  final AstraApiClient _apiClient;
  final AstraWebSocketClient? _wsClient;
  final String _currentUid;

  // In-memory message cache indexed by conversationId -> list of decrypted ChatMessageModel
  final Map<String, List<ChatMessageModel>> _messageCache = {};
  final Map<String, StreamController<List<ChatMessageModel>>> _streamControllers = {};
  StreamSubscription? _wsMessageSub;

  ChatRepository({
    required String currentUid,
    AstraApiClient? apiClient,
    AstraWebSocketClient? wsClient,
  })  : _currentUid = currentUid,
        _apiClient = apiClient ?? AstraApiClient(),
        _wsClient = wsClient {
    _initWsListener();
  }

  void _initWsListener() {
    _wsMessageSub?.cancel();
    if (_wsClient != null) {
      _wsMessageSub = _wsClient.on('message.new').listen((event) async {
        final payload = event.payload;
        final conversationId = payload['conversation_id'] as String?;
        final messageId = payload['id'] as String?;
        final senderId = payload['sender_id'] as String?;
        final recipientId = payload['recipient_id'] as String?;
        final ciphertext = payload['ciphertext'] as String?;
        final nonce = (payload['nonce'] ?? payload['iv']) as String?;
        final keyVersion = payload['key_version'] as int? ?? CryptoService.currentKeyVersion;
        final createdAtStr = payload['created_at'] as String?;
        final timestamp = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch;

        if (conversationId == null || messageId == null || senderId == null || ciphertext == null || nonce == null) {
          return;
        }

        // Decrypt message locally
        String? decrypted;
        String? decryptError;
        try {
          decrypted = await CryptoService.decryptMessage(
            ciphertextBase64: ciphertext,
            ivBase64: nonce,
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            keyVersion: keyVersion,
          );
        } catch (e) {
          decryptError = 'Decryption failed: $e';
        }

        final model = ChatMessageModel(
          id: messageId,
          conversationId: conversationId,
          senderId: senderId,
          recipientId: recipientId ?? _currentUid,
          ciphertext: ciphertext,
          iv: nonce,
          type: MessageType.text,
          timestamp: timestamp,
          keyVersion: keyVersion,
          status: decryptError != null ? MessageStatus.failed : MessageStatus.delivered,
          decryptedText: decrypted,
          decryptionError: decryptError,
        );

        _addMessageToCache(conversationId, model);

        // Acknowledge delivery
        if (senderId != _currentUid && _wsClient.isConnected) {
          _wsClient.sendEnvelope('message.delivered', {
            'message_id': messageId,
            'conversation_id': conversationId,
            'sender_id': senderId,
          });
        }
      });
    }
  }

  void _addMessageToCache(String conversationId, ChatMessageModel message) {
    final list = _messageCache.putIfAbsent(conversationId, () => []);
    final existingIdx = list.indexWhere((m) => m.id == message.id);

    if (existingIdx >= 0) {
      list[existingIdx] = message;
    } else {
      list.add(message);
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    if (_streamControllers.containsKey(conversationId) && !_streamControllers[conversationId]!.isClosed) {
      _streamControllers[conversationId]!.add(List.unmodifiable(list));
    }
  }

  /// Get or create conversation metadata
  Future<ConversationModel> getOrCreateConversation({required String recipientUid}) async {
    final conversationId = CryptoService.getConversationId(_currentUid, recipientUid);
    final participants = [_currentUid, recipientUid]..sort();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final res = await _apiClient.getOrCreateConversation(recipientUserId: recipientUid);
      return ConversationModel(
        id: (res['id'] as String?) ?? conversationId,
        participants: participants,
        createdAt: now,
        updatedAt: now,
        keyVersion: CryptoService.currentKeyVersion,
      );
    } catch (_) {
      return ConversationModel(
        id: conversationId,
        participants: participants,
        createdAt: now,
        updatedAt: now,
        keyVersion: CryptoService.currentKeyVersion,
      );
    }
  }

  /// Send an encrypted chat message
  Future<ChatMessageModel> sendMessage({
    required String conversationId,
    required String recipientUid,
    required String text,
    MessageType type = MessageType.text,
  }) async {
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_${_currentUid.substring(0, 4)}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const keyVersion = CryptoService.currentKeyVersion;

    // 1. Client-Side AES-256-GCM Encryption
    final encrypted = await CryptoService.encryptMessage(
      plaintext: text,
      conversationId: conversationId,
      messageId: messageId,
      senderId: _currentUid,
      keyVersion: keyVersion,
    );

    final localMessage = ChatMessageModel(
      id: messageId,
      conversationId: conversationId,
      senderId: _currentUid,
      recipientId: recipientUid,
      ciphertext: encrypted.ciphertextBase64,
      iv: encrypted.ivBase64,
      type: type,
      timestamp: timestamp,
      keyVersion: keyVersion,
      status: MessageStatus.sent,
      decryptedText: text,
    );

    // 2. Add immediately to local cache & notify stream
    _addMessageToCache(conversationId, localMessage);

    // 3. Dispatch to VPS via WebSocket if connected, else via REST API
    if (_wsClient != null && _wsClient.isConnected) {
      _wsClient.sendEnvelope('message.send', {
        'id': messageId,
        'conversation_id': conversationId,
        'recipient_id': recipientUid,
        'ciphertext': encrypted.ciphertextBase64,
        'nonce': encrypted.ivBase64,
        'key_version': keyVersion,
      });
    } else {
      await _apiClient.postMessage(
        conversationId,
        messageId: messageId,
        ciphertext: encrypted.ciphertextBase64,
        nonce: encrypted.ivBase64,
        keyVersion: keyVersion,
        recipientId: recipientUid,
      );
    }

    return localMessage;
  }

  /// Stream messages in real time with on-the-fly local decryption
  Stream<List<ChatMessageModel>> streamMessages({
    required String conversationId,
    int limit = 100,
  }) {
    final controller = _streamControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<ChatMessageModel>>.broadcast(),
    );

    // Fetch message history in background
    _loadHistory(conversationId, limit: limit);

    // Emit current cache immediately if non-empty
    if (_messageCache.containsKey(conversationId)) {
      controller.add(List.unmodifiable(_messageCache[conversationId]!));
    }

    return controller.stream;
  }

  Future<void> _loadHistory(String conversationId, {int limit = 100}) async {
    try {
      final rawMessages = await _apiClient.getConversationMessages(conversationId, limit: limit);

      for (final raw in rawMessages) {
        final messageId = raw['id'] as String?;
        final senderId = raw['sender_id'] as String?;
        final recipientId = raw['recipient_id'] as String?;
        final ciphertext = raw['ciphertext'] as String?;
        final nonce = (raw['nonce'] ?? raw['iv']) as String?;
        final keyVersion = raw['key_version'] as int? ?? CryptoService.currentKeyVersion;
        final createdAtStr = raw['created_at'] as String?;
        final timestamp = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch;

        if (messageId == null || senderId == null || ciphertext == null || nonce == null) continue;

        String? decrypted;
        String? decryptError;
        try {
          decrypted = await CryptoService.decryptMessage(
            ciphertextBase64: ciphertext,
            ivBase64: nonce,
            conversationId: conversationId,
            messageId: messageId,
            senderId: senderId,
            keyVersion: keyVersion,
          );
        } catch (e) {
          decryptError = 'Decryption failed: $e';
        }

        final model = ChatMessageModel(
          id: messageId,
          conversationId: conversationId,
          senderId: senderId,
          recipientId: recipientId ?? (senderId == _currentUid ? '' : _currentUid),
          ciphertext: ciphertext,
          iv: nonce,
          type: MessageType.text,
          timestamp: timestamp,
          keyVersion: keyVersion,
          status: decryptError != null ? MessageStatus.failed : MessageStatus.delivered,
          decryptedText: decrypted,
          decryptionError: decryptError,
        );

        _addMessageToCache(conversationId, model);
      }
    } catch (e) {
      debugPrint('Error loading chat history for $conversationId: $e');
    }
  }

  void dispose() {
    _wsMessageSub?.cancel();
    for (final controller in _streamControllers.values) {
      controller.close();
    }
    _streamControllers.clear();
  }
}
