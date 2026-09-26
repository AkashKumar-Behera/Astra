import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/services/notification_service.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';
import 'video_call_screen.dart';
import 'voice_call_screen.dart';

/// Global In-Call Overlay
///
/// Provides in-app minimization support:
/// - Floating top bar for Voice calls with live timer, mute toggle, and hang up.
/// - Draggable PiP box for Video calls with live video stream.
/// Tapping the overlay re-opens the active call in fullscreen.
class GlobalInCallOverlay extends StatefulWidget {
  final Widget child;

  const GlobalInCallOverlay({super.key, required this.child});

  @override
  State<GlobalInCallOverlay> createState() => _GlobalInCallOverlayState();
}

class _GlobalInCallOverlayState extends State<GlobalInCallOverlay>
    with SingleTickerProviderStateMixin {
  final WebRtcCallService _callService = WebRtcCallService.instance;
  late final AnimationController _pulseController;

  double _pipX = 16.0;
  double _pipY = 100.0;

  StreamSubscription<CallStatus>? _statusSub;
  StreamSubscription<bool>? _minSub;
  StreamSubscription<int>? _durSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _statusSub = _callService.onStatusChanged.listen((_) {
      if (mounted) setState(() {});
    });

    _minSub = _callService.onMinimizedChanged.listen((_) {
      if (mounted) setState(() {});
    });

    _durSub = _callService.onDurationChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusSub?.cancel();
    _minSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  bool get _isCallActive {
    return _callService.status == CallStatus.connected ||
        _callService.status == CallStatus.calling ||
        _callService.status == CallStatus.ringing;
  }

  String _formatDuration(int totalSec) {
    final mins = (totalSec ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSec % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _maximizeCall() {
    _callService.setMinimized(false);

    if (_callService.currentCallType == CallType.video) {
      NotificationService.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            callId: _callService.currentCallId ?? '',
            partnerUid: _callService.currentPartnerUid ?? '',
            partnerName: _callService.currentPartnerName ?? 'Partner',
            partnerPhoto: _callService.currentPartnerPhoto,
            isCaller: _callService.currentRole == CallRole.caller,
          ),
        ),
      );
    } else {
      NotificationService.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => VoiceCallScreen(
            callId: _callService.currentCallId ?? '',
            partnerUid: _callService.currentPartnerUid ?? '',
            partnerName: _callService.currentPartnerName ?? 'Partner',
            partnerPhoto: _callService.currentPartnerPhoto,
            isCaller: _callService.currentRole == CallRole.caller,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = _isCallActive && _callService.isMinimized;

    return Stack(
      children: [
        widget.child,

        if (showOverlay && _callService.currentCallType == CallType.audio)
          _buildVoiceCallBar(context),

        if (showOverlay && _callService.currentCallType == CallType.video)
          _buildVideoCallPip(context),
      ],
    );
  }

  Widget _buildVoiceCallBar(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final partnerName = _callService.currentPartnerName ?? 'Partner';
    final partnerPhoto = _callService.currentPartnerPhoto;
    final isConnected = _callService.status == CallStatus.connected;
    final durationStr = isConnected
        ? _formatDuration(_callService.durationSeconds)
        : (_callService.status == CallStatus.calling ? 'Calling...' : 'Ringing...');

    return Positioned(
      top: topPadding + 6,
      left: 14,
      right: 14,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: _maximizeCall,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF131524).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFA594F9).withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                // Partner Avatar with pulsing green live dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                      backgroundImage: partnerPhoto != null ? NetworkImage(partnerPhoto) : null,
                      child: partnerPhoto == null
                          ? Text(
                              partnerName.isNotEmpty ? partnerName[0].toUpperCase() : 'P',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            )
                          : null,
                    ),
                    if (isConnected)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            return Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2ED573),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF131524), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2ED573).withValues(alpha: 0.4 + 0.4 * _pulseController.value),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name & Duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        partnerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isConnected ? Icons.phone_in_talk_rounded : Icons.ring_volume_rounded,
                            size: 11,
                            color: isConnected ? const Color(0xFF2ED573) : const Color(0xFFA594F9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            durationStr,
                            style: TextStyle(
                              color: isConnected ? const Color(0xFF2ED573) : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Mute button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _callService.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: _callService.isMuted ? Colors.redAccent : Colors.white70,
                    size: 20,
                  ),
                  onPressed: () {
                    _callService.toggleMute();
                    setState(() {});
                  },
                ),

                const SizedBox(width: 4),

                // End call button
                GestureDetector(
                  onTap: () async {
                    await _callService.endCall();
                    if (mounted) setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4757),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCallPip(BuildContext context) {
    return Positioned(
      top: _pipY,
      right: _pipX,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipX = (_pipX - details.delta.dx).clamp(10.0, MediaQuery.of(context).size.width - 130);
            _pipY = (_pipY + details.delta.dy).clamp(60.0, MediaQuery.of(context).size.height - 200);
          });
        },
        onTap: _maximizeCall,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 120,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFA594F9).withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video feed (remote renderer fallback to local)
                  _callService.remoteRenderer.srcObject != null
                      ? RTCVideoView(
                          _callService.remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : (_callService.localRenderer.srcObject != null
                          ? RTCVideoView(
                              _callService.localRenderer,
                              mirror: _callService.isFrontCamera,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : Container(
                              color: const Color(0xFF131522),
                              child: const Center(
                                child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 28),
                              ),
                            )),

                  // Gradient overlay
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top controls (Maximize icon + End call)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () async {
                        await _callService.endCall();
                        if (mounted) setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4757),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 4,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _formatDuration(_callService.durationSeconds),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
