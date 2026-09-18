/**
 * Astra Firebase Cloud Functions
 *
 * Server-side Push Notification Dispatcher for Astra Chat.
 *
 * Privacy Guarantees:
 * - Operates ENTIRELY on message metadata (senderId, recipientId, conversationId, messageId).
 * - NEVER accesses or decrypts message ciphertext.
 * - NEVER accesses APP_SECRET or encryption keys.
 * - NEVER sends plaintext message content in notification payloads.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onChatMessageCreated = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const messageData = snapshot.data();
    if (!messageData) return;

    const {
      senderId,
      recipientId,
      conversationId,
      id: messageId,
    } = messageData;

    if (!recipientId || !senderId || !conversationId) {
      return;
    }

    try {
      // 1. Fetch sender display name (generic fallback if private)
      const senderDoc = await admin
        .firestore()
        .collection("users")
        .doc(senderId)
        .get();

      const senderName = senderDoc.exists
        ? senderDoc.data()?.name || "Friend"
        : "Friend";

      // 2. Query recipient's registered device tokens
      const devicesSnap = await admin
        .firestore()
        .collection("users")
        .doc(recipientId)
        .collection("devices")
        .get();

      if (devicesSnap.empty) {
        return;
      }

      const tokens = [];
      const tokenDocIds = [];

      devicesSnap.forEach((doc) => {
        const data = doc.data();
        if (data.fcmToken) {
          tokens.push(data.fcmToken);
          tokenDocIds.push(doc.id);
        }
      });

      if (tokens.length === 0) return;

      // 3. Build privacy-preserving generic FCM payload
      const payload = {
        tokens: tokens,
        notification: {
          title: "New message",
          body: `New message from ${senderName}`,
        },
        data: {
          type: "chat_message",
          conversationId: conversationId,
          senderId: senderId,
          messageId: messageId || event.params.messageId,
          timestamp: Date.now().toString(),
        },
        android: {
          priority: "high",
          notification: {
            channelId: "astra_chat_messages",
            priority: "high",
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      // 4. Send multicast notification
      const response = await admin.messaging().sendEachForMulticast(payload);

      // 5. Clean up expired / unregistered device tokens
      const deletionPromises = [];
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const errorCode = res.error?.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            const staleDocId = tokenDocIds[idx];
            deletionPromises.push(
              admin
                .firestore()
                .collection("users")
                .doc(recipientId)
                .collection("devices")
                .doc(staleDocId)
                .delete()
            );
          }
        }
      });

      if (deletionPromises.length > 0) {
        await Promise.all(deletionPromises);
      }
    } catch (error) {
      console.error("Failed to send chat FCM notification:", error);
    }
  }
);
