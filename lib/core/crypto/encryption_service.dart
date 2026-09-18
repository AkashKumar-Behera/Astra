import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_exceptions.dart';

/// EncryptedPayload holds base64-encoded ciphertext and nonce (IV)
class EncryptedPayload {
  final String ciphertextBase64;
  final String ivBase64;

  const EncryptedPayload({
    required this.ciphertextBase64,
    required this.ivBase64,
  });

  Map<String, String> toMap() => {
        'ciphertext': ciphertextBase64,
        'iv': ivBase64,
      };

  @override
  String toString() => 'EncryptedPayload(iv: $ivBase64, len: ${ciphertextBase64.length})';
}

/// EncryptionService
///
/// Implements AES-256-GCM authenticated encryption with 96-bit (12-byte)
/// secure random nonces and 128-bit MAC verification.
class EncryptionService {
  static final AesGcm _algorithm = AesGcm.with256bits();

  /// Canonical AAD format: "$conversationId:$messageId:$senderId:$keyVersion"
  static Uint8List computeAad({
    required String conversationId,
    required String messageId,
    required String senderId,
    required int keyVersion,
  }) {
    final raw = '$conversationId:$messageId:$senderId:$keyVersion';
    return Uint8List.fromList(utf8.encode(raw));
  }

  /// Generate a fresh, cryptographically secure 12-byte random nonce (96 bits)
  static Uint8List generateRandomNonce() {
    final random = Random.secure();
    final nonce = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
  }

  /// Encrypt plaintext using AES-256-GCM and bind message metadata as AAD.
  ///
  /// Returns [EncryptedPayload] with base64 encoded ciphertext (including 16-byte MAC tag)
  /// and 12-byte IV.
  static Future<EncryptedPayload> encrypt({
    required String plaintext,
    required SecretKey key,
    required String conversationId,
    required String messageId,
    required String senderId,
    int keyVersion = 1,
    Uint8List? explicitNonce, // For deterministic unit test verification only
  }) async {
    try {
      final plaintextBytes = utf8.encode(plaintext);
      final nonceBytes = explicitNonce ?? generateRandomNonce();
      final aadBytes = computeAad(
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        keyVersion: keyVersion,
      );

      final secretBox = await _algorithm.encrypt(
        plaintextBytes,
        secretKey: key,
        nonce: nonceBytes,
        aad: aadBytes,
      );

      // Concatenate ciphertext + MAC tag for standard transport
      final combinedCiphertext = Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
      combinedCiphertext.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
      combinedCiphertext.setRange(secretBox.cipherText.length, combinedCiphertext.length, secretBox.mac.bytes);

      return EncryptedPayload(
        ciphertextBase64: base64Encode(combinedCiphertext),
        ivBase64: base64Encode(nonceBytes),
      );
    } catch (e) {
      if (e is CryptoException) rethrow;
      throw CryptoException('Encryption failed', e);
    }
  }

  /// Decrypt ciphertext using AES-256-GCM and verify MAC tag against bound AAD.
  ///
  /// Throws [IntegrityException] or [DecryptionFailedException] if authentication fails.
  static Future<String> decrypt({
    required String ciphertextBase64,
    required String ivBase64,
    required SecretKey key,
    required String conversationId,
    required String messageId,
    required String senderId,
    int keyVersion = 1,
  }) async {
    try {
      final combinedBytes = base64Decode(ciphertextBase64);
      final nonceBytes = base64Decode(ivBase64);

      if (combinedBytes.length < 16) {
        throw const DecryptionFailedException('Ciphertext is too short to contain a 16-byte MAC tag.');
      }

      if (nonceBytes.length != 12) {
        throw const DecryptionFailedException('Invalid IV length. Expected 12 bytes.');
      }

      final cipherTextLength = combinedBytes.length - 16;
      final cipherText = combinedBytes.sublist(0, cipherTextLength);
      final macBytes = combinedBytes.sublist(cipherTextLength);

      final aadBytes = computeAad(
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        keyVersion: keyVersion,
      );

      final secretBox = SecretBox(
        cipherText,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: key,
        aad: aadBytes,
      );

      return utf8.decode(decryptedBytes);
    } on SecretBoxAuthenticationError catch (e) {
      throw IntegrityException('Authentication tag mismatch or modified AAD/ciphertext: $e');
    } catch (e) {
      if (e is CryptoException) rethrow;
      throw DecryptionFailedException('Failed to decrypt payload: $e');
    }
  }
}
