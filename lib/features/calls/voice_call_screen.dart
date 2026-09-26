import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';

class VoiceCallScreen extends StatefulWidget {
  final String partnerName;
  final String? partnerPhoto;
  final String? callId;
  final String? partnerUid;
  final bool? isCaller;

  const VoiceCallScreen({
    super.key,
    required this.partnerName,
    this.partnerPhoto,
    this.callId,
    this.partnerUid,
    this.isCaller,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final WebRtcCallService _callService = WebRtcCallService.instance;
  late StreamSubscription<CallStatus> _statusSub;
  late StreamSubscription<int> _durationSub;

  int _seconds = 0;
  bool _isMuted = false;
  bool _isSpeaker = true;
  bool _hasPopped = false;

  void _safePop() {
    if (!_hasPopped && mounted) {
      _hasPopped = true;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  void _minimizeCall() {
    _callService.setMinimized(true);
    _safePop();
  }

  @override
  void initState() {
    super.initState();
    _callService.setMinimized(false);
    _isMuted = _callService.isMuted;
    _isSpeaker = _callService.isSpeakerOn;

    _durationSub = _callService.onDurationChanged.listen((sec) {
      if (mounted) setState(() => _seconds = sec);
    });

    _statusSub = _callService.onStatusChanged.listen((status) {
      if (status == CallStatus.ended ||
          status == CallStatus.declined ||
          status == CallStatus.failed) {
        _safePop();
      }
    });
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _durationSub.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _endCall() async {
    _callService.setMinimized(false);
    await _callService.endCall();
    _safePop();
  }

  void _toggleMute() {
    setState(() {
      _callService.toggleMute();
      _isMuted = _callService.isMuted;
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _callService.toggleSpeaker();
      _isSpeaker = _callService.isSpeakerOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _callService.status == CallStatus.connected
        ? 'Connected'
        : _callService.status == CallStatus.calling
            ? 'Calling...'
            : 'Ringing...';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090A12),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient cosmic radial glow
            Center(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6C5CE7).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Top App Bar: Back (Minimize) | Astra | More
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white70, size: 20),
                          tooltip: 'Minimize call',
                          onPressed: _minimizeCall,
                        ),
                      const Text(
                        'Astra',
                        style: TextStyle(
                          color: Color(0xFFA594F9),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz_rounded,
                            color: Colors.white70, size: 24),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Glowing Partner Circular Avatar
                Center(
                  child: Container(
                    width: 190,
                    height: 190,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 6,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.45),
                        width: 2.5,
                      ),
                    ),
                    child: CircleAvatar(
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
                                  color: Colors.white,
                                  fontSize: 54,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Partner Name
                Text(
                  widget.partnerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 6),

                // Connection status
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Color(0xFFA594F9),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 12),

                // Live Timer
                Text(
                  _formatDuration(_seconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 14),

                // Live Audio Diagnostics Pill
                StreamBuilder<CallDiagnostics>(
                  stream: _callService.onDiagnosticsChanged,
                  initialData: _callService.diagnostics,
                  builder: (context, diagSnap) {
                    final diag = diagSnap.data ?? const CallDiagnostics();
                    final kbSent = (diag.bytesSent / 1024).toStringAsFixed(1);
                    final kbRec = (diag.bytesReceived / 1024).toStringAsFixed(1);
                    final isConnected = _callService.status == CallStatus.connected;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isConnected
                              ? const Color(0xFF2ED573).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.signal_cellular_alt_rounded,
                            size: 15,
                            color: isConnected ? const Color(0xFF2ED573) : Colors.amberAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isConnected
                                ? 'Live Audio (↑$kbSent KB • ↓$kbRec KB)'
                                : 'Connecting...',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const Spacer(),

                // Bottom Action Buttons: Mute | Speaker | More
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildControl(
                        icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: 'Mute',
                        isActive: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildControl(
                        icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        label: 'Speaker',
                        isActive: _isSpeaker,
                        onTap: _toggleSpeaker,
                      ),
                      _buildControl(
                        icon: Icons.more_horiz_rounded,
                        label: 'More',
                        isActive: false,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Large Red End Call Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: _endCall,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4757),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF4757).withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'End Call',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildControl({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
