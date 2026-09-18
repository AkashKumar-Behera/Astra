/// Custom exceptions for Astra Cryptographic Subsystem
class CryptoException implements Exception {
  final String message;
  final dynamic cause;

  const CryptoException(this.message, [this.cause]);

  @override
  String toString() => 'CryptoException: $message${cause != null ? " (Cause: $cause)" : ""}';
}

class InvalidSecretException extends CryptoException {
  const InvalidSecretException([super.message = 'APP_SECRET is missing or empty in environment.']);
}

class DecryptionFailedException extends CryptoException {
  const DecryptionFailedException([super.message = 'Decryption failed. Integrity check failed or invalid key/nonce.']);
}

class IntegrityException extends CryptoException {
  const IntegrityException([super.message = 'Authentication tag mismatch. Message was tampered with.']);
}
