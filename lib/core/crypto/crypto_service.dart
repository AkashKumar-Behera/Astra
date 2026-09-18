import 'package:cryptography/cryptography.dart';
import 'key_derivation_service.dart';
import 'encryption_service.dart';

export 'crypto_exceptions.dart';
export 'key_derivation_service.dart';
export 'encryption_service.dart';

/// CryptoService Facade
///
/// High-level single-entry API providing transparent deterministic key derivation,
/// authenticated encryption, and decryption for Astra Chat.
class CryptoService {
  static const int currentKeyVersion = KeyDerivationService.currentKeyVersion;

  /// Get canonical deterministic conversation ID
  static String getConversationId(String uidA, String uidB) =>
      KeyDerivationService.getCanonicalConversationId(uidA, uidB);

  /// Derive 256-bit conversation key using HKDF-SHA256
  static Future<SecretKey> deriveKey({
    required String conversationId,
    int keyVersion = currentKeyVersion,
    String? customSecret,
  }) =>
      KeyDerivationService.deriveConversationKey(
        conversationId: conversationId,
        keyVersion: keyVersion,
        customSecret: customSecret,
      );

  /// Encrypt a message payload
  static Future<EncryptedPayload> encryptMessage({
    required String plaintext,
    required String conversationId,
    required String messageId,
    required String senderId,
    int keyVersion = currentKeyVersion,
    SecretKey? cachedKey,
    String? customSecret,
  }) async {
    final key = cachedKey ??
        await KeyDerivationService.deriveConversationKey(
          conversationId: conversationId,
          keyVersion: keyVersion,
          customSecret: customSecret,
        );

    return EncryptionService.encrypt(
      plaintext: plaintext,
      key: key,
      conversationId: conversationId,
      messageId: messageId,
      senderId: senderId,
      keyVersion: keyVersion,
    );
  }

  /// Decrypt a message payload
  static Future<String> decryptMessage({
    required String ciphertextBase64,
    required String ivBase64,
    required String conversationId,
    required String messageId,
    required String senderId,
    int keyVersion = currentKeyVersion,
    SecretKey? cachedKey,
    String? customSecret,
  }) async {
    final key = cachedKey ??
        await KeyDerivationService.deriveConversationKey(
          conversationId: conversationId,
          keyVersion: keyVersion,
          customSecret: customSecret,
        );

    return EncryptionService.decrypt(
      ciphertextBase64: ciphertextBase64,
      ivBase64: ivBase64,
      key: key,
      conversationId: conversationId,
      messageId: messageId,
      senderId: senderId,
      keyVersion: keyVersion,
    );
  }
}
