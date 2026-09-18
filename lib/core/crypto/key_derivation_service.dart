import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'crypto_exceptions.dart';

/// KeyDerivationService
///
/// Implements RFC 5869 HKDF-SHA256 to derive deterministic 256-bit (32-byte)
/// conversation encryption keys from compile-time application secret and
/// canonical conversation IDs.
class KeyDerivationService {
  /// Active production APP_SECRET read from compile-time environment
  static const String _defaultAppSecret = String.fromEnvironment('APP_SECRET');

  /// Registry of historical APP_SECRETS for future rotation and backward compatibility.
  /// When rotating keys in Astra v2, add legacy secrets here while updating current version.
  static final Map<int, String> _secretVault = {
    1: _defaultAppSecret,
  };

  /// Current active cryptographic protocol version
  static const int currentKeyVersion = 1;

  /// Generate deterministic canonical conversation ID: [uidA, uidB].sort().join('_')
  static String getCanonicalConversationId(String uidA, String uidB) {
    if (uidA.isEmpty || uidB.isEmpty) {
      throw const CryptoException('UIDs cannot be empty when constructing conversation ID.');
    }
    final list = [uidA, uidB]..sort();
    return '${list[0]}_${list[1]}';
  }

  /// Derive a 256-bit SecretKey using HKDF-SHA256.
  ///
  /// - IKM: APP_SECRET (Root Secret)
  /// - Salt: canonicalConversationId (Domain Isolator)
  /// - Info: "Astra-Chat-v{keyVersion}" (Context Separator)
  /// - Output Length: 32 bytes (256 bits)
  static Future<SecretKey> deriveConversationKey({
    required String conversationId,
    int keyVersion = currentKeyVersion,
    String? customSecret,
  }) async {
    final effectiveSecret = customSecret ?? _secretVault[keyVersion] ?? _defaultAppSecret;

    if (effectiveSecret.isEmpty) {
      throw const InvalidSecretException(
        'APP_SECRET is empty. Ensure --dart-define=APP_SECRET=... or env.json is configured.',
      );
    }

    if (conversationId.isEmpty) {
      throw const CryptoException('conversationId cannot be empty for key derivation.');
    }

    // RFC 5869 HKDF with HMAC-SHA256
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32, // 256 bits
    );

    final ikm = SecretKey(utf8.encode(effectiveSecret));
    final salt = utf8.encode(conversationId);
    final info = utf8.encode('Astra-Chat-v$keyVersion');

    final derivedKey = await hkdf.deriveKey(
      secretKey: ikm,
      nonce: salt,
      info: info,
    );

    return derivedKey;
  }
}
