import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/chat_message_model.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/presence_service.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/services/r2_storage_service.dart';
import '../../core/theme/astra_theme.dart';
import '../../core/services/notification_service.dart';
import '../calls/voice_call_screen.dart';
import '../calls/video_call_screen.dart';
import '../profile/partner_profile_screen.dart';
import 'voice_note_sheet.dart';

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
  final ImagePicker _picker = ImagePicker();

  late final ChatService _chatService;
  StreamSubscription<List<ChatMessageModel>>? _messagesSubscription;

  List<ChatMessageModel> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSending = false;

  ChatMessageModel? _replyingTo;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _conversationId;

  @override
  void initState() {
    super.initState();
    _chatService = widget.chatService ?? ChatService();

    if (_currentUid.isNotEmpty && widget.partnerUid.isNotEmpty) {
      _conversationId = ChatService.getConversationId(_currentUid, widget.partnerUid);
      NotificationService.activeConversationId = _conversationId;
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

    _chatService.getOrCreateConversation(recipientUid: widget.partnerUid).then(
      (_) {},
      onError: (_) {},
    );

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

  Future<void> _sendMessage({
    String? customText,
    MessageType type = MessageType.text,
    String? mediaUrl,
    int? audioDurationSec,
  }) async {
    final text = (customText ?? _textController.text).trim();
    if (text.isEmpty && mediaUrl == null) return;
    if (_isSending) return;

    final reply = _replyingTo;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });
    if (customText == null) {
      _textController.clear();
    }

    try {
      await _chatService.sendMessage(
        conversationId: _conversationId,
        recipientUid: widget.partnerUid,
        text: text.isNotEmpty ? text : (type == MessageType.image ? 'Photo' : 'Media'),
        type: type,
        replyToId: reply?.id,
        replyToText: reply?.decryptedText ?? (reply?.type == MessageType.image ? 'Photo' : null),
        replyToSender: reply != null
            ? (reply.senderId == _currentUid ? 'You' : widget.partnerName)
            : null,
        mediaUrl: mediaUrl,
        audioDurationSec: audioDurationSec,
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

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
      if (picked == null) return;

      final file = File(picked.path);
      final remotePath = 'chats/$_conversationId/images/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final publicUrl = await R2StorageService.uploadFile(
        file: file,
        remotePath: remotePath,
        contentType: 'image/jpeg',
      );

      await _sendMessage(
        customText: 'Photo',
        type: MessageType.image,
        mediaUrl: publicUrl,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AstraTheme.accentDanger,
            content: Text('Failed to send image: $e'),
          ),
        );
      }
    }
  }

  void _openVoiceNoteSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VoiceNoteSheet(
        onSend: (durationSec) {
          _sendMessage(
            customText: 'Voice note (${durationSec}s)',
            type: MessageType.audio,
            audioDurationSec: durationSec,
          );
        },
        onCancel: () {},
      ),
    );
  }

  Future<void> _startCall(CallType type) async {
    if (_currentUid.isEmpty) return;

    await WebRtcCallService.instance.startCall(
      myUid: _currentUid,
      partnerUid: widget.partnerUid,
      partnerName: widget.partnerName,
      partnerPhoto: widget.partnerPhoto,
      type: type,
    );

    if (mounted) {
      if (type == CallType.video) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              partnerName: widget.partnerName,
              partnerPhoto: widget.partnerPhoto,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VoiceCallScreen(
              partnerName: widget.partnerName,
              partnerPhoto: widget.partnerPhoto,
            ),
          ),
        );
      }
    }
  }

  void _openPartnerProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PartnerProfileScreen(
          partnerUid: widget.partnerUid,
          partnerName: widget.partnerName,
          partnerPhoto: widget.partnerPhoto,
        ),
      ),
    );
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
    if (NotificationService.activeConversationId == _conversationId) {
      NotificationService.activeConversationId = null;
    }
    _messagesSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimestamp(int timestampMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hours = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final minutes = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hours:$minutes $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A12),
      appBar: _buildAppBar(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient cosmic background gradient
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 300,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, 1.0),
                  radius: 1.2,
                  colors: [
                    const Color(0xFF4834D4).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              // Message List Area
              Expanded(
                child: _buildBody(),
              ),

              // Active Reply Banner (if user swiped to reply)
              if (_replyingTo != null) _buildReplyPreviewBanner(),

              // Message Input Bar
              _buildInputBar(),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0F1A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: _openPartnerProfile,
        child: Row(
          children: [
            // Avatar with live presence dot
            StreamBuilder<PartnerPresence>(
              stream: PresenceService.streamPartnerPresence(widget.partnerUid),
              builder: (context, presenceSnap) {
                final isOnline = presenceSnap.data?.isOnline ?? widget.isOnline;

                return Stack(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                      backgroundImage: widget.partnerPhoto != null
                          ? NetworkImage(widget.partnerPhoto!)
                          : null,
                      child: widget.partnerPhoto == null
                          ? Text(
                              widget.partnerName.isNotEmpty
                                  ? widget.partnerName[0].toUpperCase()
                                  : 'P',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF2ED573)
                              : Colors.white30,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF0D0F1A), width: 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partnerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  StreamBuilder<PartnerPresence>(
                    stream: PresenceService.streamPartnerPresence(widget.partnerUid),
                    builder: (context, presenceSnap) {
                      final isOnline = presenceSnap.data?.isOnline ?? widget.isOnline;
                      final status = isOnline
                          ? '🟢 Online'
                          : (presenceSnap.data?.statusText ?? 'Offline');

                      return Text(
                        status,
                        style: TextStyle(
                          color: isOnline
                              ? const Color(0xFF2ED573)
                              : Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
          onPressed: () => _startCall(CallType.audio),
        ),
        IconButton(
          icon: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
          onPressed: () => _startCall(CallType.video),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 24),
          onPressed: _openPartnerProfile,
        ),
      ],
    );
  }

  Widget _buildReplyPreviewBanner() {
    final reply = _replyingTo!;
    final isMe = reply.senderId == _currentUid;
    final senderName = isMe ? 'You' : widget.partnerName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161828),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFA594F9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $senderName',
                  style: const TextStyle(
                    color: Color(0xFFA594F9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.decryptedText ?? 'Message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFA594F9),
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
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AstraTheme.primaryLight, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Say Hi to ${widget.partnerName}!',
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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

        return Dismissible(
          key: Key('msg_${msg.id}_$index'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            HapticFeedback.lightImpact();
            setState(() => _replyingTo = msg);
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 16),
            child: const Icon(Icons.reply_rounded, color: Color(0xFFA594F9), size: 24),
          ),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFF4834D4), Color(0xFF6C5CE7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : const Color(0xFF171A29),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Quoted Reply Card inside Bubble
                  if (msg.replyToText != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(
                            color: isMe
                                ? const Color(0xFFA594F9)
                                : const Color(0xFF00CEC9),
                            width: 3,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.replyToSender ?? 'Partner',
                            style: TextStyle(
                              color: isMe
                                  ? const Color(0xFFA594F9)
                                  : const Color(0xFF00CEC9),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            msg.replyToText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Decrypted text / Voice Note / Media / Error
                  if (msg.decryptionError != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_rounded,
                            size: 14, color: AstraTheme.accentDanger),
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
                  ] else if (msg.type == MessageType.audio) ...[
                    // Audio Waveform Voice Note Pill
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 24,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(16, (i) {
                                final h = (i % 4 + 2) * 4.0;
                                return Container(
                                  width: 2.5,
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '0:${(msg.audioDurationSec ?? 12).toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ] else if (msg.type == MessageType.image && msg.mediaUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        msg.mediaUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 160,
                            color: Colors.white10,
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (msg.decryptedText != null &&
                        msg.decryptedText!.isNotEmpty &&
                        msg.decryptedText != 'Photo') ...[
                      const SizedBox(height: 6),
                      Text(
                        msg.decryptedText!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14.5, height: 1.3),
                      ),
                    ],
                  ] else ...[
                    Text(
                      msg.decryptedText ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14.5, height: 1.3),
                    ),
                  ],

                  const SizedBox(height: 4),

                  // Time & Read Status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          msg.status == MessageStatus.failed
                              ? Icons.error_outline_rounded
                              : Icons.done_all_rounded,
                          size: 13,
                          color: msg.status == MessageStatus.failed
                              ? AstraTheme.accentDanger
                              : const Color(0xFF70A1FF),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          // Plus Button
          IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white70, size: 20),
            ),
            onPressed: _pickAndSendImage,
          ),

          // Text Field Container
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF161828),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        hintStyle:
                            TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Colors.white54, size: 20),
                    onPressed: _pickAndSendImage,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.mic_none_rounded,
                        color: Colors.white54, size: 22),
                    onPressed: _openVoiceNoteSheet,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send / Voice Button
          GestureDetector(
            onTap: () {
              if (_textController.text.trim().isNotEmpty) {
                _sendMessage();
              } else {
                _openVoiceNoteSheet();
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                _textController.text.trim().isNotEmpty
                    ? Icons.send_rounded
                    : Icons.graphic_eq_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
