import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/crypto/crypto_service.dart';

void main() {
  const testSecret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const uidAlice = 'user_alice_123';
  const uidBob = 'user_bob_456';
  const uidCharlie = 'user_charlie_789';

  group('Astra Cryptographic Core & Key Derivation (HKDF-SHA256)', () {
    test('1. Same users (any order) + same conversation ID derive the EXACT same key', () async {
      final roomId1 = CryptoService.getConversationId(uidAlice, uidBob);
      final roomId2 = CryptoService.getConversationId(uidBob, uidAlice);

      expect(roomId1, equals(roomId2));
      expect(roomId1, equals('user_alice_123_user_bob_456'));

      final key1 = await CryptoService.deriveKey(conversationId: roomId1, customSecret: testSecret);
      final key2 = await CryptoService.deriveKey(conversationId: roomId2, customSecret: testSecret);

      final key1Bytes = await key1.extractBytes();
      final key2Bytes = await key2.extractBytes();

      expect(key1Bytes, equals(key2Bytes));
      expect(key1Bytes.length, equals(32)); // 256 bits
    });

    test('2. Different conversation IDs derive completely different keys', () async {
      final roomAB = CryptoService.getConversationId(uidAlice, uidBob);
      final roomAC = CryptoService.getConversationId(uidAlice, uidCharlie);

      final keyAB = await CryptoService.deriveKey(conversationId: roomAB, customSecret: testSecret);
      final keyAC = await CryptoService.deriveKey(conversationId: roomAC, customSecret: testSecret);

      final bytesAB = await keyAB.extractBytes();
      final bytesAC = await keyAC.extractBytes();

      expect(bytesAB, isNot(equals(bytesAC)));
    });

    test('12. Empty/invalid APP_SECRET fails safely with InvalidSecretException', () async {
      final roomAB = CryptoService.getConversationId(uidAlice, uidBob);

      expect(
        () async => await CryptoService.deriveKey(conversationId: roomAB, customSecret: ''),
        throwsA(isA<InvalidSecretException>()),
      );
    });
  });

  group('Astra Message Encryption & Decryption (AES-256-GCM + AAD)', () {
    const conversationId = 'user_alice_123_user_bob_456';
    const messageId = 'msg_001_test';
    const senderId = uidAlice;
    const plaintext = 'Hey Bob, this is an encrypted message in Astra!';

    test('3. Same plaintext + same key produces DIFFERENT ciphertexts (Fresh CSPRNG Nonce)', () async {
      final payload1 = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      final payload2 = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      expect(payload1.ivBase64, isNot(equals(payload2.ivBase64)));
      expect(payload1.ciphertextBase64, isNot(equals(payload2.ciphertextBase64)));
    });

    test('4. Correct key + correct AAD successfully decrypts ciphertext to exact plaintext', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      final decrypted = await CryptoService.decryptMessage(
        ciphertextBase64: payload.ciphertextBase64,
        ivBase64: payload.ivBase64,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      expect(decrypted, equals(plaintext));
    });

    test('5. Decryption with wrong key fails safely', () async {
      const wrongSecret = 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: payload.ciphertextBase64,
          ivBase64: payload.ivBase64,
          conversationId: conversationId,
          messageId: messageId,
          senderId: senderId,
          customSecret: wrongSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('6. Tampered / modified ciphertext fails integrity check', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      // Flip one byte in the ciphertext
      final rawBytes = base64Decode(payload.ciphertextBase64);
      rawBytes[0] ^= 0xFF;
      final tamperedCiphertext = base64Encode(rawBytes);

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: tamperedCiphertext,
          ivBase64: payload.ivBase64,
          conversationId: conversationId,
          messageId: messageId,
          senderId: senderId,
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('7. Tampered / modified nonce (IV) fails integrity check', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      // Tamper the IV
      final rawIv = base64Decode(payload.ivBase64);
      rawIv[0] ^= 0xAA;
      final tamperedIv = base64Encode(rawIv);

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: payload.ciphertextBase64,
          ivBase64: tamperedIv,
          conversationId: conversationId,
          messageId: messageId,
          senderId: senderId,
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('8. Modified AAD (conversation ID mismatch / cross-chat injection) fails integrity check', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        customSecret: testSecret,
      );

      // Attempt to decrypt in another conversation room
      const attackerRoom = 'user_alice_123_user_charlie_789';

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: payload.ciphertextBase64,
          ivBase64: payload.ivBase64,
          conversationId: attackerRoom,
          messageId: messageId,
          senderId: senderId,
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('9. Modified messageId in AAD fails integrity check', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: 'msg_original_001',
        senderId: senderId,
        customSecret: testSecret,
      );

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: payload.ciphertextBase64,
          ivBase64: payload.ivBase64,
          conversationId: conversationId,
          messageId: 'msg_forged_999',
          senderId: senderId,
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('10. Different keyVersion in AAD fails integrity check', () async {
      final payload = await CryptoService.encryptMessage(
        plaintext: plaintext,
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        keyVersion: 1,
        customSecret: testSecret,
      );

      expect(
        () async => await CryptoService.decryptMessage(
          ciphertextBase64: payload.ciphertextBase64,
          ivBase64: payload.ivBase64,
          conversationId: conversationId,
          messageId: messageId,
          senderId: senderId,
          keyVersion: 2, // Mismatched version
          customSecret: testSecret,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('11. Historical keyVersion can be specified and decrypted seamlessly', () async {
      const v1Secret = 'v1_secret_key_11111111111111111111111111111111';
      const v2Secret = 'v2_secret_key_22222222222222222222222222222222';

      // Old message encrypted under v1
      final v1Payload = await CryptoService.encryptMessage(
        plaintext: 'Legacy message from 2025',
        conversationId: conversationId,
        messageId: 'msg_v1_001',
        senderId: senderId,
        keyVersion: 1,
        customSecret: v1Secret,
      );

      // New message encrypted under v2
      final v2Payload = await CryptoService.encryptMessage(
        plaintext: 'Modern message from 2026',
        conversationId: conversationId,
        messageId: 'msg_v2_002',
        senderId: senderId,
        keyVersion: 2,
        customSecret: v2Secret,
      );

      // Decrypt old message explicitly specifying keyVersion: 1
      final decryptedV1 = await CryptoService.decryptMessage(
        ciphertextBase64: v1Payload.ciphertextBase64,
        ivBase64: v1Payload.ivBase64,
        conversationId: conversationId,
        messageId: 'msg_v1_001',
        senderId: senderId,
        keyVersion: 1,
        customSecret: v1Secret,
      );

      // Decrypt new message specifying keyVersion: 2
      final decryptedV2 = await CryptoService.decryptMessage(
        ciphertextBase64: v2Payload.ciphertextBase64,
        ivBase64: v2Payload.ivBase64,
        conversationId: conversationId,
        messageId: 'msg_v2_002',
        senderId: senderId,
        keyVersion: 2,
        customSecret: v2Secret,
      );

      expect(decryptedV1, equals('Legacy message from 2025'));
      expect(decryptedV2, equals('Modern message from 2026'));
    });
  });
}
