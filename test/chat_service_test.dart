import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/crypto/crypto_service.dart';
import 'package:astra/core/models/chat_message_model.dart';
import 'package:astra/core/models/conversation_model.dart';
import 'package:astra/core/services/chat_service.dart';

void main() {
  const testSecret = 'ASTRA_SUPER_SECRET_KEY_FOR_TESTING_PURPOSES_ONLY_32B';
  const uidAlice = 'user_alice_12345';
  const uidBob = 'user_bob_67890';
  const uidCharlie = 'user_charlie_99999';

  group('Milestone 2 - Deterministic Conversation IDs', () {
    test('1. Same two users produce the same conversation ID', () {
      final convId1 = ChatService.getConversationId(uidAlice, uidBob);
      final convId2 = ChatService.getConversationId(uidAlice, uidBob);
      expect(convId1, equals(convId2));
      expect(convId1, equals('user_alice_12345_user_bob_67890'));
    });

    test('2. Reversed UID order produces the exact same conversation ID', () {
      final convIdA = ChatService.getConversationId(uidAlice, uidBob);
      final convIdB = ChatService.getConversationId(uidBob, uidAlice);
      expect(convIdA, equals(convIdB));
    });

    test('3. Different users produce completely different conversation IDs', () {
      final convIdAliceBob = ChatService.getConversationId(uidAlice, uidBob);
      final convIdAliceCharlie = ChatService.getConversationId(uidAlice, uidCharlie);
      expect(convIdAliceBob, isNot(equals(convIdAliceCharlie)));
    });
  });

  group('Milestone 2 - ConversationModel & Serialization', () {
    test('Conversation metadata serialization contains only metadata and no secrets', () {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      final model = ConversationModel(
        id: convId,
        participants: [uidAlice, uidBob],
        createdAt: 1700000000000,
        updatedAt: 1700000000500,
        keyVersion: 1,
      );

      final map = model.toFirestore();
      expect(map['id'], equals(convId));
      expect(map['participants'], equals([uidAlice, uidBob]));
      expect(map['keyVersion'], equals(1));
      expect(map.containsKey('plaintext'), isFalse);
      expect(map.containsKey('secretKey'), isFalse);
    });
  });

  group('Milestone 2 - ChatMessageModel Firestore Envelope Integrity', () {
    test('4 & 5. Plaintext is encrypted before persistence, payload has ciphertext/IV only', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      const messageId = 'msg_001_abc';
      const plaintext = 'Top secret Astra private payload 🔐';

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      final model = ChatMessageModel(
        id: messageId,
        conversationId: convId,
        senderId: uidAlice,
        recipientId: uidBob,
        ciphertext: encrypted.ciphertextBase64,
        iv: encrypted.ivBase64,
        timestamp: 1700000000000,
        keyVersion: 1,
        status: MessageStatus.sent,
        decryptedText: plaintext, // In-memory only
      );

      final firestorePayload = model.toFirestore();

      // Plaintext must NEVER be present in Firestore payload
      expect(firestorePayload.containsKey('decryptedText'), isFalse);
      expect(firestorePayload.containsKey('decryptionError'), isFalse);
      expect(firestorePayload.containsValue(plaintext), isFalse);

      // Ciphertext and IV must be non-empty base64 strings
      expect(firestorePayload['ciphertext'], equals(encrypted.ciphertextBase64));
      expect(firestorePayload['iv'], equals(encrypted.ivBase64));
      expect(firestorePayload['senderId'], equals(uidAlice));
      expect(firestorePayload['recipientId'], equals(uidBob));
      expect(firestorePayload['conversationId'], equals(convId));
    });
  });

  group('Milestone 2 - Encryption, Decryption & AAD Enforcement', () {
    test('6. Correct participant can decrypt the Firestore message envelope', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      const messageId = 'msg_002_xyz';
      const plaintext = 'Hello Bob! This is Alice on Astra.';

      // Alice encrypts
      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      // Bob receives Firestore envelope and decrypts
      final decrypted = await CryptoService.decryptMessage(
        ciphertextBase64: encrypted.ciphertextBase64,
        ivBase64: encrypted.ivBase64,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      expect(decrypted, equals(plaintext));
    });

    test('7. Wrong conversation ID / AAD fails decryption integrity check', () async {
      final convAliceBob = ChatService.getConversationId(uidAlice, uidBob);
      final convAliceCharlie = ChatService.getConversationId(uidAlice, uidCharlie);
      const messageId = 'msg_003_cross_room';
      const plaintext = 'Secret meant only for Alice and Bob';

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convAliceBob,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      // Charlie attempts to decrypt in Alice-Charlie room
      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: encrypted.ciphertextBase64,
          ivBase64: encrypted.ivBase64,
          conversationId: convAliceCharlie, // Wrong AAD
          messageId: messageId,
          senderId: uidAlice,
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('8. Wrong keyVersion fails decryption safely', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      const messageId = 'msg_004_v1';
      const plaintext = 'Version 1 message';

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        keyVersion: 1,
        customSecret: testSecret,
      );

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: encrypted.ciphertextBase64,
          ivBase64: encrypted.ivBase64,
          conversationId: convId,
          messageId: messageId,
          senderId: uidAlice,
          keyVersion: 2, // Mismatched keyVersion in AAD
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('9. Unauthorized user with different secret cannot decrypt message', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      const messageId = 'msg_005_eavesdrop';
      const plaintext = 'Private Astra message';

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      const attackerSecret = 'ATTACKER_SECRET_DIFFERENT_HASH_VALUE_32B';
      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: encrypted.ciphertextBase64,
          ivBase64: encrypted.ivBase64,
          conversationId: convId,
          messageId: messageId,
          senderId: uidAlice,
          customSecret: attackerSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('10. Sender ID cannot be spoofed in AAD', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);
      const messageId = 'msg_006_spoof';
      const plaintext = 'Message claiming to be from someone else';

      final encrypted = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: convId,
        messageId: messageId,
        senderId: uidAlice,
        customSecret: testSecret,
      );

      // Attempting to decrypt claiming Bob was the sender
      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: encrypted.ciphertextBase64,
          ivBase64: encrypted.ivBase64,
          conversationId: convId,
          messageId: messageId,
          senderId: uidBob, // Spoofed sender in AAD
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('Milestone 2 - Stream Resiliency & Error Handling', () {
    test('12. Corrupted / tampered Firestore message does not crash message stream', () async {
      final convId = ChatService.getConversationId(uidAlice, uidBob);

      // Message 1: Valid
      final enc1 = await CryptoService.encryptMessage(
        plaintext: 'Valid Message 1',
        conversationId: convId,
        messageId: 'msg_valid_1',
        senderId: uidAlice,
        customSecret: testSecret,
      );

      // Message 2: Corrupted ciphertext (simulating tamper / db corruption)
      final corruptedCiphertext = '${enc1.ciphertextBase64.substring(4)}AAAA';

      // Message 3: Valid
      final enc3 = await CryptoService.encryptMessage(
        plaintext: 'Valid Message 3',
        conversationId: convId,
        messageId: 'msg_valid_3',
        senderId: uidAlice,
        customSecret: testSecret,
      );

      final rawList = [
        {
          'id': 'msg_valid_1',
          'conversationId': convId,
          'senderId': uidAlice,
          'recipientId': uidBob,
          'ciphertext': enc1.ciphertextBase64,
          'iv': enc1.ivBase64,
          'type': 'text',
          'timestamp': 1000,
          'keyVersion': 1,
          'status': 'sent',
        },
        {
          'id': 'msg_corrupted_2',
          'conversationId': convId,
          'senderId': uidAlice,
          'recipientId': uidBob,
          'ciphertext': corruptedCiphertext,
          'iv': enc1.ivBase64,
          'type': 'text',
          'timestamp': 2000,
          'keyVersion': 1,
          'status': 'sent',
        },
        {
          'id': 'msg_valid_3',
          'conversationId': convId,
          'senderId': uidAlice,
          'recipientId': uidBob,
          'ciphertext': enc3.ciphertextBase64,
          'iv': enc3.ivBase64,
          'type': 'text',
          'timestamp': 3000,
          'keyVersion': 1,
          'status': 'sent',
        },
      ];

      // Simulate stream transformation logic from ChatService
      final processedMessages = <ChatMessageModel>[];

      for (final raw in rawList) {
        final model = ChatMessageModel.fromFirestore(raw);
        try {
          final decrypted = await CryptoService.decryptMessage(
            ciphertextBase64: model.ciphertext,
            ivBase64: model.iv,
            conversationId: model.conversationId,
            messageId: model.id,
            senderId: model.senderId,
            keyVersion: model.keyVersion,
            customSecret: testSecret,
          );
          processedMessages.add(model.copyWith(decryptedText: decrypted));
        } catch (e) {
          processedMessages.add(
            model.copyWith(
              status: MessageStatus.failed,
              decryptionError: e.toString(),
            ),
          );
        }
      }

      // Stream continues and all 3 messages are preserved
      expect(processedMessages.length, equals(3));
      expect(processedMessages[0].decryptedText, equals('Valid Message 1'));
      expect(processedMessages[0].status, equals(MessageStatus.sent));

      // Corrupted message has clear error and does not crash
      expect(processedMessages[1].decryptedText, isNull);
      expect(processedMessages[1].status, equals(MessageStatus.failed));
      expect(processedMessages[1].decryptionError, isNotNull);
      expect(processedMessages[1].decryptionError, contains('CryptoException'));

      // Third message is still successfully decrypted
      expect(processedMessages[2].decryptedText, equals('Valid Message 3'));
      expect(processedMessages[2].status, equals(MessageStatus.sent));
    });
  });
}
