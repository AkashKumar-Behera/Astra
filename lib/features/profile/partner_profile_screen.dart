import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/presence_service.dart';
import '../../core/services/reverse_geocoding_service.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/services/location_rtdb_service.dart';
import '../calls/voice_call_screen.dart';
import '../calls/video_call_screen.dart';
import '../chat/chat_screen.dart';

class PartnerProfileScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final String? partnerPhoto;
  final double? partnerLat;
  final double? partnerLng;
  final double? myLat;
  final double? myLng;
  final dynamic updatedAt;
  final VoidCallback? onRemoveConnection;

  const PartnerProfileScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.partnerPhoto,
    this.partnerLat,
    this.partnerLng,
    this.myLat,
    this.myLng,
    this.updatedAt,
    this.onRemoveConnection,
  });

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String _resolvedAddress = 'Locating...';
  bool _isLoadingAddress = false;
  double? _liveLat;
  double? _liveLng;
  dynamic _liveUpdatedAt;

  @override
  void initState() {
    super.initState();
    _liveLat = widget.partnerLat;
    _liveLng = widget.partnerLng;
    _liveUpdatedAt = widget.updatedAt;
    _loadLiveLocationAndAddress();
  }

  Future<void> _loadLiveLocationAndAddress() async {
    try {
      if (_liveLat == null || _liveLng == null) {
        final rtdbLoc = await LocationRtdbService.getPartnerLocation(widget.partnerUid);
        if (rtdbLoc != null && rtdbLoc['latitude'] != null) {
          if (mounted) {
            setState(() {
              _liveLat = (rtdbLoc['latitude'] as num).toDouble();
              _liveLng = (rtdbLoc['longitude'] as num).toDouble();
              _liveUpdatedAt = rtdbLoc['updatedAt'];
            });
          }
        }
      }

      if (_liveLat != null && _liveLng != null) {
        setState(() => _isLoadingAddress = true);
        final addr = await ReverseGeocodingService.getAddressFromCoordinates(_liveLat!, _liveLng!);
        if (mounted) {
          setState(() {
            _resolvedAddress = addr;
            _isLoadingAddress = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _resolvedAddress = 'Coordinates unavailable';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  String _formatDistance() {
    if (widget.myLat != null && widget.myLng != null && _liveLat != null && _liveLng != null) {
      final meters = Geolocator.distanceBetween(
        widget.myLat!,
        widget.myLng!,
        _liveLat!,
        _liveLng!,
      );
      if (meters < 1000) {
        return '${meters.round()} m away';
      } else {
        final km = meters / 1000.0;
        return '${km.toStringAsFixed(1)} km away';
      }
    }
    return '-- km away';
  }

  String _formatFreshness() {
    if (_liveUpdatedAt == null) return 'Live';
    int? ts;
    if (_liveUpdatedAt is num) ts = (_liveUpdatedAt as num).toInt();
    if (_liveUpdatedAt is String) ts = int.tryParse(_liveUpdatedAt as String);
    if (ts == null) return 'Live';

    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

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
      backgroundColor: const Color(0xFF07060E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background celestial nebula glow
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
                    const Color(0xFF8B5CF6).withValues(alpha: 0.20),
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
                  // Top Bar: Back | Astra Cosmic Title | More
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
                              size: 18, color: Color(0xFFA594F9)),
                          SizedBox(height: 2),
                          Text(
                            'Astra',
                            style: TextStyle(
                              color: Color(0xFFA594F9),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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

                  const SizedBox(height: 16),

                  // Avatar with Presence & Glowing Orbit
                  StreamBuilder<PartnerPresence>(
                    stream: PresenceService.streamPartnerPresence(widget.partnerUid),
                    builder: (context, snapshot) {
                      final isOnline = snapshot.data?.isOnline ?? false;
                      final statusLabel = isOnline
                          ? 'Online'
                          : (snapshot.data?.statusText ?? 'Offline');

                      return Column(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 130,
                                height: 130,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
                                      blurRadius: 36,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: const Color(0xFF8B5CF6),
                                    width: 2.2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: widget.partnerPhoto != null && widget.partnerPhoto!.isNotEmpty
                                      ? Image.network(
                                          widget.partnerPhoto!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: const Color(0xFF1E1B4B),
                                          child: Center(
                                            child: Text(
                                              widget.partnerName.isNotEmpty
                                                  ? widget.partnerName[0].toUpperCase()
                                                  : '✦',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 42,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: isOnline ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF07060E),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Name
                          Text(
                            widget.partnerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Status text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isOnline ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Online • Just now' : statusLabel,
                                style: TextStyle(
                                  color: isOnline ? const Color(0xFF10B981) : Colors.white60,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 3),

                          const Text(
                            'Here with you • Always',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 22),

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

                  const SizedBox(height: 18),

                  // Real Live Location Card (Geocoded)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121024),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF2A234E),
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
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.near_me_rounded,
                                  color: Color(0xFFC084FC), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Live Location',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Updated ${_formatFreshness()}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Color(0xFFA78BFA), size: 20),
                              onPressed: _loadLiveLocationAndAddress,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1733),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF322858)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  color: Color(0xFFC084FC), size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _isLoadingAddress
                                        ? const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                                          )
                                        : Text(
                                            _resolvedAddress,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_formatDistance()} • ${_formatFreshness()}',
                                      style: const TextStyle(
                                        color: Color(0xFFA594F9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6D28D9),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    'View on Map',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
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
                      color: const Color(0xFF121024),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF2A234E),
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
                                'Live continuous location is active',
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
                      color: const Color(0xFF121024),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF2A234E),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildSettingRow(
                          icon: Icons.notifications_none_rounded,
                          label: 'Notifications',
                          trailingText: 'On',
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.05)),
                        _buildSettingRow(
                          icon: Icons.near_me_outlined,
                          label: 'Location sharing',
                          trailingText: 'Realtime active',
                        ),
                        Divider(color: Colors.white.withValues(alpha: 0.05)),
                        _buildSettingRow(
                          icon: Icons.shield_outlined,
                          label: 'End-to-End Encryption',
                          trailingText: 'Active',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Remove Connection Button
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
          color: const Color(0xFF121024),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF2A234E),
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
                fontWeight: FontWeight.w600,
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
