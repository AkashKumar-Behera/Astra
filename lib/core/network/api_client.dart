import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_exceptions.dart';

typedef TokenProvider = Future<String?> Function();

class AstraApiClient {
  final String baseUrl;
  final TokenProvider? tokenProvider;
  final http.Client _httpClient;

  static const String defaultBaseUrl = 'https://api.croto.in/api/v1';

  AstraApiClient({
    this.baseUrl = defaultBaseUrl,
    this.tokenProvider,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Future<Map<String, String>> _getHeaders({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth && tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    bool requiresAuth = true,
  }) async {
    Uri uri = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    try {
      final headers = await _getHeaders(requiresAuth: requiresAuth);
      http.Response response;

      switch (method.toUpperCase()) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(const Duration(seconds: 15));
          break;
        case 'POST':
          response = await _httpClient
              .post(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'PUT':
          response = await _httpClient
              .put(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
          break;
        case 'DELETE':
          response = await _httpClient.delete(uri, headers: headers).timeout(const Duration(seconds: 15));
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }

      return _handleResponse(response);
    } on SocketException catch (e) {
      throw NetworkException(message: 'No internet connection: ${e.message}');
    } on TimeoutException {
      throw const NetworkException(message: 'Request timed out. Please check your network connection.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException(message: e.toString());
    }
  }

  dynamic _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      if (response.body.isNotEmpty) {
        decoded = jsonDecode(response.body);
      }
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final code = decoded is Map && decoded['error'] is Map
        ? (decoded['error']['code'] as String? ?? 'UNKNOWN_ERROR')
        : (decoded is Map && decoded['code'] is String ? decoded['code'] as String : 'UNKNOWN_ERROR');

    final message = decoded is Map && decoded['error'] is Map
        ? (decoded['error']['message'] as String? ?? 'An unexpected error occurred')
        : (decoded is Map && decoded['message'] is String ? decoded['message'] as String : 'An error occurred (${response.statusCode})');

    switch (response.statusCode) {
      case 401:
        throw UnauthorizedException(message: message, details: decoded);
      case 403:
        throw ForbiddenException(message: message, details: decoded);
      case 404:
        throw NotFoundException(message: message, details: decoded);
      case 409:
        throw IdempotencyConflictException(message: message, details: decoded);
      case 429:
        throw RateLimitException(message: message, details: decoded);
      default:
        throw ApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
          details: decoded,
        );
    }
  }

  // ================= AUTH & USER =================

  /// Sync user profile with VPS
  Future<Map<String, dynamic>> syncAuth({
    String? phoneNumber,
    String? displayName,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{};
    if (phoneNumber != null) body['phone_number'] = phoneNumber;
    if (displayName != null) body['display_name'] = displayName;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;

    final res = await _send('POST', '/auth/sync', body: body);
    return res is Map && res['user'] is Map ? Map<String, dynamic>.from(res['user']) : <String, dynamic>{};
  }

  /// Get current user profile
  Future<Map<String, dynamic>> getCurrentUser() async {
    final res = await _send('GET', '/users/me');
    return res is Map && res['user'] is Map ? Map<String, dynamic>.from(res['user']) : <String, dynamic>{};
  }

  // ================= DEVICES =================

  Future<void> registerDevice({
    required String deviceId,
    required String platform,
    String? fcmToken,
    String? appVersion,
  }) async {
    await _send('POST', '/devices', body: {
      'device_id': deviceId,
      'platform': platform,
      if (fcmToken != null) 'fcm_token': fcmToken,
      if (appVersion != null) 'app_version': appVersion,
    });
  }

  Future<void> removeDevice(String deviceId) async {
    await _send('DELETE', '/devices/$deviceId');
  }

  /// Look up users by a list of phone numbers
  Future<List<Map<String, dynamic>>> lookupUsers(List<String> phoneNumbers) async {
    if (phoneNumbers.isEmpty) return [];
    final res = await _send('POST', '/users/lookup', body: {
      'phone_numbers': phoneNumbers,
    });
    if (res is Map && res['users'] is List) {
      return (res['users'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Search users by name or phone
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final res = await _send('GET', '/users/search', queryParams: {'q': query.trim()});
    if (res is Map && res['users'] is List) {
      return (res['users'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ================= FRIENDS =================

  Future<Map<String, dynamic>> sendFriendRequest(String recipientUserId) async {
    final res = await _send('POST', '/friends/requests', body: {
      'recipient_user_id': recipientUserId,
    });
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<List<Map<String, dynamic>>> listFriendRequests({String type = 'all'}) async {
    final res = await _send('GET', '/friends/requests', queryParams: {'type': type});
    if (res is Map && res['requests'] is List) {
      return (res['requests'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> respondFriendRequest({
    required String requestId,
    required String action, // 'accept', 'reject', 'cancelled'
  }) async {
    final res = await _send('POST', '/friends/requests/$requestId/respond', body: {
      'action': action,
    });
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<List<Map<String, dynamic>>> listFriends() async {
    final res = await _send('GET', '/friends');
    if (res is Map && res['friends'] is List) {
      return (res['friends'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> removeFriend(String friendId) async {
    await _send('DELETE', '/friends/$friendId');
  }

  // ================= CONVERSATIONS & CHAT =================

  Future<Map<String, dynamic>> getOrCreateConversation({required String recipientUserId}) async {
    final res = await _send('POST', '/conversations', body: {
      'recipient_user_id': recipientUserId,
    });
    return res is Map && res['conversation'] is Map
        ? Map<String, dynamic>.from(res['conversation'])
        : (res is Map ? Map<String, dynamic>.from(res) : {});
  }

  Future<List<Map<String, dynamic>>> listConversations({int limit = 50, int offset = 0}) async {
    final res = await _send('GET', '/conversations', queryParams: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    if (res is Map && res['conversations'] is List) {
      return (res['conversations'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getConversationMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _send('GET', '/conversations/$conversationId/messages', queryParams: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    if (res is Map && res['messages'] is List) {
      return (res['messages'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> postMessage(
    String conversationId, {
    required String messageId,
    required String ciphertext,
    required String nonce,
    required int keyVersion,
    required String recipientId,
    String? aad,
  }) async {
    final res = await _send('POST', '/conversations/$conversationId/messages', body: {
      'id': messageId,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'key_version': keyVersion,
      'recipient_id': recipientId,
      if (aad != null) 'aad': aad,
    });
    return res is Map && res['message'] is Map ? Map<String, dynamic>.from(res['message']) : {};
  }

  // ================= LOCATION & MISS YOU =================

  Future<Map<String, dynamic>> updateLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    String? deviceId,
  }) async {
    final res = await _send('POST', '/location', body: {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (deviceId != null) 'device_id': deviceId,
    });
    return res is Map && res['location'] is Map ? Map<String, dynamic>.from(res['location']) : {};
  }

  Future<Map<String, dynamic>?> getUserLocation(String userId) async {
    try {
      final res = await _send('GET', '/location/$userId');
      return res is Map && res['location'] is Map ? Map<String, dynamic>.from(res['location']) : null;
    } catch (e) {
      if (e is NotFoundException) return null;
      rethrow;
    }
  }

  Future<void> sendMissYou(String friendId) async {
    await _send('POST', '/friends/$friendId/miss-you');
  }

  void close() {
    _httpClient.close();
  }
}
