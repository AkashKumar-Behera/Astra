import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/models/chat_message_model.dart';
import '../../core/services/chat_service.dart';
import '../../core/theme/astra_theme.dart';

/// ChatScreen
///
/// Production 1-to-1 encrypted chat screen for Astra.
///
/// Features:
/// - Deterministic canonical conversation routing via [ChatService]
/// - Real-time message streaming with in-memory decrypted text display
/// - Zero plaintext persistence to Firestore
/// - Never exposes ciphertext or keys to the user
/// - Controlled visual indicator for individual message decryption failures
/// - Clean subscription cancellation on widget dispose
class ChatScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final String? partnerPhoto;
  final bool isOnline;
  final ChatService? chatService;

  const ChatScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.partnerPhoto,
    this.isOnline = true,
    this.chatService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final ChatService _chatService;
  StreamSubscription<List<ChatMessageModel>>? _messagesSubscription;

  List<ChatMessageModel> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSending = false;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _conversationId;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatService();

    if (_currentUid.isNotEmpty && widget.partnerUid.isNotEmpty) {
      _conversationId = ChatService.getConversationId(_currentUid, widget.partnerUid);
      _initChatStream();
    } else {
      _isLoading = false;
      _errorMessage = 'Authentication or partner information missing.';
    }
  }

  void _initChatStream() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Ensure conversation metadata doc exists in background
    _chatService.getOrCreateConversation(recipientUid: widget.partnerUid).then(
      (_) {},
      onError: (_) {},
    );

    // Subscribe to encrypted message stream
    _messagesSubscription?.cancel();
    _messagesSubscription = _chatService
        .streamMessages(conversationId: _conversationId)
        .listen(
      (messages) {
        if (!mounted) return;
        setState(() {
          _messages = messages;
          _isLoading = false;
          _errorMessage = null;
        });
        _scrollToBottom();
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to sync messages. Please check connection.';
        });
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();

    try {
      await _chatService.sendMessage(
        conversationId: _conversationId,
        recipientUid: widget.partnerUid,
        text: text,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AstraTheme.accentDanger,
            content: Text('Failed to send message: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimestamp(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hours = dt.hour.toString().padLeft(2, '0');
    final minutes = dt.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      appBar: AppBar(
        backgroundColor: AstraTheme.cardSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                  backgroundImage: widget.partnerPhoto != null
                      ? NetworkImage(widget.partnerPhoto!)
                      : null,
                  child: widget.partnerPhoto == null
                      ? Text(
                          widget.partnerName.isNotEmpty
                              ? widget.partnerName[0].toUpperCase()
                              : 'P',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.isOnline ? AstraTheme.accentOnline : AstraTheme.accentOffline,
                      shape: BoxShape.circle,
                      border: Border.all(color: AstraTheme.cardSurface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partnerName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Row(
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 11,
                        color: AstraTheme.accentCyan,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Astra Encrypted (AES-256-GCM)',
                        style: TextStyle(
                          color: AstraTheme.accentCyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Message List Area
          Expanded(
            child: _buildBody(),
          ),

          // Message Input Bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AstraTheme.primaryLight,
        ),
      );
    }

    if (_errorMessage != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AstraTheme.accentDanger, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AstraTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _initChatStream,
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AstraTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded, color: AstraTheme.primaryLight, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Say Hi to ${widget.partnerName}!',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Messages are encrypted with AES-256-GCM before leaving your device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AstraTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.senderId == _currentUid;
        final timeStr = _formatTimestamp(msg.timestamp);

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AstraTheme.primary : AstraTheme.cardSurfaceLight,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Decrypted text or controlled decryption error badge
                if (msg.decryptionError != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_clock_rounded, size: 14, color: AstraTheme.accentDanger),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Message could not be decrypted',
                          style: TextStyle(
                            color: AstraTheme.accentDanger.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    msg.decryptedText ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3),
                  ),
                ],

                const SizedBox(height: 4),

                // Time & Status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        msg.status == MessageStatus.failed
                            ? Icons.error_outline_rounded
                            : Icons.done_all_rounded,
                        size: 12,
                        color: msg.status == MessageStatus.failed
                            ? AstraTheme.accentDanger
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(
        color: AstraTheme.cardSurface,
        border: Border(top: BorderSide(color: AstraTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AstraTheme.borderSubtle),
              ),
              child: TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: AstraTheme.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: _isSending ? AstraTheme.cardSurfaceLight : AstraTheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
