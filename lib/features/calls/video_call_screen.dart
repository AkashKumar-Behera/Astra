import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';

class VideoCallScreen extends StatefulWidget {
  final String partnerName;
  final String? partnerPhoto;
  final String? callId;
  final String? partnerUid;
  final bool? isCaller;

  const VideoCallScreen({
    super.key,
    required this.partnerName,
    this.partnerPhoto,
    this.callId,
    this.partnerUid,
    this.isCaller,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final WebRtcCallService _callService = WebRtcCallService.instance;

  late StreamSubscription<CallStatus> _statusSub;
  late StreamSubscription<int> _durationSub;
  late StreamSubscription<bool> _screenShareSub;

  int _seconds = 0;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeaker = true;
  bool _showControls = true;
  bool _isSwapped = false;
  bool _isScreenSharing = false;
  double _dragDistance = 0;
  Timer? _controlsTimer;

  double _pipX = 20;
  double _pipY = 100;
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
    _isCameraOff = _callService.isCameraOff;
    _isSpeaker = _callService.isSpeakerOn;
    _isScreenSharing = _callService.isScreenSharing;

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

    _screenShareSub = _callService.onScreenShareChanged.listen((sharing) {
      if (mounted) setState(() => _isScreenSharing = sharing);
    });

    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls) {
      _controlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetControlsTimer();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _statusSub.cancel();
    _durationSub.cancel();
    _screenShareSub.cancel();
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
    _resetControlsTimer();
  }

  void _toggleCamera() {
    setState(() {
      _callService.toggleCamera();
      _isCameraOff = _callService.isCameraOff;
    });
    _resetControlsTimer();
  }

  void _toggleSpeaker() {
    setState(() {
      _callService.toggleSpeaker();
      _isSpeaker = _callService.isSpeakerOn;
    });
    _resetControlsTimer();
  }

  Future<void> _switchCamera() async {
    await _callService.switchCamera();
    if (mounted) setState(() {});
    _resetControlsTimer();
  }

  Future<void> _toggleScreenShare() async {
    final success = await _callService.toggleScreenShare();
    if (!mounted) return;
    setState(() {
      _isScreenSharing = _callService.isScreenSharing;
    });
    _resetControlsTimer();
    if (success && _isScreenSharing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.screen_share_rounded, color: Color(0xFF00D2D3), size: 20),
              SizedBox(width: 10),
              Text('Live screen sharing active', style: TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: const Color(0xFF1E1F35),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainRenderer = _isSwapped ? _callService.localRenderer : _callService.remoteRenderer;
    final pipRenderer = _isSwapped ? _callService.remoteRenderer : _callService.localRenderer;
    final isMainLocal = _isSwapped;
    final isPipLocal = !_isSwapped;

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
            // 1. Fullscreen Main Video Feed (Tap to toggle controls)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  mainRenderer.srcObject != null && (!isMainLocal || !_isCameraOff)
                      ? RTCVideoView(
                          mainRenderer,
                          mirror: isMainLocal && _callService.isFrontCamera,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Container(
                          color: const Color(0xFF131522),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 54,
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
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _callService.status == CallStatus.connected
                                      ? (isMainLocal ? 'Your camera is off' : 'Camera paused')
                                      : 'Connecting video...',
                                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),

                  // Subtle dark gradient overlays for controls legibility
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _showControls ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 180,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.75),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 240,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.85),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Floating Picture-in-Picture (Tap to swap screen / Double tap switch)
            Positioned(
              top: _pipY,
              right: _pipX,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  _dragDistance = 0;
                },
                onPanUpdate: (details) {
                  _dragDistance += details.delta.distance;
                  setState(() {
                    _pipX = (_pipX - details.delta.dx).clamp(16.0, 200.0);
                    _pipY = (_pipY + details.delta.dy).clamp(80.0, 500.0);
                  });
                },
                onPanEnd: (_) {
                  if (_dragDistance < 10) {
                    setState(() {
                      _isSwapped = !_isSwapped;
                    });
                    _resetControlsTimer();
                  }
                },
                onTap: () {
                  setState(() {
                    _isSwapped = !_isSwapped;
                  });
                  _resetControlsTimer();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 110,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFA594F9).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                          blurRadius: 16,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        pipRenderer.srcObject != null && (!isPipLocal || !_isCameraOff)
                            ? RTCVideoView(
                                pipRenderer,
                                mirror: isPipLocal && _callService.isFrontCamera,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                              )
                            : Center(
                                child: Icon(
                                  isPipLocal ? Icons.videocam_off_rounded : Icons.person_rounded,
                                  color: Colors.white54,
                                  size: 28,
                                ),
                              ),

                        // Switch Camera / Swap Badge
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _switchCamera,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cameraswitch_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),

                        // Swap hint icon
                        Positioned(
                          top: 6,
                          left: 6,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() {
                                _isSwapped = !_isSwapped;
                              });
                              _resetControlsTimer();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.swap_horiz_rounded,
                                color: Colors.white70,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Animated Overlay Controls (Top bar & Bottom controls)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top Header Area: Back (Minimize) | Astra | More
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white, size: 20),
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
                                  color: Colors.white, size: 24),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Partner Name
                      Text(
                        widget.partnerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Timer
                      Text(
                        _formatDuration(_seconds),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // "📶 Live diagnostics" pill badge
                      StreamBuilder<CallDiagnostics>(
                        stream: _callService.onDiagnosticsChanged,
                        initialData: _callService.diagnostics,
                        builder: (context, diagSnap) {
                          final diag = diagSnap.data ?? const CallDiagnostics();
                          final kbSent = (diag.bytesSent / 1024).toStringAsFixed(1);
                          final kbRec = (diag.bytesReceived / 1024).toStringAsFixed(1);
                          final isConnected = _callService.status == CallStatus.connected;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isConnected
                                    ? const Color(0xFF2ED573).withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isConnected
                                      ? Icons.signal_cellular_alt_rounded
                                      : Icons.wifi_find_rounded,
                                  size: 13,
                                  color: isConnected
                                      ? const Color(0xFF2ED573)
                                      : const Color(0xFFFFA502),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isConnected
                                      ? 'Live Stream (↑$kbSent KB • ↓$kbRec KB)'
                                      : 'Connecting Media...',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // Screen Sharing Active Pill Indicator
                      if (_isScreenSharing)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D2D3).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF00D2D3), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D2D3).withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.screen_share_rounded, color: Color(0xFF00D2D3), size: 15),
                              const SizedBox(width: 6),
                              const Text(
                                'Screen sharing is active',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _toggleScreenShare,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF4757),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('Stop', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const Spacer(),

                      // Bottom Call Controls: Mute | Camera | Speaker | Flip | Screen Share
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildControl(
                              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              label: 'Mute',
                              isActive: _isMuted,
                              onTap: _toggleMute,
                            ),
                            _buildControl(
                              icon: _isCameraOff
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              label: 'Camera',
                              isActive: _isCameraOff,
                              onTap: _toggleCamera,
                            ),
                            _buildControl(
                              icon: _isSpeaker
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              label: 'Speaker',
                              isActive: _isSpeaker,
                              onTap: _toggleSpeaker,
                            ),
                            _buildControl(
                              icon: Icons.cameraswitch_rounded,
                              label: 'Flip',
                              isActive: false,
                              onTap: _switchCamera,
                            ),
                            _buildControl(
                              icon: _isScreenSharing
                                  ? Icons.stop_screen_share_rounded
                                  : Icons.screen_share_rounded,
                              label: _isScreenSharing ? 'Stop' : 'Share',
                              isActive: _isScreenSharing,
                              activeColor: const Color(0xFF00D2D3),
                              onTap: _toggleScreenShare,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Red End Call Button
                      Column(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _endCall,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4757),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF4757).withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'End Call',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
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
    Color? activeColor,
  }) {
    final effectiveActiveColor = activeColor ?? Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? effectiveActiveColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? effectiveActiveColor.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: effectiveActiveColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive && activeColor != null ? effectiveActiveColor : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive && activeColor != null ? effectiveActiveColor : Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
