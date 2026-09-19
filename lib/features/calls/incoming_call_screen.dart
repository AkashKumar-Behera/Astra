import 'package:flutter/material.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';
import 'voice_call_screen.dart';
import 'video_call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final String callId;
  final String callerUid;
  final String callerName;
  final String? callerPhoto;
  final CallType type;
  final String myUid;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerUid,
    required this.callerName,
    this.callerPhoto,
    required this.type,
    required this.myUid,
  });

  Future<void> _accept(BuildContext context) async {
    final callService = WebRtcCallService.instance;
    await callService.answerCall(
      callId: callId,
      myUid: myUid,
      callerUid: callerUid,
      type: type,
    );

    if (context.mounted) {
      if (type == CallType.video) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              partnerName: callerName,
              partnerPhoto: callerPhoto,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VoiceCallScreen(
              partnerName: callerName,
              partnerPhoto: callerPhoto,
            ),
          ),
        );
      }
    }
  }

  Future<void> _decline(BuildContext context) async {
    await WebRtcCallService.instance.declineCall(
      callId: callId,
      myUid: myUid,
    );
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = type == CallType.video;

    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient blurred glowing background
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isVideo ? const Color(0xFF6C5CE7) : const Color(0xFF00B894))
                        .withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 50),

                // Large Glowing Avatar
                Center(
                  child: Container(
                    width: 170,
                    height: 170,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isVideo ? const Color(0xFF8C7AE6) : const Color(0xFF00CEC9))
                              .withValues(alpha: 0.45),
                          blurRadius: 36,
                          spreadRadius: 4,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                      backgroundImage:
                          callerPhoto != null ? NetworkImage(callerPhoto!) : null,
                      child: callerPhoto == null
                          ? Text(
                              callerName.isNotEmpty ? callerName[0].toUpperCase() : 'P',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Caller Name
                Text(
                  callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 10),

                // Call Type Pill / Subtitle
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      size: 18,
                      color: const Color(0xFFA594F9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isVideo ? 'Incoming Video Call' : 'Incoming Audio Call',
                      style: const TextStyle(
                        color: Color(0xFFA594F9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Secondary Action Row (Message instead / Remind me)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSecondaryAction(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message\ninstead',
                        onTap: () => _decline(context),
                      ),
                      _buildSecondaryAction(
                        icon: Icons.access_alarm_rounded,
                        label: 'Remind\nme',
                        onTap: () => _decline(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Primary Action Row (Decline / Accept)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Decline (Red)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: () => _decline(context),
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4757),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF4757).withValues(alpha: 0.45),
                                    blurRadius: 20,
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
                            'Decline',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      // Accept (Green for Audio, Purple for Video)
                      Column(
                        children: [
                          GestureDetector(
                            onTap: () => _accept(context),
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: isVideo
                                    ? const Color(0xFF6C5CE7)
                                    : const Color(0xFF2ED573),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isVideo
                                            ? const Color(0xFF6C5CE7)
                                            : const Color(0xFF2ED573))
                                        .withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isVideo
                                    ? Icons.videocam_rounded
                                    : Icons.call_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Accept',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
