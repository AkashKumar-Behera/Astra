/// Typed API Exceptions for Astra VPS Client
class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final dynamic details;

  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'ApiException [$statusCode - $code]: $message';
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({
    super.statusCode = 401,
    super.code = 'UNAUTHORIZED',
    super.message = 'Authentication token is invalid or expired.',
    super.details,
  });
}

class ForbiddenException extends ApiException {
  const ForbiddenException({
    super.statusCode = 403,
    super.code = 'FORBIDDEN',
    super.message = 'You do not have permission to perform this action.',
    super.details,
  });
}

class NotFoundException extends ApiException {
  const NotFoundException({
    super.statusCode = 404,
    super.code = 'NOT_FOUND',
    super.message = 'The requested resource was not found.',
    super.details,
  });
}

class RateLimitException extends ApiException {
  const RateLimitException({
    super.statusCode = 429,
    super.code = 'RATE_LIMITED',
    super.message = 'Too many requests. Please slow down.',
    super.details,
  });
}

class NetworkException extends ApiException {
  const NetworkException({
    super.statusCode = 0,
    super.code = 'NETWORK_ERROR',
    super.message = 'Failed to connect to the Astra server. Check your connection.',
    super.details,
  });
}

class IdempotencyConflictException extends ApiException {
  const IdempotencyConflictException({
    super.statusCode = 409,
    super.code = 'IDEMPOTENCY_CONFLICT',
    super.message = 'Message ID conflict with different payload.',
    super.details,
  });
}
