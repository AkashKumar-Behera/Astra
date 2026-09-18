import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:firebase_database/firebase_database.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/location_rtdb_service.dart';
import '../../core/services/telemetry_service.dart';
import '../../core/theme/astra_theme.dart';
import '../chat/chat_screen.dart';
import '../settings/profile_settings_modal.dart';

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
  late AnimationController _pulseController;
  final MapController _mapController = MapController();
  int _selectedPartnerIndex = 0;

  // Dark Matrix Color Filter to turn standard OSM tiles into Pure Midnight Cosmic Dark Map
  static const ColorFilter _darkOsmMatrix = ColorFilter.matrix(<double>[
    -0.2126 * 0.85, -0.7152 * 0.85, -0.0722 * 0.85, 0, 255 * 0.9,
    -0.2126 * 0.85, -0.7152 * 0.85, -0.0722 * 0.85, 0, 255 * 0.9,
    -0.2126 * 0.95, -0.7152 * 0.95, -0.0722 * 0.95, 0, 255 * 1.05,
    0,              0,              0,              1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initLocation();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      TelemetryService.startTelemetrySync(uid);
    }
  }

  @override
  void dispose() {
    TelemetryService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await Future.wait([
          AuthService.updateUserLocation(
            uid: uid,
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          LocationRtdbService.updateLocation(
            uid: uid,
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        ]);
      }
    } catch (_) {}
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProfileSettingsModal(
        initialName: widget.userName,
        initialPhotoUrl: widget.photoUrl,
        myPhone: myPhone,
      ),
    );
  }

  void _openChat(Map<String, dynamic> partner, bool isOnline) {
    final uid = partner['uid'] as String? ?? '';
    final name = (partner['name'] as String?) ?? 'Friend';
    final photo = partner['photoUrl'] as String?;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          partnerUid: uid,
          partnerName: name,
          partnerPhoto: photo,
          isOnline: isOnline,
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
          'You will no longer share live map radar, telemetry and chat with each other.',
          style: TextStyle(color: AstraTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AstraTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AstraTheme.accentDanger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      return '${km.toStringAsFixed(1)} km';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPartnersData(List<String> uids) async {
    if (uids.isEmpty) return [];
    try {
      final docs = await Future.wait(
        uids.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get()),
      );
      return docs.where((d) => d.exists && d.data() != null).map((d) => d.data()!).toList();
    } catch (_) {
      return [];
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
        final connectionUids = List<String>.from(userData?['connections'] ?? []);

        return Scaffold(
          backgroundColor: AstraTheme.background,
          body: Stack(
            children: [
              // 1. FULL BACKGROUND DARK OSM MAP
              Positioned.fill(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchPartnersData(connectionUids),
                  builder: (context, partnersSnap) {
                    final partners = partnersSnap.data ?? [];
                    return _buildFullDarkMap(
                      myLat: _currentPosition?.latitude,
                      myLng: _currentPosition?.longitude,
                      partners: partners,
                    );
                  },
                ),
              ),

              // 2. TOP FLOATING APP BAR (Header matching Screen4)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Astra Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurface.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AstraTheme.borderSubtle),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/Astra.png',
                                width: 22,
                                height: 22,
                                errorBuilder: (ctx, error, stackTrace) => const Icon(Icons.auto_awesome, color: AstraTheme.primaryLight, size: 20),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Astra',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Right Actions: Add Contact & Settings Icon
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: AstraTheme.cardSurface.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                border: Border.all(color: AstraTheme.borderSubtle),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.person_add_alt_1, color: Colors.white70, size: 20),
                                onPressed: _openContactsModal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: AstraTheme.cardSurface.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                border: Border.all(color: AstraTheme.borderSubtle),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 20),
                                onPressed: () => _openSettingsModal(myPhone),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. MAP RE-CENTER / ZOOM BUTTONS
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.38,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'recenter_btn',
                      backgroundColor: AstraTheme.cardSurface.withValues(alpha: 0.9),
                      foregroundColor: AstraTheme.accentCyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AstraTheme.borderSubtle),
                      ),
                      onPressed: () {
                        if (_currentPosition != null) {
                          _mapController.move(
                            ll.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            14.0,
                          );
                        }
                      },
                      child: const Icon(Icons.navigation_outlined, size: 20),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'layers_btn',
                      backgroundColor: AstraTheme.cardSurface.withValues(alpha: 0.9),
                      foregroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: AstraTheme.borderSubtle),
                      ),
                      onPressed: _openContactsModal,
                      child: const Icon(Icons.layers_outlined, size: 20),
                    ),
                  ],
                ),
              ),

              // 4. BOTTOM DRAGGABLE & EXPANDABLE SHEET (Matching Screen4.png)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchPartnersData(connectionUids),
                builder: (context, partnersSnap) {
                  final partners = partnersSnap.data ?? [];
                  return _buildDraggableTelemetrySheet(
                    currentUid: currentUser.uid,
                    partners: partners,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // FULLSCREEN DARK MATRIX OPENSTREETMAP (100% Free, No Watermark)
  // -------------------------------------------------------------
  Widget _buildFullDarkMap({
    required double? myLat,
    required double? myLng,
    required List<Map<String, dynamic>> partners,
  }) {
    final hasMyLoc = myLat != null && myLng != null;
    final initialCenter = hasMyLoc
        ? ll.LatLng(myLat, myLng)
        : const ll.LatLng(20.5937, 78.9629);

    final markers = <Marker>[];
    final polylines = <Polyline>[];

    // Current User Glowing Cyan Pin
    if (hasMyLoc) {
      markers.add(
        Marker(
          point: ll.LatLng(myLat, myLng),
          width: 80,
          height: 80,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AstraTheme.cardSurface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AstraTheme.accentCyan.withValues(alpha: 0.5)),
                ),
                child: const Text('You', style: TextStyle(color: AstraTheme.accentCyan, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AstraTheme.accentCyan.withValues(alpha: 0.25),
                      border: Border.all(color: AstraTheme.accentCyan, width: 2),
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AstraTheme.accentCyan,
                      boxShadow: [
                        BoxShadow(
                          color: AstraTheme.accentCyan,
                          blurRadius: 12,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Partner Markers with Glowing Aura & Distance Badges
    for (int i = 0; i < partners.length; i++) {
      final p = partners[i];
      final pLat = (p['latitude'] as num?)?.toDouble();
      final pLng = (p['longitude'] as num?)?.toDouble();
      final pName = (p['name'] as String?) ?? 'Friend';
      final pPhoto = p['photoUrl'] as String?;
      final isOnline = (p['isOnline'] as bool?) ?? false;

      if (pLat != null && pLng != null) {
        final distStr = _formatDistance(myLat, myLng, pLat, pLng);

        // Dashed polyline between You & Partner
        if (hasMyLoc) {
          polylines.add(
            Polyline(
              points: [ll.LatLng(myLat, myLng), ll.LatLng(pLat, pLng)],
              strokeWidth: 2.5,
              color: AstraTheme.primaryLight.withValues(alpha: 0.7),
            ),
          );

          // Center distance badge marker
          final midLat = (myLat + pLat) / 2;
          final midLng = (myLng + pLng) / 2;
          markers.add(
            Marker(
              point: ll.LatLng(midLat, midLng),
              width: 80,
              height: 30,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AstraTheme.cardSurface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AstraTheme.borderSubtle),
                  ),
                  child: Text(
                    distStr,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          );
        }

        // Partner Pin (Avatar + Time updated)
        markers.add(
          Marker(
            point: ll.LatLng(pLat, pLng),
            width: 80,
            height: 90,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedPartnerIndex = i);
                _openChat(p, isOnline);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AstraTheme.cardSurface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isOnline ? AstraTheme.accentOnline : AstraTheme.borderSubtle),
                    ),
                    child: Text(
                      isOnline ? 'Online' : 'Active recently',
                      style: TextStyle(
                        color: isOnline ? AstraTheme.accentOnline : AstraTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isOnline ? AstraTheme.accentOnline : AstraTheme.primary,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isOnline ? AstraTheme.accentOnline : AstraTheme.primary).withValues(alpha: 0.6),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: pPhoto != null
                          ? Image.network(pPhoto, fit: BoxFit.cover)
                          : Container(
                              color: AstraTheme.cardSurface,
                              child: Center(
                                child: Text(
                                  pName.isNotEmpty ? pName[0].toUpperCase() : 'P',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: hasMyLoc ? 13.5 : 5.0,
        minZoom: 3.0,
        maxZoom: 18.5,
      ),
      children: [
        // 100% Free Standard OpenStreetMap with ColorFiltered Dark Matrix
        ColorFiltered(
          colorFilter: _darkOsmMatrix,
          child: TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.croto.astra',
          ),
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  // -------------------------------------------------------------
  // DRAGGABLE & EXPANDABLE TELEMETRY BOTTOM SHEET (Screen4.png)
  // -------------------------------------------------------------
  Widget _buildDraggableTelemetrySheet({
    required String currentUid,
    required List<Map<String, dynamic>> partners,
  }) {
    if (partners.isEmpty) {
      return DraggableScrollableSheet(
        initialChildSize: 0.28,
        minChildSize: 0.22,
        maxChildSize: 0.85,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AstraTheme.cardSurface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(color: AstraTheme.borderSubtle, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Partners Connected',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap + to discover and connect with friends from your contacts.',
                  style: TextStyle(color: AstraTheme.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _openContactsModal,
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add Friend from Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AstraTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final partnerIndex = _selectedPartnerIndex < partners.length ? _selectedPartnerIndex : 0;
    final activePartner = partners[partnerIndex];
    final pUid = activePartner['uid'] as String? ?? '';
    final pName = (activePartner['name'] as String?) ?? 'Partner';
    final pPhoto = activePartner['photoUrl'] as String?;
    final pPhone = (activePartner['phoneNumber'] as String?) ?? '';
    final pStatus = (activePartner['status'] as String?) ?? 'Online';

    return DraggableScrollableSheet(
      initialChildSize: 0.36,
      minChildSize: 0.30,
      maxChildSize: 0.88,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AstraTheme.cardSurface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: AstraTheme.borderSubtle, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: StreamBuilder<DatabaseEvent>(
            stream: TelemetryService.streamPartnerTelemetry(pUid),
            builder: (context, teleSnap) {
              int battery = 85;
              String network = 'wifi';
              bool isOnline = true;

              if (teleSnap.hasData && teleSnap.data!.snapshot.value != null) {
                try {
                  final val = Map<dynamic, dynamic>.from(teleSnap.data!.snapshot.value as Map);
                  battery = (val['battery'] as num?)?.toInt() ?? battery;
                  network = (val['network'] as String?) ?? network;
                  isOnline = (val['isOnline'] as bool?) ?? isOnline;
                } catch (_) {}
              }

              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Drag Handle Bar
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Horizontal Partner Selector (if multiple friends)
                  if (partners.length > 1) ...[
                    SizedBox(
                      height: 42,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: partners.length,
                        itemBuilder: (ctx, idx) {
                          final isSel = idx == partnerIndex;
                          final p = partners[idx];
                          final name = p['name'] ?? 'Friend';
                          return GestureDetector(
                            onTap: () => setState(() => _selectedPartnerIndex = idx),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSel ? AstraTheme.primary : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSel ? AstraTheme.primaryLight : AstraTheme.borderSubtle,
                                ),
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: isSel ? Colors.white : AstraTheme.textSecondary,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Profile Header Row (Screen4.png match)
                  GestureDetector(
                    onTap: () => _openChat(activePartner, isOnline),
                    child: Row(
                      children: [
                        // Avatar with glowing ring
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                          backgroundImage: pPhoto != null ? NetworkImage(pPhoto) : null,
                          child: pPhoto == null
                              ? Text(
                                  pName.isNotEmpty ? pName[0].toUpperCase() : 'P',
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),

                        // Partner Name & Telemetry Row
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pName,
                                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),

                              // Online status + Network + Battery badges
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isOnline ? AstraTheme.accentOnline : AstraTheme.accentOffline,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? 'Online • Just now' : 'Offline',
                                    style: TextStyle(
                                      color: isOnline ? AstraTheme.accentOnline : AstraTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Network Icon (WiFi or Cellular)
                                  Icon(
                                    network == 'wifi' ? Icons.wifi : Icons.signal_cellular_alt,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 8),

                                  // Battery Icon + Level
                                  Icon(
                                    battery > 20 ? Icons.battery_charging_full : Icons.battery_alert,
                                    size: 14,
                                    color: battery > 20 ? Colors.greenAccent : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$battery%',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 4),
                              // Location updated line
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 12, color: AstraTheme.accentCyan),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      pStatus,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AstraTheme.textSecondary, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Right Arrow to Chat
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons Row: Call, Video, Direct Chat (Screen4.png match)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: pPhone.isNotEmpty ? () => _callPartner(pPhone) : null,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.call, color: Colors.white, size: 20),
                                SizedBox(height: 4),
                                Text('Call', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openChat(activePartner, isOnline),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam, color: Colors.white, size: 22),
                                SizedBox(height: 4),
                                Text('Video', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: AstraTheme.primary.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AstraTheme.primary.withValues(alpha: 0.5)),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openChat(activePartner, isOnline),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_rounded, color: AstraTheme.primaryLight, size: 20),
                                SizedBox(height: 4),
                                Text('Direct Chat', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Disconnect / Change Friend Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.link_off, size: 16, color: AstraTheme.accentDanger),
                        label: const Text('Disconnect', style: TextStyle(color: AstraTheme.accentDanger, fontSize: 12)),
                        onPressed: () => _disconnectPartner(currentUid, pUid, pName),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_outlined, size: 16, color: AstraTheme.accentCyan),
                        label: const Text('Add More Friends', style: TextStyle(color: AstraTheme.accentCyan, fontSize: 12)),
                        onPressed: _openContactsModal,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// WHATSAPP-STYLE PHONE CONTACTS + SEARCH MODAL
// -------------------------------------------------------------
class _ContactsAndSearchModal extends StatefulWidget {
  const _ContactsAndSearchModal();

  @override
  State<_ContactsAndSearchModal> createState() => _ContactsAndSearchModalState();
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
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      _myConnectedUserIds = List<String>.from(myDoc.data()?['connections'] ?? []);
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
      final hasPerm = await FlutterContacts.permissions.has(PermissionType.read);
      bool granted = hasPerm;
      if (!granted) {
        final status = await FlutterContacts.permissions.request(PermissionType.read);
        granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
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
    final message = 'Hey $name! Connect with me on Astra: https://astra.croto.in/';
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        final fallback = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
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
      final phoneMatches = contact.phones.any((p) => p.number.replaceAll(RegExp(r'[^0-9]'), '').contains(_searchQuery));
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
                hintStyle: const TextStyle(color: AstraTheme.textSecondary, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: AstraTheme.textSecondary, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                          final userData = item['userData'] as Map<String, dynamic>;
                          final uid = userData['uid'] as String;
                          final isAlreadyConnected = _myConnectedUserIds.contains(uid);
                          final displayName = contact.displayName ?? 'User';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                                child: Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                (userData['phoneNumber'] as String?) ?? (item['phone'] as String? ?? ''),
                                style: const TextStyle(color: AstraTheme.textSecondary, fontSize: 12),
                              ),
                              trailing: isAlreadyConnected
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Connected',
                                        style: TextStyle(color: AstraTheme.accentCyan, fontSize: 12),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: () => _connectWithUser(userData),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AstraTheme.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                      ),
                                      child: const Text('Connect', style: TextStyle(fontSize: 13)),
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
                          final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                          final displayName = contact.displayName ?? 'Friend';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: Colors.white10,
                              child: Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                            ),
                            subtitle: Text(
                              phone,
                              style: const TextStyle(color: AstraTheme.textSecondary, fontSize: 12),
                            ),
                            trailing: OutlinedButton.icon(
                              onPressed: () => _inviteViaWhatsApp(phone, displayName),
                              icon: const Icon(Icons.share_outlined, size: 14),
                              label: const Text('Invite', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.greenAccent,
                                side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.6)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              style: TextStyle(color: AstraTheme.textSecondary),
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
