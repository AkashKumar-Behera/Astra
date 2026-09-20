import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../crypto/crypto_service.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'websocket_service.dart';

/// ChatService
///
/// Production Firestore persistence and transport layer for Astra Chat.
///
/// Features:
/// - Deterministic canonical conversation IDs (sorted participant UIDs)
/// - Strict 1-to-1 conversation validation
/// - Authenticated encryption before writing to Firestore
/// - Plaintext is strictly transient and never written to Firestore
/// - Transparent decryption on stream reads
/// - Controlled decryption error handling (corrupted messages do not crash streams)
class ChatService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Current authenticated Firebase UID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Deterministic Canonical Conversation ID
  ///
  /// Always produces the exact same string regardless of UID order:
  /// `[uidA, uidB]..sort().join('_')`
  static String getConversationId(String uidA, String uidB) {
    return CryptoService.getConversationId(uidA, uidB);
  }

  /// Get or create a 1-to-1 conversation metadata document
  ///
  /// Enforces exactly two unique participants.
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

    final conversationId = getConversationId(senderUid, recipientUid);
    final docRef = _firestore.collection('conversations').doc(conversationId);

    final snapshot = await docRef.get();
    if (snapshot.exists && snapshot.data() != null) {
      return ConversationModel.fromFirestore(snapshot.data()!, conversationId);
    }

    final participants = [senderUid, recipientUid]..sort();
    final now = DateTime.now().millisecondsSinceEpoch;

    final conversation = ConversationModel(
      id: conversationId,
      participants: participants,
      createdAt: now,
      updatedAt: now,
      keyVersion: CryptoService.currentKeyVersion,
    );

    await docRef.set(conversation.toFirestore());
    return conversation;
  }

  /// Get conversation metadata by ID
  Future<ConversationModel?> getConversation(String conversationId) async {
    final snapshot = await _firestore.collection('conversations').doc(conversationId).get();
    if (snapshot.exists && snapshot.data() != null) {
      return ConversationModel.fromFirestore(snapshot.data()!, conversationId);
    }
    return null;
  }

  /// Send an encrypted chat message
  ///
  /// Flow:
  /// 1. Validate authenticated user (sender).
  /// 2. Validate sender and recipient are the 2 participants of the conversation.
  /// 3. Generate unique messageId.
  /// 4. Encrypt plaintext using [CryptoService.encryptMessage] with canonical APP_SECRET and AAD.
  /// 5. Write ONLY the encrypted envelope to Firestore.
  /// 6. Update conversation `updatedAt` metadata.
  /// 7. Return in-memory [ChatMessageModel] with decryptedText populated.
  Future<ChatMessageModel> sendMessage({
    required String conversationId,
    required String recipientUid,
    required String text,
    MessageType type = MessageType.text,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    String? mediaUrl,
    int? audioDurationSec,
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

    // Verify conversation ID matches deterministic pair
    final expectedConvId = getConversationId(senderUid, recipientUid);
    if (conversationId != expectedConvId) {
      throw ArgumentError('Conversation ID $conversationId does not match participant pair.');
    }

    // Generate unique message ID
    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();
    final messageId = messageRef.id;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    const keyVersion = CryptoService.currentKeyVersion;

    // Encrypt plaintext payload with AES-256-GCM + AAD using canonical CryptoService
    final encrypted = await CryptoService.encryptMessage(
      plaintext: text,
      conversationId: conversationId,
      messageId: messageId,
      senderId: senderUid,
      keyVersion: keyVersion,
    );

    final message = ChatMessageModel(
      id: messageId,
      conversationId: conversationId,
      senderId: senderUid,
      recipientId: recipientUid,
      ciphertext: encrypted.ciphertextBase64,
      iv: encrypted.ivBase64,
      type: type,
      timestamp: timestamp,
      keyVersion: keyVersion,
      status: MessageStatus.sent,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      mediaUrl: mediaUrl,
      audioDurationSec: audioDurationSec,
      decryptedText: text, // in-memory only
    );

    // Atomic / batch write
    final batch = _firestore.batch();
    batch.set(messageRef, message.toFirestore());
    batch.update(
      _firestore.collection('conversations').doc(conversationId),
      {'updatedAt': timestamp},
    );

    await batch.commit();

    // Broadcast over WebSocket for sub-50ms instant delivery
    if (WebSocketService.isConnected) {
      WebSocketService.sendEncryptedMessage(
        messageId: messageId,
        conversationId: conversationId,
        recipientUid: recipientUid,
        plaintext: text,
      ).catchError((_) => false);
    }

    return message;
  }

  /// Stream messages in real-time with on-the-fly decryption
  ///
  /// Guarantees that malformed documents or decryption integrity failures
  /// will NOT crash the entire message stream.
  Stream<List<ChatMessageModel>> streamMessages({
    required String conversationId,
    int limit = 100,
  }) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .asyncMap((snapshot) async {
      final messages = <ChatMessageModel>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final rawMessage = ChatMessageModel.fromFirestore(data);

          // Decrypt ciphertext using CryptoService and verified AAD
          try {
            final decrypted = await CryptoService.decryptMessage(
              ciphertextBase64: rawMessage.ciphertext,
              ivBase64: rawMessage.iv,
              conversationId: rawMessage.conversationId.trim().isNotEmpty
                  ? rawMessage.conversationId.trim()
                  : conversationId.trim(),
              messageId: rawMessage.id.trim().isNotEmpty
                  ? rawMessage.id.trim()
                  : doc.id.trim(),
              senderId: rawMessage.senderId.trim(),
              keyVersion: rawMessage.keyVersion,
            );

            messages.add(rawMessage.copyWith(
              id: rawMessage.id.trim().isNotEmpty ? rawMessage.id.trim() : doc.id.trim(),
              decryptedText: decrypted,
            ));
          } catch (cryptoErr) {
            // Decryption failure (tag mismatch, key mismatch, corrupted data)
            messages.add(
              rawMessage.copyWith(
                id: rawMessage.id.trim().isNotEmpty ? rawMessage.id.trim() : doc.id.trim(),
                status: MessageStatus.failed,
                decryptionError: 'Decryption failed: ${cryptoErr.toString()}',
              ),
            );
          }
        } catch (parseErr) {
          // Skip completely unparseable docs without crashing stream
          continue;
        }
      }

      return messages;
    });
  }

  /// Get past messages once (e.g. for initial load or history)
  Future<List<ChatMessageModel>> getMessages({
    required String conversationId,
    int limit = 50,
  }) async {
    final snapshot = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .get();

    final messages = <ChatMessageModel>[];

    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        final rawMessage = ChatMessageModel.fromFirestore(data);

        try {
          final decrypted = await CryptoService.decryptMessage(
            ciphertextBase64: rawMessage.ciphertext,
            ivBase64: rawMessage.iv,
            conversationId: rawMessage.conversationId.trim().isNotEmpty
                ? rawMessage.conversationId.trim()
                : conversationId.trim(),
            messageId: rawMessage.id.trim().isNotEmpty
                ? rawMessage.id.trim()
                : doc.id.trim(),
            senderId: rawMessage.senderId.trim(),
            keyVersion: rawMessage.keyVersion,
          );

          messages.add(rawMessage.copyWith(
            id: rawMessage.id.trim().isNotEmpty ? rawMessage.id.trim() : doc.id.trim(),
            decryptedText: decrypted,
          ));
        } catch (cryptoErr) {
          messages.add(
            rawMessage.copyWith(
              id: rawMessage.id.trim().isNotEmpty ? rawMessage.id.trim() : doc.id.trim(),
              status: MessageStatus.failed,
              decryptionError: 'Decryption failed: ${cryptoErr.toString()}',
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }

    return messages;
  }

  /// Delete a message from Firestore
  ///
  /// Only allows sender to delete their own message.
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final senderUid = currentUserId;
    if (senderUid == null || senderUid.isEmpty) {
      throw StateError('User must be authenticated to delete a message.');
    }

    final messageRef = _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    final snapshot = await messageRef.get();
    if (!snapshot.exists || snapshot.data() == null) {
      return;
    }

    final data = snapshot.data()!;
    if (data['senderId'] != senderUid) {
      throw StateError('Cannot delete a message sent by another user.');
    }

    await messageRef.delete();
  }
}
