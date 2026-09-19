import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../crypto/crypto_service.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import '../network/api_client.dart';
import '../network/websocket_client.dart';
import '../repositories/chat_repository.dart';

/// ChatService
///
/// Production persistence and transport layer for Astra Chat using the Astra VPS Backend.
///
/// Features:
/// - Deterministic canonical conversation IDs (sorted participant UIDs)
/// - Strict 1-to-1 conversation validation
/// - Authenticated encryption before transmission (zero plaintext on VPS)
/// - Plaintext is strictly transient and never sent over wire
/// - Transparent local decryption on stream reads
/// - Controlled decryption error handling (corrupted messages do not crash streams)
class ChatService {
  final FirebaseAuth _auth;
  final ChatRepository _chatRepo;

  ChatService({
    FirebaseAuth? auth,
    AstraApiClient? apiClient,
    AstraWebSocketClient? wsClient,
    ChatRepository? chatRepo,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _chatRepo = chatRepo ??
            ChatRepository(
              currentUid: (auth ?? FirebaseAuth.instance).currentUser?.uid ?? '',
              apiClient: apiClient ??
                  AstraApiClient(
                    tokenProvider: () async => (auth ?? FirebaseAuth.instance).currentUser?.getIdToken(),
                  ),
              wsClient: wsClient,
            );

  /// Current authenticated Firebase UID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Deterministic Canonical Conversation ID
  static String getConversationId(String uidA, String uidB) {
    return CryptoService.getConversationId(uidA, uidB);
  }

  /// Get or create a 1-to-1 conversation metadata
  Future<ConversationModel> getOrCreateConversation({
    required String recipientUid,
  }) async {
    final senderUid = currentUserId;
    if (senderUid == null || senderUid.isEmpty) {
      throw StateError('User must be authenticated to create or access a conversation.');
    }

    if (recipientUid.isEmpty) {
      throw ArgumentError('Recipient UID cannot be empty.');
    }

    if (senderUid == recipientUid) {
      throw ArgumentError('Cannot create a conversation with oneself.');
    }

    return await _chatRepo.getOrCreateConversation(recipientUid: recipientUid);
  }

  /// Send an encrypted chat message
  Future<ChatMessageModel> sendMessage({
    required String conversationId,
    required String recipientUid,
    required String text,
    MessageType type = MessageType.text,
  }) async {
    final senderUid = currentUserId;
    if (senderUid == null || senderUid.isEmpty) {
      throw StateError('User must be authenticated to send messages.');
    }

    if (recipientUid.isEmpty) {
      throw ArgumentError('Recipient UID cannot be empty.');
    }

    if (senderUid == recipientUid) {
      throw ArgumentError('Sender and recipient cannot be identical.');
    }

    final expectedConvId = getConversationId(senderUid, recipientUid);
    if (conversationId != expectedConvId) {
      throw ArgumentError('Conversation ID $conversationId does not match participant pair.');
    }

    return await _chatRepo.sendMessage(
      conversationId: conversationId,
      recipientUid: recipientUid,
      text: text,
      type: type,
    );
  }

  /// Stream messages in real-time with on-the-fly decryption
  Stream<List<ChatMessageModel>> streamMessages({
    required String conversationId,
    int limit = 100,
  }) {
    return _chatRepo.streamMessages(conversationId: conversationId, limit: limit);
  }

  /// Get past messages
  Future<List<ChatMessageModel>> getMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    final stream = _chatRepo.streamMessages(conversationId: conversationId, limit: limit);
    return await stream.first.timeout(const Duration(seconds: 5), onTimeout: () => []);
  }

  void dispose() {
    _chatRepo.dispose();
  }
}
