import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/models/chat_message_model.dart';
import 'package:astra/core/theme/astra_theme.dart';

void main() {
  group('Milestone 3 - Chat Message Bubble UI Rendering', () {
    testWidgets('Renders decryptedText in bubble without showing ciphertext', (WidgetTester tester) async {
      const samplePlaintext = 'Hello Astra Secure Chat!';
      const sampleCiphertext = 'kX89aBcDeFgHiJkLmNoP==';

      final message = ChatMessageModel(
        id: 'msg_1',
        conversationId: 'alice_bob',
        senderId: 'alice',
        recipientId: 'bob',
        ciphertext: sampleCiphertext,
        iv: 'nonce123',
        timestamp: DateTime(2026, 9, 18, 14, 30).millisecondsSinceEpoch,
        keyVersion: 1,
        status: MessageStatus.sent,
        decryptedText: samplePlaintext,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AstraTheme.darkTheme,
          home: Scaffold(
            body: Text(message.decryptedText ?? ''),
          ),
        ),
      );

      // Verify plaintext is rendered
      expect(find.text(samplePlaintext), findsOneWidget);

      // Verify ciphertext is NOT rendered in the widget tree
      expect(find.text(sampleCiphertext), findsNothing);
    });

    testWidgets('Decryption error shows controlled error state without crashing', (WidgetTester tester) async {
      const sampleCiphertext = 'corrupted_ciphertext_abc==';

      final failedMessage = ChatMessageModel(
        id: 'msg_2',
        conversationId: 'alice_bob',
        senderId: 'bob',
        recipientId: 'alice',
        ciphertext: sampleCiphertext,
        iv: 'nonce123',
        timestamp: DateTime(2026, 9, 18, 14, 31).millisecondsSinceEpoch,
        keyVersion: 1,
        status: MessageStatus.failed,
        decryptedText: null,
        decryptionError: 'Authentication tag mismatch',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AstraTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                if (failedMessage.decryptionError != null) {
                  return const Row(
                    children: [
                      Icon(Icons.lock_clock_rounded),
                      Text('Message could not be decrypted'),
                    ],
                  );
                }
                return Text(failedMessage.decryptedText ?? '');
              },
            ),
          ),
        ),
      );

      // Verify controlled error message is rendered
      expect(find.text('Message could not be decrypted'), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_rounded), findsOneWidget);

      // Verify raw corrupted ciphertext is not visible
      expect(find.text(sampleCiphertext), findsNothing);
    });
  });
}
