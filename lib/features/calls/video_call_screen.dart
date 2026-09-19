import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';

class VideoCallScreen extends StatefulWidget {
  final String partnerName;
  final String? partnerPhoto;

  const VideoCallScreen({
    super.key,
    required this.partnerName,
    this.partnerPhoto,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final WebRtcCallService _callService = WebRtcCallService.instance;
  late StreamSubscription<CallStatus> _statusSub;
  late StreamSubscription<int> _durationSub;

  int _seconds = 0;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeaker = true;

  double _pipX = 20;
  double _pipY = 100;

  @override
  void initState() {
    super.initState();
    _isMuted = _callService.isMuted;
    _isCameraOff = _callService.isCameraOff;
    _isSpeaker = _callService.isSpeakerOn;

    _durationSub = _callService.onDurationChanged.listen((sec) {
      if (mounted) setState(() => _seconds = sec);
    });

    _statusSub = _callService.onStatusChanged.listen((status) {
      if (status == CallStatus.ended ||
          status == CallStatus.declined ||
          status == CallStatus.failed) {
        if (mounted) Navigator.of(context).pop();
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
    await _callService.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMute() {
    setState(() {
      _callService.toggleMute();
      _isMuted = _callService.isMuted;
    });
  }

  void _toggleCamera() {
    setState(() {
      _callService.toggleCamera();
      _isCameraOff = _callService.isCameraOff;
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _callService.toggleSpeaker();
      _isSpeaker = _callService.isSpeakerOn;
    });
  }

  Future<void> _switchCamera() async {
    await _callService.switchCamera();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Remote Video Feed (Fullscreen)
          _callService.remoteRenderer.srcObject != null
              ? RTCVideoView(
                  _callService.remoteRenderer,
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
                                      fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _callService.status == CallStatus.connected
                              ? 'Camera paused'
                              : 'Connecting video...',
                          style: const TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),

          // Dark gradient overlays top and bottom for UI controls readability
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

          // Floating Picture-in-Picture (Local Camera Feed)
          Positioned(
            top: _pipY,
            right: _pipX,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pipX = (_pipX - details.delta.dx).clamp(16.0, 200.0);
                  _pipY = (_pipY + details.delta.dy).clamp(80.0, 500.0);
                });
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
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      !_isCameraOff && _callService.localRenderer.srcObject != null
                          ? RTCVideoView(
                              _callService.localRenderer,
                              mirror: _callService.isFrontCamera,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : const Center(
                              child: Icon(Icons.videocam_off_rounded,
                                  color: Colors.white54, size: 28),
                            ),

                      // Switch Camera Overlay Button
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: GestureDetector(
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
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Top Header Area: Back | Astra | More & Call Info
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: _endCall,
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

                // "📶 Good connection" pill badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.signal_cellular_alt_rounded,
                          size: 14, color: Color(0xFF2ED573)),
                      SizedBox(width: 6),
                      Text(
                        'Good connection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom Call Controls: Mute | Camera | Speaker | More
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
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
                        icon: Icons.more_horiz_rounded,
                        label: 'More',
                        isActive: false,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Red End Call Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: _endCall,
                      child: Container(
                        width: 72,
                        height: 72,
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
                          size: 32,
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

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
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
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
