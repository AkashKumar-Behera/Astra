import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/services/chat_service.dart';
import 'package:astra/core/services/notification_service.dart';

void main() {
  group('Milestone 4 - Notification Payload Privacy & Integrity', () {
    test('1. Generic notification payload contains NO plaintext message text', () {
      final payload = NotificationService.buildGenericNotificationPayload(
        conversationId: 'alice_bob',
        senderId: 'alice',
        messageId: 'msg_123',
      );

      final notification = payload['notification'] as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;

      // Verify generic notification titles
      expect(notification['title'], equals('New message'));
      expect(notification['body'], contains('Astra encrypted message'));

      // Verify no message text fields exist
      expect(data.containsKey('text'), isFalse);
      expect(data.containsKey('decryptedText'), isFalse);
      expect(data.containsKey('plaintext'), isFalse);
      expect(data.containsKey('secret'), isFalse);
      expect(data.containsKey('APP_SECRET'), isFalse);
      expect(data.containsKey('key'), isFalse);
    });

    test('2. Notification payload contains required routing metadata', () {
      final payload = NotificationService.buildGenericNotificationPayload(
        conversationId: 'user1_user2',
        senderId: 'user1',
        messageId: 'msg_abc',
      );

      final data = payload['data'] as Map<String, dynamic>;
      expect(data['type'], equals('chat_message'));
      expect(data['conversationId'], equals('user1_user2'));
      expect(data['senderId'], equals('user1'));
      expect(data['messageId'], equals('msg_abc'));
      expect(data.containsKey('timestamp'), isTrue);
    });

    test('3. Notification routing validation rejects unauthorized user conversationId', () {
      const currentUid = 'user_charlie';
      const unauthorizedPayload = {
        'type': 'chat_message',
        'conversationId': 'user_alice_user_bob', // Charlie is NOT a participant
        'senderId': 'user_alice',
        'messageId': 'msg_999',
      };

      final conversationId = unauthorizedPayload['conversationId']!;
      final senderId = unauthorizedPayload['senderId']!;

      final expectedConvId = ChatService.getConversationId(currentUid, senderId);
      final isParticipant = conversationId == expectedConvId;

      // Charlie must be rejected from navigating to Alice-Bob conversation
      expect(isParticipant, isFalse);
    });

    test('4. Notification routing validation accepts legitimate participant conversationId', () {
      const currentUid = 'user_bob';
      final canonicalId = ChatService.getConversationId('user_alice', 'user_bob');
      final validPayload = {
        'type': 'chat_message',
        'conversationId': canonicalId,
        'senderId': 'user_alice',
        'messageId': 'msg_100',
      };

      final conversationId = validPayload['conversationId']!;
      final senderId = validPayload['senderId']!;

      final expectedConvId = ChatService.getConversationId(currentUid, senderId);
      final isParticipant = conversationId == expectedConvId;

      expect(isParticipant, isTrue);
    });
  });
}
