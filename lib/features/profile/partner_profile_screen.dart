import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/presence_service.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';
import '../calls/voice_call_screen.dart';
import '../calls/video_call_screen.dart';
import '../chat/chat_screen.dart';

class PartnerProfileScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final String? partnerPhoto;
  final String? locationName;
  final double? distanceKm;
  final VoidCallback? onRemoveConnection;

  const PartnerProfileScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.partnerPhoto,
    this.locationName,
    this.distanceKm,
    this.onRemoveConnection,
  });

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _startCall(CallType type) async {
    if (_myUid.isEmpty) return;

    await WebRtcCallService.instance.startCall(
      myUid: _myUid,
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

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          partnerUid: widget.partnerUid,
          partnerName: widget.partnerName,
          partnerPhoto: widget.partnerPhoto,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background celestial curve/glow
          Positioned(
            top: -60,
            left: -100,
            right: -100,
            height: 380,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4834D4).withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  // Top Bar: Back | Astra | More
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white70, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 20, color: Color(0xFFA594F9)),
                          SizedBox(height: 2),
                          Text(
                            'Astra',
                            style: TextStyle(
                              color: Color(0xFFA594F9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz_rounded,
                            color: Colors.white70, size: 24),
                        onPressed: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Avatar with presence dot
                  StreamBuilder<PartnerPresence>(
                    stream: PresenceService.streamPartnerPresence(widget.partnerUid),
                    builder: (context, snapshot) {
                      final isOnline = snapshot.data?.isOnline ?? false;
                      final statusLabel = isOnline
                          ? '🟢 Online'
                          : (snapshot.data?.statusText ?? 'Offline');

                      return Column(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 140,
                                height: 140,
                                padding: const EdgeInsets.all(3.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                                      blurRadius: 30,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 2,
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
                                              fontSize: 44,
                                              fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                              ),
                              if (isOnline)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2ED573),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF090A12),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Name
                          Text(
                            widget.partnerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Status text
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: isOnline
                                  ? const Color(0xFF2ED573)
                                  : Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                          const SizedBox(height: 2),

                          const Text(
                            'Here with you • Always',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // 3 Action Buttons: Call | Video | Chat
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.call_rounded,
                          label: 'Call',
                          onTap: () => _startCall(CallType.audio),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          onTap: () => _startCall(CallType.video),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionTile(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Chat',
                          onTap: _openChat,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Live Location Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131522),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.near_me_rounded,
                                  color: Color(0xFFA594F9), size: 18),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Live Location',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Updated just now',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.white38, size: 20),
                          ],
                        ),

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  color: Color(0xFFA594F9), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.locationName ?? 'Bhubaneswar, Odisha',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${widget.distanceKm?.toStringAsFixed(1) ?? "1.2"} km away • 2 min ago',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4834D4),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'View on Map',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Shared with you Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131522),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            color: Color(0xFFA594F9), size: 22),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shared with you',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Live location is on',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.white38, size: 20),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Settings Tiles Container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131522),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildSettingRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Notifications',
                          trailingText: 'On',
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.05)),
                        _buildSettingRow(
                          icon: Icons.near_me_outlined,
                          label: 'Location sharing',
                          trailingText: 'While using app',
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.05)),
                        _buildSettingRow(
                          icon: Icons.shield_outlined,
                          label: 'Privacy',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Remove Connection Outlined Button
                  GestureDetector(
                    onTap: widget.onRemoveConnection,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4757).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFFF4757).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_remove_outlined,
                              color: Color(0xFFFF6B81), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Remove connection',
                            style: TextStyle(
                              color: Color(0xFFFF6B81),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'This will remove your connection on Astra.\nYou can always add them again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF131522),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFA594F9), size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    String? trailingText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
        ],
      ),
    );
  }
}
