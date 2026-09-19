import 'package:cloud_firestore/cloud_firestore.dart';

/// ConversationModel
///
/// Represents the metadata envelope for a 1-to-1 conversation stored at
/// `/conversations/{conversationId}` in Firestore.
///
/// Contains ONLY participant and timing metadata with the active keyVersion.
/// No plaintext message text or encryption keys are ever stored here.
class ConversationModel {
  final String id;
  final List<String> participants;
  final int createdAt;
  final int updatedAt;
  final int keyVersion;

  const ConversationModel({
    required this.id,
    required this.participants,
    required this.createdAt,
    required this.updatedAt,
    this.keyVersion = 1,
  });

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'participants': participants,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'keyVersion': keyVersion,
      };

  Map<String, dynamic> toMap() => toFirestore();

  static int _parseTimestamp(dynamic value) {
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is String) return int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch;
    return DateTime.now().millisecondsSinceEpoch;
  }

  factory ConversationModel.fromFirestore(Map<String, dynamic> data, String id) {
    final rawParticipants = data['participants'] as List<dynamic>? ?? [];
    return ConversationModel(
      id: id,
      participants: rawParticipants.map((e) => e.toString()).toList(),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      keyVersion: (data['keyVersion'] as num?)?.toInt() ?? 1,
    );
  }

  ConversationModel copyWith({
    String? id,
    List<String>? participants,
    int? createdAt,
    int? updatedAt,
    int? keyVersion,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      keyVersion: keyVersion ?? this.keyVersion,
    );
  }
}
