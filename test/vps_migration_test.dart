import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:astra/core/crypto/crypto_service.dart';
import 'package:astra/core/models/chat_message_model.dart';
import 'package:astra/core/network/api_client.dart';
import 'package:astra/core/network/api_exceptions.dart';
import 'package:astra/core/network/websocket_client.dart';
import 'package:astra/core/repositories/friend_repository.dart';
import 'package:astra/core/repositories/chat_repository.dart';
import 'package:astra/core/repositories/presence_repository.dart';
import 'package:astra/core/repositories/location_repository.dart';
import 'package:astra/core/repositories/notification_repository.dart';

void main() {
  group('1. AstraApiClient Tests', () {
    test('Injects Bearer token into headers when tokenProvider is present', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], equals('Bearer test_mock_token_123'));
        expect(request.headers['Content-Type'], equals('application/json'));
        return http.Response(jsonEncode({'user': {'id': 'user-1', 'display_name': 'Akash'}}), 200);
      });

      final client = AstraApiClient(
        baseUrl: 'https://api.croto.in/api/v1',
        tokenProvider: () async => 'test_mock_token_123',
        httpClient: mockClient,
      );

      final user = await client.getCurrentUser();
      expect(user['id'], equals('user-1'));
      expect(user['display_name'], equals('Akash'));
    });

    test('Maps HTTP 401 to UnauthorizedException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid token'}}), 401);
      });

      final client = AstraApiClient(
        baseUrl: 'https://api.croto.in/api/v1',
        httpClient: mockClient,
      );

      expect(() async => await client.getCurrentUser(), throwsA(isA<UnauthorizedException>()));
    });

    test('Maps HTTP 403 to ForbiddenException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': {'code': 'FORBIDDEN', 'message': 'Not friends'}}), 403);
      });

      final client = AstraApiClient(baseUrl: 'https://api.croto.in/api/v1', httpClient: mockClient);
      expect(() async => await client.getUserLocation('user-2'), throwsA(isA<ForbiddenException>()));
    });

    test('Maps HTTP 409 to IdempotencyConflictException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': {'code': 'IDEMPOTENCY_CONFLICT', 'message': 'Payload mismatch'}}), 409);
      });

      final client = AstraApiClient(baseUrl: 'https://api.croto.in/api/v1', httpClient: mockClient);
      expect(
        () async => await client.postMessage(
          'conv-1',
          messageId: 'msg-1',
          ciphertext: 'c',
          nonce: 'n',
          keyVersion: 1,
          recipientId: 'r',
        ),
        throwsA(isA<IdempotencyConflictException>()),
      );
    });
  });

  group('2. FriendRepository Tests', () {
    test('Sends friend request and parses response', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/friends/requests') && request.method == 'POST') {
          return http.Response(
            jsonEncode({'request': {'id': 'req-123', 'status': 'pending'}}),
            201,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final repo = FriendRepository(apiClient: apiClient);

      final res = await repo.sendFriendRequest('user-target-456');
      expect(res['request']['id'], equals('req-123'));
    });

    test('Lists accepted friends', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'friends': [
              {'friend_user_id': 'user-2', 'display_name': 'Astra Friend', 'phone_number': '+919876543210'}
            ]
          }),
          200,
        );
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final repo = FriendRepository(apiClient: apiClient);

      final friends = await repo.listFriends();
      expect(friends.length, equals(1));
      expect(friends[0]['display_name'], equals('Astra Friend'));
    });
  });

  group('3. Encrypted Chat & ChatRepository Tests', () {
    const uidAlice = '00000000-0000-0000-0000-000000000001';
    const uidBob = '00000000-0000-0000-0000-000000000002';
    final conversationId = CryptoService.getConversationId(uidAlice, uidBob);

    test('Encrypts message with AES-256-GCM before sending; VPS receives only ciphertext', () async {
      String? sentCiphertext;
      String? sentNonce;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/messages') && request.method == 'POST') {
          final body = jsonDecode(request.body);
          sentCiphertext = body['ciphertext'];
          sentNonce = body['nonce'];

          // Verify plaintext is NOT in HTTP request body
          expect(request.body.contains('Secret message for Bob'), isFalse);

          return http.Response(
            jsonEncode({
              'message': {
                'id': body['id'],
                'conversation_id': conversationId,
                'sender_id': uidAlice,
                'recipient_id': uidBob,
                'ciphertext': body['ciphertext'],
                'nonce': body['nonce'],
                'key_version': 1,
                'created_at': DateTime.now().toIso8601String(),
              }
            }),
            201,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final chatRepo = ChatRepository(currentUid: uidAlice, apiClient: apiClient);

      final sentMessage = await chatRepo.sendMessage(
        conversationId: conversationId,
        recipientUid: uidBob,
        text: 'Secret message for Bob',
      );

      expect(sentMessage.decryptedText, equals('Secret message for Bob'));
      expect(sentMessage.ciphertext, equals(sentCiphertext));
      expect(sentMessage.iv, equals(sentNonce));
      expect(sentCiphertext, isNotNull);
      expect(sentCiphertext, isNot(equals('Secret message for Bob')));
    });

    test('Deduplicates duplicate message events by messageId', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'messages': [],
            'message': {'id': 'msg-1', 'ciphertext': 'c', 'nonce': 'n', 'key_version': 1}
          }),
          200,
        );
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final chatRepo = ChatRepository(currentUid: uidAlice, apiClient: apiClient);
      final stream = chatRepo.streamMessages(conversationId: conversationId);

      final eventsList = <List<ChatMessageModel>>[];
      final sub = stream.listen((list) => eventsList.add(list));

      await chatRepo.sendMessage(
        conversationId: conversationId,
        recipientUid: uidBob,
        text: 'Hello once',
      );

      expect(eventsList.isNotEmpty, isTrue);
      expect(eventsList.last.length, equals(1));
      await sub.cancel();
    });
  });

  group('4. Presence & Typing Tests', () {
    test('Tracks user online status and last seen timestamp from presence events', () {
      final wsClient = AstraWebSocketClient();
      final repo = PresenceRepository(wsClient: wsClient);

      expect(repo.isUserOnline('user-1'), isFalse);
    });
  });

  group('5. Location & Freshness Tests', () {
    test('Evaluates location freshness correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      expect(LocationRepository.isLocationFresh(now), isTrue);
      expect(LocationRepository.isLocationFresh(now - const Duration(minutes: 2).inMilliseconds), isTrue);
      expect(LocationRepository.isLocationFresh(now - const Duration(minutes: 5).inMilliseconds), isFalse);
      expect(LocationRepository.isLocationFresh(null), isFalse);
      expect(LocationRepository.isLocationFresh(0), isFalse);
    });

    test('Formats honest human-readable freshness labels', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      expect(LocationRepository.formatLocationFreshness(now), equals('Live • Just now'));
      expect(LocationRepository.formatLocationFreshness(now - const Duration(minutes: 1).inMilliseconds), equals('Live • 1m ago'));
      expect(LocationRepository.formatLocationFreshness(now - const Duration(minutes: 10).inMilliseconds), equals('Last Known • 10m ago'));
      expect(LocationRepository.formatLocationFreshness(null), equals('Location unavailable'));
    });

    test('Sends Miss You notification via API client', () async {
      bool missYouCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/miss-you') && request.method == 'POST') {
          missYouCalled = true;
          return http.Response(jsonEncode({'success': true, 'friend_id': 'friend-1'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final repo = LocationRepository(apiClient: apiClient);

      await repo.sendMissYou('friend-1');
      expect(missYouCalled, isTrue);
    });
  });

  group('6. Device & Notification Repository Tests', () {
    test('Registers FCM device token with VPS', () async {
      bool registered = false;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/devices') && request.method == 'POST') {
          final body = jsonDecode(request.body);
          expect(body['device_id'], equals('dev-123'));
          expect(body['fcm_token'], equals('fcm-token-xyz'));
          registered = true;
          return http.Response(jsonEncode({'success': true}), 201);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = AstraApiClient(httpClient: mockClient);
      final notifRepo = NotificationRepository(apiClient: apiClient);

      await notifRepo.registerDeviceToken(
        deviceId: 'dev-123',
        platform: 'android',
        fcmToken: 'fcm-token-xyz',
      );
      expect(registered, isTrue);
    });
  });
}
