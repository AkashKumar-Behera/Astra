import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/astra_theme.dart';
import '../auth/phone_auth_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userName;
  final String? photoUrl;

  const HomeScreen({
    super.key,
    required this.userName,
    this.photoUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  bool _isGettingLocation = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isGettingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isGettingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isGettingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isGettingLocation = false;
        });
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await AuthService.updateUserLocation(
          uid: uid,
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _openContactsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ContactsAndSearchModal(),
    );
  }

  void _openSettingsModal(String myPhone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: AstraTheme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AstraTheme.borderSubtle),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AstraTheme.primary.withValues(alpha: 0.2),
                    backgroundImage: widget.photoUrl != null
                        ? NetworkImage(widget.photoUrl!)
                        : null,
                    child: widget.photoUrl == null
                        ? Text(
                            widget.userName.isNotEmpty
                                ? widget.userName[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          myPhone.isNotEmpty ? myPhone : 'Connected via Astra',
                          style: const TextStyle(
                            color: AstraTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: AstraTheme.borderSubtle),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.location_on_outlined,
                      color: AstraTheme.accentCyan, size: 20),
                ),
                title: const Text(
                  'Refresh My GPS Location',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: Text(
                  _currentPosition != null
                      ? 'Lat: ${_currentPosition!.latitude.toStringAsFixed(3)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(3)}'
                      : 'Not acquired yet',
                  style: const TextStyle(
                      color: AstraTheme.textSecondary, fontSize: 12),
                ),
                trailing: _isGettingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AstraTheme.primary),
                      )
                    : const Icon(Icons.refresh, color: Colors.white70, size: 20),
                onTap: _isGettingLocation ? null : _initLocation,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout,
                      color: Colors.redAccent, size: 20),
                ),
                title: const Text(
                  'Log Out',
                  style: TextStyle(color: Colors.redAccent, fontSize: 15),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await AuthService.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const PhoneAuthScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _callPartner(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _disconnectPartner(String currentUid, String partnerUid, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AstraTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Disconnect from $name?',
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text(
          'You will no longer share live radar and location with each other.',
          style: TextStyle(color: AstraTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AstraTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AstraTheme.accentDanger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService.removeConnection(
                currentUid: currentUid,
                targetUid: partnerUid,
              );
            },
            child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double? myLat, double? myLng, double? pLat, double? pLng) {
    if (myLat == null || myLng == null || pLat == null || pLng == null) {
      return 'Location unavailable';
    }
    final meters = Geolocator.distanceBetween(myLat, myLng, pLat, pLng);
    if (meters < 1000) {
      return '${meters.round()} m away';
    } else {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km away';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AuthService.streamUser(currentUser.uid),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data();
        final myPhone = (userData?['phoneNumber'] as String?) ?? '';
        final connections = List<String>.from(userData?['connections'] ?? []);
        final String? partnerUid =
            connections.isNotEmpty ? connections.first : null;

        return Scaffold(
          backgroundColor: AstraTheme.background,
          body: Stack(
            children: [
              // Background Space Graphic
              Positioned.fill(
                child: Image.asset(
                  'assets/images/Bg image.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),

              // Cosmic Dark Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AstraTheme.background.withValues(alpha: 0.4),
                        AstraTheme.background.withValues(alpha: 0.75),
                        AstraTheme.background,
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  children: [
                    // Top App Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => _openSettingsModal(myPhone),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: AstraTheme.primary
                                          .withValues(alpha: 0.3),
                                      backgroundImage: widget.photoUrl != null
                                          ? NetworkImage(widget.photoUrl!)
                                          : null,
                                      child: widget.photoUrl == null
                                          ? Text(
                                              widget.userName.isNotEmpty
                                                  ? widget.userName[0]
                                                      .toUpperCase()
                                                  : 'U',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                                          color: AstraTheme.accentOnline,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AstraTheme.background,
                                              width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          _currentPosition != null
                                              ? 'GPS Active'
                                              : 'Acquiring GPS...',
                                          style: const TextStyle(
                                            color: AstraTheme.accentCyan,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Right actions: Add friend / Settings
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.person_add_alt_1_outlined,
                                    color: Colors.white70, size: 22),
                                onPressed: _openContactsModal,
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_vert,
                                    color: Colors.white70, size: 22),
                                onPressed: () => _openSettingsModal(myPhone),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Main Body: Connected Partner Radar OR Empty State
                    Expanded(
                      child: partnerUid == null
                          ? _buildEmptyState()
                          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: AuthService.streamPartner(partnerUid),
                              builder: (context, partnerSnap) {
                                final pData = partnerSnap.data?.data();
                                return _buildPartnerScreen(
                                  currentUser.uid,
                                  partnerUid,
                                  pData,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // EMPTY STATE: Screen5 with central glowing '+' Button
  // -------------------------------------------------------------
  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        // Radar circle with pulsating '+'
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return CustomPaint(
              painter: _EmptyPulsePainter(_pulseController.value),
              child: SizedBox(
                width: 220,
                height: 220,
                child: Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AstraTheme.primary, AstraTheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AstraTheme.primary.withValues(alpha: 0.5),
                          blurRadius: 28,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(38),
                        onTap: _openContactsModal,
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        const Text(
          'Connect Your Space',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Tap + to discover friends from your contacts using Astra or invite them via WhatsApp.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AstraTheme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _openContactsModal,
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text(
            'Add Friend from Contacts',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AstraTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 8,
            shadowColor: AstraTheme.primary.withValues(alpha: 0.5),
          ),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  // -------------------------------------------------------------
  // PARTNER VIEW: Screen5 Matching Cosmic Radar & Bottom Card
  // -------------------------------------------------------------
  Widget _buildPartnerScreen(
    String currentUid,
    String partnerUid,
    Map<String, dynamic>? partnerData,
  ) {
    final name = (partnerData?['name'] as String?) ?? 'Partner';
    final photoUrl = partnerData?['photoUrl'] as String?;
    final phone = (partnerData?['phoneNumber'] as String?) ?? '';
    final isOnline = partnerData?['isOnline'] as bool? ?? false;
    final partnerLat = (partnerData?['latitude'] as num?)?.toDouble();
    final partnerLng = (partnerData?['longitude'] as num?)?.toDouble();

    final myLat = _currentPosition?.latitude;
    final myLng = _currentPosition?.longitude;

    final distanceText = _formatDistance(myLat, myLng, partnerLat, partnerLng);

    return Column(
      children: [
        const SizedBox(height: 10),

        // Radar Visual with Center Partner Avatar
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      painter: _CosmicRadarPainter(
                        pulseVal: _pulseController.value,
                        isOnline: isOnline,
                      ),
                      size: const Size(280, 280),
                    ),

                    // Center Avatar with Live Glow
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline
                                    ? AstraTheme.accentOnline
                                    : AstraTheme.primary)
                                .withValues(alpha: 0.4),
                            blurRadius: 22,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: AstraTheme.cardSurface,
                        backgroundImage: photoUrl != null
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),

                    // Live Status Pill on Radar
                    Positioned(
                      bottom: 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AstraTheme.cardSurface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isOnline
                                ? AstraTheme.accentOnline.withValues(alpha: 0.5)
                                : AstraTheme.borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? AstraTheme.accentOnline
                                    : AstraTheme.accentOffline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isOnline ? 'Online now' : 'Offline',
                              style: TextStyle(
                                color: isOnline
                                    ? AstraTheme.accentOnline
                                    : AstraTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Partner Info Bottom Card (Glassmorphic)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AstraTheme.cardSurface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AstraTheme.borderSubtle,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AstraTheme.primary.withValues(alpha: 0.25),
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'P',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.near_me,
                              size: 13,
                              color: AstraTheme.accentCyan,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distanceText,
                              style: const TextStyle(
                                color: AstraTheme.accentCyan,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Disconnect Menu
                  IconButton(
                    icon: const Icon(Icons.link_off,
                        color: AstraTheme.textMuted, size: 22),
                    tooltip: 'Disconnect',
                    onPressed: () =>
                        _disconnectPartner(currentUid, partnerUid, name),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(color: AstraTheme.borderSubtle, height: 1),
              const SizedBox(height: 16),

              // Action Buttons: Call & Change Friend
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openContactsModal(),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change Friend',
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: AstraTheme.borderSubtle),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: phone.isNotEmpty ? () => _callPartner(phone) : null,
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('Call',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AstraTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: AstraTheme.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------
// RADAR PAINTERS
// -------------------------------------------------------------
class _CosmicRadarPainter extends CustomPainter {
  final double pulseVal;
  final bool isOnline;

  _CosmicRadarPainter({required this.pulseVal, required this.isOnline});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    final radarLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AstraTheme.primary.withValues(alpha: 0.18)
      ..strokeWidth = 1.0;

    // Fixed concentric circles
    canvas.drawCircle(center, baseRadius * 0.4, radarLinePaint);
    canvas.drawCircle(center, baseRadius * 0.7, radarLinePaint);
    canvas.drawCircle(center, baseRadius * 0.96, radarLinePaint);

    // Crosshairs
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AstraTheme.primary.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;

    canvas.drawLine(
        Offset(center.dx - baseRadius, center.dy),
        Offset(center.dx + baseRadius, center.dy),
        crossPaint);
    canvas.drawLine(
        Offset(center.dx, center.dy - baseRadius),
        Offset(center.dx, center.dy + baseRadius),
        crossPaint);

    // Animated ripple wave
    final waveColor = isOnline ? AstraTheme.accentOnline : AstraTheme.primary;
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = waveColor.withValues(alpha: (1.0 - pulseVal) * 0.4)
      ..strokeWidth = 2.0;

    canvas.drawCircle(
        center, (baseRadius * 0.35) + (pulseVal * baseRadius * 0.65), wavePaint);

    // Small decorative satellites / stars
    final starPaint = Paint()
      ..color = AstraTheme.accentCyan.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * (math.pi / 180);
      final pt = Offset(
        center.dx + (baseRadius * 0.7) * math.cos(angle),
        center.dy + (baseRadius * 0.7) * math.sin(angle),
      );
      canvas.drawCircle(pt, 2.5, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicRadarPainter oldDelegate) {
    return oldDelegate.pulseVal != pulseVal ||
        oldDelegate.isOnline != isOnline;
  }
}

class _EmptyPulsePainter extends CustomPainter {
  final double pulse;

  _EmptyPulsePainter(this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AstraTheme.primary.withValues(alpha: (1.0 - pulse) * 0.4)
      ..strokeWidth = 2.5;

    canvas.drawCircle(center, 42 + (pulse * 35), wavePaint);
    canvas.drawCircle(center, 55 + (pulse * 25), wavePaint);
  }

  @override
  bool shouldRepaint(covariant _EmptyPulsePainter oldDelegate) => true;
}

// -------------------------------------------------------------
// WHATSAPP-STYLE PHONE CONTACTS + SEARCH MODAL
// -------------------------------------------------------------
class _ContactsAndSearchModal extends StatefulWidget {
  const _ContactsAndSearchModal();

  @override
  State<_ContactsAndSearchModal> createState() =>
      _ContactsAndSearchModalState();
}

class _ContactsAndSearchModalState extends State<_ContactsAndSearchModal> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';

  List<Contact> _contacts = [];
  Map<String, Map<String, dynamic>> _registeredUsers = {};
  List<String> _myConnectedUserIds = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    String clean = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length > 10) {
      clean = clean.substring(clean.length - 10);
    }
    return clean;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      _myConnectedUserIds =
          List<String>.from(myDoc.data()?['connections'] ?? []);
    }

    try {
      final regList = await AuthService.fetchAllRegisteredUsers();
      final Map<String, Map<String, dynamic>> map = {};
      for (final u in regList) {
        final ph = u['phoneNumber'] as String? ?? '';
        final clean = _normalizePhone(ph);
        if (clean.isNotEmpty) {
          map[clean] = u;
        }
      }
      _registeredUsers = map;
    } catch (_) {}

    try {
      final hasPerm =
          await FlutterContacts.permissions.has(PermissionType.read);
      bool granted = hasPerm;
      if (!granted) {
        final status =
            await FlutterContacts.permissions.request(PermissionType.read);
        granted = status == PermissionStatus.granted ||
            status == PermissionStatus.limited;
      }

      if (granted) {
        final list = await FlutterContacts.getAll(
          properties: {ContactProperty.phone, ContactProperty.name},
        );
        _contacts = list.where((c) => c.phones.isNotEmpty).toList();
        _contacts.sort((a, b) {
          final nameA = (a.displayName ?? '').toLowerCase();
          final nameB = (b.displayName ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _connectWithUser(Map<String, dynamic> targetUser) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    try {
      await AuthService.addConnection(
        currentUid: currentUid,
        targetUser: targetUser,
      );
      if (!mounted) return;

      final targetName = (targetUser['name'] as String?) ?? 'Friend';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected with $targetName!'),
          backgroundColor: AstraTheme.primary,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _inviteViaWhatsApp(String phone, String name) async {
    final message =
        'Hey $name! Connect with me on Astra: https://astra.croto.in/';
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallback = Uri.parse(
            'https://wa.me/?text=${Uri.encodeComponent(message)}');
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    final filteredContacts = _contacts.where((contact) {
      if (_searchQuery.isEmpty) return true;
      final dName = (contact.displayName ?? '').toLowerCase();
      final nameMatches = dName.contains(_searchQuery);
      final phoneMatches = contact.phones.any((p) =>
          p.number.replaceAll(RegExp(r'[^0-9]'), '').contains(_searchQuery));
      return nameMatches || phoneMatches;
    }).toList();

    final List<Map<String, dynamic>> onAstraList = [];
    final List<Contact> inviteList = [];

    for (final contact in filteredContacts) {
      bool matched = false;
      for (final p in contact.phones) {
        final clean = _normalizePhone(p.number);
        if (_registeredUsers.containsKey(clean)) {
          final regData = _registeredUsers[clean]!;
          if (regData['uid'] != currentUid) {
            onAstraList.add({
              'contact': contact,
              'userData': regData,
              'phone': p.number,
            });
            matched = true;
            break;
          }
        }
      }
      if (!matched) {
        inviteList.add(contact);
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AstraTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AstraTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Find Friends',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search contacts by name or number...',
                hintStyle: const TextStyle(
                    color: AstraTheme.textSecondary, fontSize: 14),
                prefixIcon: const Icon(Icons.search,
                    color: AstraTheme.textSecondary, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white70, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AstraTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AstraTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AstraTheme.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AstraTheme.primary),
                  )
                : ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    children: [
                      if (onAstraList.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'ON ASTRA',
                            style: TextStyle(
                              color: AstraTheme.accentCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        ...onAstraList.map((item) {
                          final contact = item['contact'] as Contact;
                          final userData =
                              item['userData'] as Map<String, dynamic>;
                          final uid = userData['uid'] as String;
                          final isAlreadyConnected =
                              _myConnectedUserIds.contains(uid);
                          final displayName =
                              contact.displayName ?? 'User';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AstraTheme.primary.withValues(alpha: 0.3),
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                (userData['phoneNumber'] as String?) ??
                                    (item['phone'] as String? ?? ''),
                                style: const TextStyle(
                                    color: AstraTheme.textSecondary,
                                    fontSize: 12),
                              ),
                              trailing: isAlreadyConnected
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Connected',
                                        style: TextStyle(
                                            color: AstraTheme.accentCyan,
                                            fontSize: 12),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: () =>
                                          _connectWithUser(userData),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AstraTheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                      ),
                                      child: const Text('Connect',
                                          style: TextStyle(fontSize: 13)),
                                    ),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],
                      if (inviteList.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'INVITE TO ASTRA',
                            style: TextStyle(
                              color: AstraTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        ...inviteList.map((contact) {
                          final phone = contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : '';
                          final displayName =
                              contact.displayName ?? 'Friend';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: Colors.white10,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                            ),
                            subtitle: Text(
                              phone,
                              style: const TextStyle(
                                  color: AstraTheme.textSecondary,
                                  fontSize: 12),
                            ),
                            trailing: OutlinedButton.icon(
                              onPressed: () =>
                                  _inviteViaWhatsApp(phone, displayName),
                              icon: const Icon(Icons.share_outlined, size: 14),
                              label: const Text('Invite',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.greenAccent,
                                side: BorderSide(
                                    color: Colors.greenAccent
                                        .withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                      if (onAstraList.isEmpty && inviteList.isEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No contacts found matching search',
                              style:
                                  TextStyle(color: AstraTheme.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
