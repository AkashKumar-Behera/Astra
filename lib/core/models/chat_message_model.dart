enum MessageType {
  text,
  image,
  audio,
  file,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

/// ChatMessageModel
///
/// Production minimal data model representing an encrypted chat message envelope in Firestore.
/// Note: [decryptedText] and [decryptionError] are strictly transient in-memory fields
/// and are NEVER serialized or written to Firestore.
class ChatMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String ciphertext;
  final String iv;
  final MessageType type;
  final int timestamp;
  final int keyVersion;
  final MessageStatus status;

  // Transient / in-memory decrypted content (NEVER stored in Firestore)
  final String? decryptedText;

  // Transient / in-memory error description if decryption failed
  final String? decryptionError;

  const ChatMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.ciphertext,
    required this.iv,
    this.type = MessageType.text,
    required this.timestamp,
    this.keyVersion = 1,
    this.status = MessageStatus.sent,
    this.decryptedText,
    this.decryptionError,
  });

  /// Serializes ONLY the encrypted envelope to Firestore.
  /// [decryptedText] and [decryptionError] are intentionally excluded.
  Map<String, dynamic> toFirestore() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'recipientId': recipientId,
        'ciphertext': ciphertext,
        'iv': iv,
        'type': type.name,
        'timestamp': timestamp,
        'keyVersion': keyVersion,
        'status': status.name,
      };

  factory ChatMessageModel.fromFirestore(
    Map<String, dynamic> data, {
    String? decryptedContent,
    String? decryptionError,
  }) {
    return ChatMessageModel(
      id: data['id'] as String? ?? '',
      conversationId: data['conversationId'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      recipientId: data['recipientId'] as String? ?? '',
      ciphertext: data['ciphertext'] as String? ?? '',
      iv: data['iv'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (t) => t.name == (data['type'] as String?),
        orElse: () => MessageType.text,
      ),
      timestamp: (data['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      keyVersion: (data['keyVersion'] as num?)?.toInt() ?? 1,
      status: MessageStatus.values.firstWhere(
        (s) => s.name == (data['status'] as String?),
        orElse: () => MessageStatus.sent,
      ),
      decryptedText: decryptedContent,
      decryptionError: decryptionError,
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? recipientId,
    String? ciphertext,
    String? iv,
    MessageType? type,
    int? timestamp,
    int? keyVersion,
    MessageStatus? status,
    String? decryptedText,
    String? decryptionError,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      recipientId: recipientId ?? this.recipientId,
      ciphertext: ciphertext ?? this.ciphertext,
      iv: iv ?? this.iv,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      keyVersion: keyVersion ?? this.keyVersion,
      status: status ?? this.status,
      decryptedText: decryptedText ?? this.decryptedText,
      decryptionError: decryptionError ?? this.decryptionError,
    );
  }
}
