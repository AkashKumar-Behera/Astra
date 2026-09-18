import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../core/services/webrtc_chat_service.dart';
import '../../core/theme/astra_theme.dart';

class ChatMessage {
  final String text;
  final DateTime time;
  final bool isMe;

  ChatMessage({
    required this.text,
    required this.time,
    required this.isMe,
  });
}

class ChatScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final String? partnerPhoto;
  final bool isOnline;

  const ChatScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.partnerPhoto,
    this.isOnline = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  WebRtcChatService? _webRtcService;
  bool _isP2pConnected = false;
  StreamSubscription? _fallbackSub;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _roomKey {
    final list = [_currentUid, widget.partnerUid]..sort();
    return '${list[0]}_${list[1]}';
  }

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  void _initChat() {
    if (_currentUid.isEmpty) return;

    _webRtcService = WebRtcChatService(
      currentUid: _currentUid,
      partnerUid: widget.partnerUid,
      onMessageReceived: (text, time, isMe) {
        if (!mounted) return;
        setState(() {
          _messages.add(ChatMessage(text: text, time: time, isMe: isMe));
        });
        _scrollToBottom();
      },
      onConnectionStateChanged: (isConnected) {
        if (!mounted) return;
        setState(() => _isP2pConnected = isConnected);
      },
    );

    _webRtcService?.init();

    // Listen to fallback RTDB messages
    _fallbackSub = _rtdb.ref('chat_fallback/$_roomKey').onChildAdded.listen((event) {
      if (event.snapshot.value == null) return;
      try {
        final val = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final sender = val['sender'] as String? ?? '';
        if (sender != _currentUid) {
          final text = val['text'] as String? ?? '';
          final time = val['time'] != null
              ? DateTime.fromMillisecondsSinceEpoch(val['time'] as int)
              : DateTime.now();

          if (!mounted) return;
          setState(() {
            // Avoid duplicate if already received via WebRTC
            if (!_messages.any((m) => m.text == text && m.time.difference(time).inSeconds.abs() < 2)) {
              _messages.add(ChatMessage(text: text, time: time, isMe: false));
            }
          });
          _scrollToBottom();
        }
      } catch (_) {}
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    _webRtcService?.sendMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _fallbackSub?.cancel();
    _webRtcService?.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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
                  Row(
                    children: [
                      Icon(
                        _isP2pConnected ? Icons.lock_outline : Icons.sync,
                        size: 11,
                        color: _isP2pConnected ? AstraTheme.accentCyan : AstraTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isP2pConnected ? 'WebRTC P2P Direct' : 'Connecting direct tunnel...',
                        style: TextStyle(
                          color: _isP2pConnected ? AstraTheme.accentCyan : AstraTheme.textMuted,
                          fontSize: 11,
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
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AstraTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chat_bubble_outline, color: AstraTheme.primaryLight, size: 36),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Say Hi to ${widget.partnerName}!',
                          style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Messages are sent peer-to-peer over WebRTC.',
                          style: TextStyle(color: AstraTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final timeStr = '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}';

                      return Align(
                        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: msg.isMe ? AstraTheme.primary : AstraTheme.cardSurfaceLight,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: msg.isMe ? const Radius.circular(18) : const Radius.circular(4),
                              bottomRight: msg.isMe ? const Radius.circular(4) : const Radius.circular(18),
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
                            crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.text,
                                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3),
                              ),
                              const SizedBox(height: 4),
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
                                  if (msg.isMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.done_all, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Input Bar
          Container(
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
            decoration: BoxDecoration(
              color: AstraTheme.cardSurface,
              border: const Border(top: BorderSide(color: AstraTheme.borderSubtle)),
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
                  decoration: const BoxDecoration(
                    color: AstraTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
