import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/location_rtdb_service.dart';
import '../../core/services/telemetry_service.dart';
import '../../core/services/presence_service.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/services/map_cache_service.dart';
import '../../core/theme/astra_theme.dart';
import '../chat/chat_screen.dart';
import '../../core/services/background_location_service.dart';
import '../calls/incoming_call_screen.dart';
import '../profile/partner_profile_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/services/widget_sync_service.dart';
import '../../core/widgets/astra_logo.dart';

enum AstraMapStyle {
  nocturne,
  darkMatter,
  midnightBlue,
  pureOled,
  satellite,
  voyager,
}

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
  StreamSubscription<Position>? _positionStreamSub;
  StreamSubscription? _incomingCallSub;
  late AnimationController _pulseController;
  final MapController _mapController = MapController();
  int _selectedPartnerIndex = 0;
  AstraMapStyle _currentMapStyle = AstraMapStyle.nocturne;
  bool _isRefreshingLocation = false;
  double _mapRotation = 0.0;
  bool _isPrecachingMap = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _loadSavedMapStyle();
    _initLocation();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      PresenceService.instance.init(uid);
      TelemetryService.startTelemetrySync(uid);
      LocationRtdbService.startLocationRequestListener(uid);
      BackgroundLocationManager.startContinuousTracking(uid);

      _incomingCallSub = WebRtcCallService.listenToIncomingCalls(uid).listen((callData) {
        if (callData != null && mounted) {
          final callId = callData['callId'] as String? ?? '';
          final callerUid = callData['callerUid'] as String? ?? '';
          final callerName = callData['callerName'] as String? ?? 'Partner';
          final callerPhoto = callData['callerPhoto'] as String?;
          final typeStr = callData['type'] as String? ?? 'audio';
          final type = typeStr == 'video' ? CallType.video : CallType.audio;

          if (WebRtcCallService.instance.status == CallStatus.idle) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IncomingCallScreen(
                  callId: callId,
                  callerUid: callerUid,
                  callerName: callerName,
                  callerPhoto: callerPhoto,
                  type: type,
                  myUid: uid,
                ),
              ),
            );
          }
        }
      });
    }
  }

  Future<void> _loadSavedMapStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('astra_map_style');
      if (saved != null) {
        final match = AstraMapStyle.values.firstWhere(
          (s) => s.name == saved,
          orElse: () => AstraMapStyle.nocturne,
        );
        if (mounted) setState(() => _currentMapStyle = match);
      }
    } catch (_) {}
  }

  Future<void> _setMapStyle(AstraMapStyle style) async {
    setState(() => _currentMapStyle = style);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('astra_map_style', style.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _incomingCallSub?.cancel();
    LocationRtdbService.disposeLocationRequestListener();
    TelemetryService.dispose();
    PresenceService.instance.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  int? _parseTimestamp(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toInt();
    if (val is Timestamp) return val.millisecondsSinceEpoch;
    if (val is String) return int.tryParse(val);
    return null;
  }

  Future<void> _refreshPartnerLocation(String partnerUid, String partnerName) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || _isRefreshingLocation) return;

    setState(() => _isRefreshingLocation = true);

    try {
      final result = await LocationRtdbService.refreshPartnerLocation(
        partnerUid: partnerUid,
        myUid: myUid,
        timeout: const Duration(seconds: 10),
      );

      if (!mounted) return;

      if (result.isSuccess && result.latitude != null && result.longitude != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AstraTheme.cardSurface,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$partnerName\'s location refreshed (${result.statusLabel})',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        _mapController.move(
          ll.LatLng(result.latitude!, result.longitude!),
          14.5,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AstraTheme.cardSurface,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.updatedAt != null
                        ? '$partnerName is unavailable. Showing ${result.statusLabel}'
                        : '$partnerName\'s location could not be refreshed.',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isRefreshingLocation = false);
      }
    }
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

      // 1. Instant cached location (0ms) so map centers immediately on launch
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() => _currentPosition = lastKnown);
        try {
          _mapController.move(ll.LatLng(lastKnown.latitude, lastKnown.longitude), 15.0);
        } catch (_) {}
        _precacheLocalArea(lastKnown.latitude, lastKnown.longitude);
      }

      // 2. Fresh high-precision GPS position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        try {
          _mapController.move(ll.LatLng(position.latitude, position.longitude), 15.0);
        } catch (_) {}
        _precacheLocalArea(position.latitude, position.longitude);
      }

      // 3. Continuous real-time GPS stream so user's pin tracks them live
      _positionStreamSub?.cancel();
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((pos) async {
        if (mounted) {
          setState(() => _currentPosition = pos);
        }
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await LocationRtdbService.updateLocation(
            uid: uid,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
          FirebaseFirestore.instance.collection('users').doc(uid).update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'lastSeen': FieldValue.serverTimestamp(),
          }).catchError((_) {});
        }
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await LocationRtdbService.updateLocation(
          uid: uid,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        FirebaseFirestore.instance.collection('users').doc(uid).update({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'lastSeen': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      }
    } catch (_) {}
  }

  void _precacheLocalArea(double lat, double lng, {bool showFeedback = false}) async {
    if (_isPrecachingMap) return;
    _isPrecachingMap = true;

    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AstraTheme.cardSurface,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA594F9)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Saving 30-50 km local area for offline use...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    try {
      await MapCacheService.precacheArea(
        latitude: lat,
        longitude: lng,
        radiusKm: 35.0,
        urlTemplate: _getTileUrlTemplateForStyle(_currentMapStyle),
        styleKey: _currentMapStyle.name,
        zoomLevels: const [13, 14, 15],
      );

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AstraTheme.cardSurface,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Local 35 km map area cached! Instant loading enabled.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
    } finally {
      _isPrecachingMap = false;
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

  void _openSettingsModal(String myPhone, {String? partnerUid, String? partnerName}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          userName: widget.userName,
          photoUrl: widget.photoUrl,
          myPhone: myPhone,
          partnerUid: partnerUid,
          partnerName: partnerName,
        ),
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
      final results = await Future.wait(
        uids.map((uid) async {
          try {
            final docFuture = FirebaseFirestore.instance.collection('users').doc(uid).get();
            final rtdbFuture = LocationRtdbService.getPartnerLocation(uid);

            final doc = await docFuture;
            final rtdbLoc = await rtdbFuture;

            if (!doc.exists || doc.data() == null) return null;
            final data = Map<String, dynamic>.from(doc.data()!);

            // Ensure 'name' is cleanly populated
            if (data['name'] == null && data['displayName'] != null) {
              data['name'] = data['displayName'];
            }

            // Merge real-time RTDB coordinates
            if (rtdbLoc != null) {
              if (rtdbLoc['latitude'] != null) data['latitude'] = rtdbLoc['latitude'];
              if (rtdbLoc['longitude'] != null) data['longitude'] = rtdbLoc['longitude'];
              if (rtdbLoc['updatedAt'] != null) data['updatedAt'] = rtdbLoc['updatedAt'];
            }
            return data;
          } catch (_) {
            return null;
          }
        }),
      );
      return results.whereType<Map<String, dynamic>>().toList();
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
                    final userLat = _currentPosition?.latitude ?? (userData?['latitude'] as num?)?.toDouble();
                    final userLng = _currentPosition?.longitude ?? (userData?['longitude'] as num?)?.toDouble();
                    final myPhoto = (userData?['photoUrl'] as String?) ?? widget.photoUrl;
                    final myName = (userData?['name'] as String?) ?? widget.userName;
                    return _buildFullDarkMap(
                      myLat: userLat,
                      myLng: userLng,
                      myPhoto: myPhoto,
                      myName: myName,
                      partners: partners,
                    );
                  },
                ),
              ),

              // 2. TOP FLOATING APP BAR (Glassmorphic)
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
                        // Left Astra Pill (Frosted Glass)
                        _GlassContainer(
                          borderRadius: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AstraLogo(
                                size: 24,
                                animate: false,
                                showGlow: false,
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

                        // Right Actions: Add Contact & Settings Icon (Frosted Glass)
                        Row(
                          children: [
                            _GlassContainer(
                              borderRadius: 22,
                              padding: EdgeInsets.zero,
                              child: IconButton(
                                icon: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                                onPressed: _openContactsModal,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _GlassContainer(
                              borderRadius: 22,
                              padding: EdgeInsets.zero,
                              child: IconButton(
                                icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                                onPressed: () => _openSettingsModal(
                                  myPhone,
                                  partnerUid: connectionUids.isNotEmpty ? connectionUids.first : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. MAP CONTROLS: COMPASS / RE-CENTER / LAYERS / REFRESH (Glassmorphic)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.36,
                child: Column(
                  children: [
                    // Google Maps Style Compass
                    _GoogleMapsCompass(
                      rotation: _mapRotation,
                      onTap: () {
                        _mapController.rotate(0.0);
                        setState(() => _mapRotation = 0.0);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Recenter / Navigation Button (Matching Screen4.png)
                    _GlassContainer(
                      borderRadius: 24,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.near_me_rounded, color: Color(0xFFA594F9), size: 24),
                          onPressed: () {
                            final targetLat = _currentPosition?.latitude ?? (userData?['latitude'] as num?)?.toDouble();
                            final targetLng = _currentPosition?.longitude ?? (userData?['longitude'] as num?)?.toDouble();
                            if (targetLat != null && targetLng != null) {
                              _mapController.move(
                                ll.LatLng(targetLat, targetLng),
                                16.0,
                              );
                            } else {
                              _initLocation();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Layers Theme Button (Matching Screen4.png)
                    _GlassContainer(
                      borderRadius: 24,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.layers_rounded, color: Color(0xFFA594F9), size: 24),
                          onPressed: _openMapStyleModal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Refresh Button
                    _GlassContainer(
                      borderRadius: 24,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: _isRefreshingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFA594F9),
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, color: Color(0xFFA594F9), size: 22),
                          onPressed: _isRefreshingLocation || connectionUids.isEmpty
                              ? null
                              : () {
                                  final partnerIndex = _selectedPartnerIndex < connectionUids.length ? _selectedPartnerIndex : 0;
                                  final partnerUid = connectionUids[partnerIndex];
                                  _refreshPartnerLocation(partnerUid, 'Friend');
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. BOTTOM DRAGGABLE & EXPANDABLE SHEET (Matching Screen4.png)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchPartnersData(connectionUids),
                builder: (context, partnersSnap) {
                  final partners = partnersSnap.data ?? [];
                  if (partners.isNotEmpty) {
                    final activePartner = _selectedPartnerIndex < partners.length
                        ? partners[_selectedPartnerIndex]
                        : partners.first;
                    final partnerUid = (activePartner['uid'] as String?) ??
                        (connectionUids.isNotEmpty ? connectionUids.first : null);

                    if (partnerUid != null) {
                      return StreamBuilder<DatabaseEvent>(
                        stream: TelemetryService.streamPartnerTelemetry(partnerUid),
                        builder: (context, telemSnap) {
                          Map<String, dynamic>? partnerTelemetry;
                          if (telemSnap.hasData && telemSnap.data!.snapshot.value != null) {
                            try {
                              partnerTelemetry = Map<String, dynamic>.from(
                                telemSnap.data!.snapshot.value as Map,
                              );
                            } catch (_) {}
                          }

                          TelemetryService.getMyBatteryLevel().then((myBatt) {
                            WidgetSyncService.syncFromPartnerData(
                              partnerData: activePartner,
                              myLat: _currentPosition?.latitude ?? (userData?['latitude'] as num?)?.toDouble(),
                              myLng: _currentPosition?.longitude ?? (userData?['longitude'] as num?)?.toDouble(),
                              partnerTelemetry: partnerTelemetry,
                              myData: userData,
                              myBattery: myBatt,
                            );
                          });

                          return _buildDraggableTelemetrySheet(
                            currentUid: currentUser.uid,
                            partners: partners,
                          );
                        },
                      );
                    }
                  }
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
  // MAP STYLE SWITCHER MODAL
  // -------------------------------------------------------------
  void _openMapStyleModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final options = [
            {
              'style': AstraMapStyle.nocturne,
              'title': 'Nocturne Night Satellite',
              'subtitle': 'Ultra-HD night satellite with illuminated streets (Screen4.png)',
              'icon': Icons.satellite_alt_rounded,
              'gradient': [const Color(0xFF1E1B4B), const Color(0xFF0F0E26)],
              'accent': const Color(0xFFA594F9),
            },
            {
              'style': AstraMapStyle.darkMatter,
              'title': 'CartoDB Dark Matter',
              'subtitle': 'Ultra-clean charcoal dark, sharp typography',
              'icon': Icons.dark_mode_rounded,
              'gradient': [const Color(0xFF1E2026), const Color(0xFF111217)],
              'accent': AstraTheme.accentCyan,
            },
            {
              'style': AstraMapStyle.midnightBlue,
              'title': 'Midnight Cosmic Blue',
              'subtitle': 'Futuristic Astra navy blue & glowing routes',
              'icon': Icons.nightlight_round,
              'gradient': [const Color(0xFF0F172A), const Color(0xFF1E1B4B)],
              'accent': AstraTheme.primaryLight,
            },
            {
              'style': AstraMapStyle.pureOled,
              'title': 'Pure OLED Black',
              'subtitle': 'True #000000 black, max contrast & battery saving',
              'icon': Icons.contrast_rounded,
              'gradient': [Colors.black, const Color(0xFF18181B)],
              'accent': Colors.white,
            },
            {
              'style': AstraMapStyle.satellite,
              'title': 'Satellite World Imagery',
              'subtitle': 'Ultra-HD photographic sub-meter satellite view',
              'icon': Icons.satellite_alt_rounded,
              'gradient': [const Color(0xFF064E3B), const Color(0xFF022C22)],
              'accent': const Color(0xFF10B981),
            },
            {
              'style': AstraMapStyle.voyager,
              'title': 'Voyager Modern',
              'subtitle': 'Vibrant colorful daylight city rendering',
              'icon': Icons.explore_rounded,
              'gradient': [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)],
              'accent': Colors.amberAccent,
            },
          ];

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C0B20).withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.layers_rounded, color: AstraTheme.accentCyan, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Map Style & Themes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Offline Area Cache Action Bar
                    _GlassContainer(
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFA594F9).withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.download_for_offline_rounded, color: Color(0xFFA594F9), size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '30-50 km Local Offline Cache',
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Permanently saved on disk for instant 0ms load',
                                  style: TextStyle(color: AstraTheme.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (_currentPosition != null) {
                                _precacheLocalArea(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                  showFeedback: true,
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AstraTheme.cardSurface,
                                    behavior: SnackBarBehavior.floating,
                                    content: Text('Waiting for GPS position...', style: TextStyle(color: Colors.white)),
                                  ),
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFFA594F9).withValues(alpha: 0.25),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text(
                              'Cache Area',
                              style: TextStyle(color: Color(0xFFA594F9), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...options.map((opt) {
                      final style = opt['style'] as AstraMapStyle;
                      final isSelected = _currentMapStyle == style;
                      final title = opt['title'] as String;
                      final subtitle = opt['subtitle'] as String;
                      final icon = opt['icon'] as IconData;
                      final gradient = opt['gradient'] as List<Color>;
                      final accent = opt['accent'] as Color;

                      return _GlassContainer(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        borderRadius: 18,
                        blur: 14,
                        color: isSelected
                            ? gradient[0].withValues(alpha: 0.50)
                            : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: isSelected ? AstraTheme.accentCyan : Colors.white.withValues(alpha: 0.10),
                          width: isSelected ? 1.6 : 1.0,
                        ),
                        onTap: () {
                          _setMapStyle(style);
                          setModalState(() {});
                          Navigator.pop(ctx);
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: gradient[0],
                                shape: BoxShape.circle,
                                border: Border.all(color: accent.withValues(alpha: 0.6)),
                              ),
                              child: Icon(icon, color: accent, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white70 : AstraTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: AstraTheme.accentCyan, size: 24)
                            else
                              const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 22),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // DYNAMIC TILE LAYER BY SELECTED MAP STYLE
  // -------------------------------------------------------------
  static const String _mapTilerKey = 'IG8L4cXU4hvolM8F63k6';

  String _getTileUrlTemplateForStyle(AstraMapStyle style) {
    switch (style) {
      case AstraMapStyle.nocturne:
        return 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case AstraMapStyle.darkMatter:
        return 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}{r}.png?key=$_mapTilerKey';
      case AstraMapStyle.midnightBlue:
        return 'https://api.maptiler.com/maps/dataviz-dark/{z}/{x}/{y}{r}.png?key=$_mapTilerKey';
      case AstraMapStyle.pureOled:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case AstraMapStyle.satellite:
        return 'https://mt{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case AstraMapStyle.voyager:
        return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}{r}.png?key=$_mapTilerKey';
    }
  }

  Widget _buildMapTileLayer() {
    switch (_currentMapStyle) {
      case AstraMapStyle.nocturne:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            // Cinematic Nocturne Night Satellite (Screen4.png aesthetic)
            0.56, 0.00, 0.00, 0.0, -22.0, // R: Preserve road illumination & building highlights
            0.00, 0.58, 0.00, 0.0, -18.0, // G: Deep dark vegetation & fields
            0.00, 0.00, 0.82, 0.0,   8.0, // B: Atmospheric midnight blue tint
            0.00, 0.00, 0.00, 1.0,   0.0,
          ]),
          child: TileLayer(
            urlTemplate: 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
            subdomains: const ['0', '1', '2', '3'],
            userAgentPackageName: 'com.croto.astra',
            tileProvider: CachedTileProvider(styleKey: 'nocturne'),
            retinaMode: false,
            maxZoom: 22,
            maxNativeZoom: 20,
          ),
        );
      case AstraMapStyle.darkMatter:
        return TileLayer(
          urlTemplate: 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}{r}.png?key=$_mapTilerKey',
          userAgentPackageName: 'com.croto.astra',
          tileProvider: CachedTileProvider(styleKey: 'darkMatter'),
          retinaMode: true,
          maxZoom: 22,
          maxNativeZoom: 20,
        );
      case AstraMapStyle.midnightBlue:
        return TileLayer(
          urlTemplate: 'https://api.maptiler.com/maps/dataviz-dark/{z}/{x}/{y}{r}.png?key=$_mapTilerKey',
          userAgentPackageName: 'com.croto.astra',
          tileProvider: CachedTileProvider(styleKey: 'midnightBlue'),
          retinaMode: true,
          maxZoom: 22,
          maxNativeZoom: 20,
        );
      case AstraMapStyle.pureOled:
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            -0.3, -0.59, -0.11, 0, 245,
            -0.3, -0.59, -0.11, 0, 245,
            -0.3, -0.59, -0.11, 0, 245,
            0,    0,     0,     1, 0,
          ]),
          child: TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.croto.astra',
            tileProvider: CachedTileProvider(styleKey: 'pureOled'),
            retinaMode: true,
            maxZoom: 22,
            maxNativeZoom: 19,
          ),
        );
      case AstraMapStyle.satellite:
        return TileLayer(
          urlTemplate: 'https://mt{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          subdomains: const ['0', '1', '2', '3'],
          userAgentPackageName: 'com.croto.astra',
          tileProvider: CachedTileProvider(styleKey: 'satellite'),
          retinaMode: false,
          maxZoom: 22,
          maxNativeZoom: 20,
        );
      case AstraMapStyle.voyager:
        return TileLayer(
          urlTemplate: 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}{r}.png?key=$_mapTilerKey',
          userAgentPackageName: 'com.croto.astra',
          tileProvider: CachedTileProvider(styleKey: 'voyager'),
          retinaMode: true,
          maxZoom: 22,
          maxNativeZoom: 20,
        );
    }
  }

  // -------------------------------------------------------------
  // FULLSCREEN MAP WITH DYNAMIC TILE LAYER (CartoDB, OSM, Satellite)
  // -------------------------------------------------------------
  Widget _buildFullDarkMap({
    required double? myLat,
    required double? myLng,
    required String? myPhoto,
    required String myName,
    required List<Map<String, dynamic>> partners,
  }) {
    final hasMyLoc = myLat != null && myLng != null;
    final initialCenter = hasMyLoc
        ? ll.LatLng(myLat, myLng)
        : const ll.LatLng(20.5937, 78.9629);

    final markers = <Marker>[];
    final polylines = <Polyline>[];

    // Current User Glowing Avatar Pin with PP (Profile Picture)
    if (hasMyLoc) {
      markers.add(
        Marker(
          point: ll.LatLng(myLat, myLng),
          width: 80,
          height: 106,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "You" capsule badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF14132B).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.50),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 5),

              // User's Own PP Avatar with Glowing Cyan Ring & Live Status Dot
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF38BDF8), // Electric cyan/sky blue
                        width: 2.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.65),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: myPhoto != null && myPhoto.isNotEmpty
                          ? Image.network(myPhoto, fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFF1E1B4B),
                              child: Center(
                                child: Text(
                                  myName.isNotEmpty ? myName[0].toUpperCase() : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Glowing Live Status Dot at 2 o'clock
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981), // Emerald green online/live
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF14132B), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Cyan Road Anchor Dot
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Partner Markers with Glowing Aura & Distance Badges (Matching Screen4.png)
    for (int i = 0; i < partners.length; i++) {
      final p = partners[i];
      final pLat = (p['latitude'] as num?)?.toDouble();
      final pLng = (p['longitude'] as num?)?.toDouble();
      final pName = (p['name'] as String?) ?? 'Friend';
      final pPhoto = p['photoUrl'] as String?;
      final isOnline = (p['isOnline'] as bool?) ?? false;

      if (pLat != null && pLng != null) {
        final distStr = _formatDistance(myLat, myLng, pLat, pLng);

        // Dashed polyline between You & Partner (Matching Screen4.png)
        if (hasMyLoc) {
          polylines.add(
            Polyline(
              points: [ll.LatLng(myLat, myLng), ll.LatLng(pLat, pLng)],
              strokeWidth: 2.2,
              color: const Color(0xFFA594F9),
              pattern: StrokePattern.dashed(segments: const [6, 6]),
            ),
          );

          // Center distance badge marker (Matching Screen4.png)
          final midLat = (myLat + pLat) / 2;
          final midLng = (myLng + pLng) / 2;
          markers.add(
            Marker(
              point: ll.LatLng(midLat, midLng),
              width: 90,
              height: 34,
              alignment: Alignment.center,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131127).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    distStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Calculate honest human time ago label (Screen4.png "2 min ago")
        String timeAgo = '2 min ago';
        final updatedAt = _parseTimestamp(p['updatedAt']);
        if (updatedAt != null && updatedAt > 0) {
          final diff = DateTime.now().millisecondsSinceEpoch - updatedAt;
          if (diff < 60000) {
            timeAgo = 'Just now';
          } else {
            final mins = diff ~/ 60000;
            if (mins < 60) {
              timeAgo = '$mins min ago';
            } else {
              final hrs = mins ~/ 60;
              timeAgo = '$hrs hr ago';
            }
          }
        }

        // Partner Pin (Matching Screen4.png)
        markers.add(
          Marker(
            point: ll.LatLng(pLat, pLng),
            width: 80,
            height: 106,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedPartnerIndex = i);
                _openChat(p, isOnline);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Time capsule badge ("2 min ago")
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14132B).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      timeAgo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Avatar with Glowing Lavender Ring & Accent Dot
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFA594F9),
                            width: 2.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFA594F9).withValues(alpha: 0.60),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: pPhoto != null
                              ? Image.network(pPhoto, fit: BoxFit.cover)
                              : Container(
                                  color: const Color(0xFF1E1B4B),
                                  child: Center(
                                    child: Text(
                                      pName.isNotEmpty ? pName[0].toUpperCase() : 'P',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      // Accent Status Dot at 2 o'clock
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFA594F9),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF14132B), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Lavender Anchor Dot on Road
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFA594F9).withValues(alpha: 0.35),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFA594F9),
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
        initialZoom: hasMyLoc ? 15.0 : 5.0,
        minZoom: 4.5,
        maxZoom: 21.0,
        cameraConstraint: CameraConstraint.containCenter(
          bounds: LatLngBounds(
            const ll.LatLng(4.0, 64.0),
            const ll.LatLng(39.0, 100.0),
          ),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onPositionChanged: (pos, hasGesture) {
          if ((_mapRotation - pos.rotation).abs() > 0.5) {
            setState(() {
              _mapRotation = pos.rotation;
            });
          }
        },
      ),
      children: [
        _buildMapTileLayer(),
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
      return Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C0B22).withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 36,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E1B4B).withValues(alpha: 0.65),
                              border: Border.all(
                                color: const Color(0xFFA594F9).withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFA594F9).withValues(alpha: 0.3),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Image.asset(
                                'assets/images/transparent_logo.png',
                                width: 26,
                                height: 26,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) =>
                                    const Icon(Icons.people_outline, color: AstraTheme.primaryLight, size: 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'No Partners Connected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Connect with friends to see live locations.',
                                  style: TextStyle(
                                    color: AstraTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [AstraTheme.primary, AstraTheme.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AstraTheme.primary.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _openContactsModal,
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Add Friend from Contacts',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
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
        ),
      );
    }

    final partnerIndex = _selectedPartnerIndex < partners.length ? _selectedPartnerIndex : 0;
    final activePartner = partners[partnerIndex];
    final pUid = activePartner['uid'] as String? ?? '';
    final pName = (activePartner['name'] as String?) ?? 'Partner';
    final pPhoto = activePartner['photoUrl'] as String?;
    final pPhone = (activePartner['phoneNumber'] as String?) ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.16,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.16, 0.50, 0.85],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C0B22).withValues(alpha: 0.78),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 36,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
          child: StreamBuilder<PartnerPresence>(
            stream: PresenceService.streamPartnerPresence(pUid),
            builder: (context, presenceSnap) {
              final isOnline = presenceSnap.data?.isOnline ?? false;
              final presenceText = presenceSnap.data?.statusText ?? 'Offline';

              return StreamBuilder<DatabaseEvent>(
                stream: TelemetryService.streamPartnerTelemetry(pUid),
                builder: (context, teleSnap) {
                  int battery = 85;
                  String network = 'wifi';

                  if (teleSnap.hasData && teleSnap.data!.snapshot.value != null) {
                    try {
                      final val = Map<dynamic, dynamic>.from(teleSnap.data!.snapshot.value as Map);
                      battery = (val['battery'] as num?)?.toInt() ?? battery;
                      network = (val['network'] as String?) ?? network;
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
                  Row(
                    children: [
                      // Avatar with glowing ring -> opens Partner Profile
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PartnerProfileScreen(
                                partnerUid: pUid,
                                partnerName: pName,
                                partnerPhoto: pPhoto,
                              ),
                            ),
                          );
                        },
                        child: CircleAvatar(
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
                      ),
                      const SizedBox(width: 14),

                      // Partner Name & Telemetry Row -> opens Chat
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openChat(activePartner, isOnline),
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
                                    isOnline ? 'Online • Just now' : presenceText,
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
                            ],
                          ),
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

                  // Real-time RTDB Partner Location Stream & Refresh Tile
                  StreamBuilder<DatabaseEvent>(
                    stream: LocationRtdbService.streamPartnerLocation(pUid),
                    builder: (context, locSnap) {
                      int? updatedAt;
                      if (locSnap.hasData && locSnap.data!.snapshot.value != null) {
                        try {
                          final locMap = Map<dynamic, dynamic>.from(locSnap.data!.snapshot.value as Map);
                          updatedAt = _parseTimestamp(locMap['updatedAt']);
                        } catch (_) {}
                      }

                      final isFresh = LocationRtdbService.isLocationFresh(updatedAt);
                      final freshnessLabel = LocationRtdbService.formatLocationFreshness(updatedAt);

                      return _GlassContainer(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        borderRadius: 20,
                        blur: 16,
                        color: const Color(0xFF161530).withValues(alpha: 0.60),
                        border: Border.all(
                          color: isFresh
                              ? Colors.greenAccent.withValues(alpha: 0.35)
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1.1,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (isFresh ? Colors.greenAccent : Colors.amberAccent).withValues(alpha: 0.18),
                                border: Border.all(
                                  color: (isFresh ? Colors.greenAccent : Colors.amberAccent).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Icon(
                                isFresh ? Icons.my_location_rounded : Icons.location_history_rounded,
                                color: isFresh ? Colors.greenAccent : Colors.amberAccent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        isFresh ? '🟢 Live' : '🟡 Last Known',
                                        style: TextStyle(
                                          color: isFresh ? Colors.greenAccent : Colors.amberAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isFresh ? 'Radar Active' : 'Location Stored',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    freshnessLabel,
                                    style: const TextStyle(color: AstraTheme.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            _GlassContainer(
                              borderRadius: 14,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              blur: 12,
                              color: AstraTheme.primary.withValues(alpha: 0.85),
                              border: Border.all(color: AstraTheme.primaryLight.withValues(alpha: 0.6)),
                              onTap: _isRefreshingLocation ? null : () => _refreshPartnerLocation(pUid, pName),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isRefreshingLocation)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  else
                                    const Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isRefreshingLocation ? 'Pinging...' : 'Refresh',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  // Action Buttons Row: Call, Video, Direct Chat (Glassmorphic)
                  Row(
                    children: [
                      Expanded(
                        child: _GlassContainer(
                          borderRadius: 20,
                          blur: 16,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          color: const Color(0xFF1A1936).withValues(alpha: 0.60),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          onTap: pPhone.isNotEmpty ? () => _callPartner(pPhone) : null,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.call, color: Colors.white, size: 20),
                              SizedBox(height: 6),
                              Text('Call', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GlassContainer(
                          borderRadius: 20,
                          blur: 16,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          color: const Color(0xFF1A1936).withValues(alpha: 0.60),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          onTap: () => _openChat(activePartner, isOnline),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam, color: Colors.white, size: 22),
                              SizedBox(height: 6),
                              Text('Video', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GlassContainer(
                          borderRadius: 20,
                          blur: 16,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          color: AstraTheme.primary.withValues(alpha: 0.40),
                          border: Border.all(color: AstraTheme.primaryLight.withValues(alpha: 0.65), width: 1.2),
                          onTap: () => _openChat(activePartner, isOnline),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_rounded, color: AstraTheme.primaryLight, size: 20),
                              SizedBox(height: 6),
                              Text('Direct Chat', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Disconnect / Add More Friends Glass Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GlassContainer(
                        borderRadius: 14,
                        blur: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: AstraTheme.accentDanger.withValues(alpha: 0.12),
                        border: Border.all(color: AstraTheme.accentDanger.withValues(alpha: 0.35)),
                        onTap: () => _disconnectPartner(currentUid, pUid, pName),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.link_off, size: 15, color: AstraTheme.accentDanger),
                            SizedBox(width: 6),
                            Text('Disconnect', style: TextStyle(color: AstraTheme.accentDanger, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _GlassContainer(
                        borderRadius: 14,
                        blur: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: AstraTheme.accentCyan.withValues(alpha: 0.12),
                        border: Border.all(color: AstraTheme.accentCyan.withValues(alpha: 0.35)),
                        onTap: _openContactsModal,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_outlined, size: 15, color: AstraTheme.accentCyan),
                            SizedBox(width: 6),
                            Text('Add More Friends', style: TextStyle(color: AstraTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
        ),
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

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: const Color(0xFF0C0B20).withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
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

                              return _GlassContainer(
                                margin: const EdgeInsets.only(bottom: 10),
                                borderRadius: 18,
                                blur: 14,
                                color: Colors.white.withValues(alpha: 0.05),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
                                      : _GlassContainer(
                                          borderRadius: 18,
                                          blur: 10,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          color: AstraTheme.primary.withValues(alpha: 0.85),
                                          border: Border.all(color: AstraTheme.primaryLight.withValues(alpha: 0.6)),
                                          onTap: () => _connectWithUser(userData),
                                          child: const Text('Connect', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
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
                              return _GlassContainer(
                                margin: const EdgeInsets.only(bottom: 8),
                                borderRadius: 16,
                                blur: 12,
                                color: Colors.white.withValues(alpha: 0.03),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
                                  trailing: _GlassContainer(
                                    borderRadius: 16,
                                    blur: 10,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    color: Colors.greenAccent.withValues(alpha: 0.12),
                                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                                    onTap: () => _inviteViaWhatsApp(phone, displayName),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.share_outlined, size: 14, color: Colors.greenAccent),
                                        SizedBox(width: 4),
                                        Text('Invite', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                      ],
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
        ),
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;

  const _GlassContainer({
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.blur = 18,
    this.color,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF14132B).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1.1,
            ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// GOOGLE MAPS STYLE COMPASS WIDGET
// -------------------------------------------------------------
class _GoogleMapsCompass extends StatelessWidget {
  final double rotation;
  final VoidCallback onTap;

  const _GoogleMapsCompass({
    required this.rotation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rad = -rotation * (math.pi / 180.0);
    return _GlassContainer(
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Center(
              child: Transform.rotate(
                angle: rad,
                child: CustomPaint(
                  size: const Size(20, 26),
                  painter: _CompassNeedlePainter(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Beveled colors for iconic 3D Google Maps look
    final northPaintRight = Paint()..color = const Color(0xFFFF3B30); // Vibrant Red
    final northPaintLeft = Paint()..color = const Color(0xFFC62828); // Shaded Deep Red
    final southPaintRight = Paint()..color = Colors.white.withValues(alpha: 0.95);
    final southPaintLeft = Paint()..color = const Color(0xFFB0BEC5); // Shaded Slate

    // 1. North Needle (Top Triangle)
    final northPathLeft = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx - size.width / 2, cy)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(northPathLeft, northPaintLeft);

    final northPathRight = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx + size.width / 2, cy)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(northPathRight, northPaintRight);

    // 2. South Needle (Bottom Triangle)
    final southPathLeft = Path()
      ..moveTo(cx, size.height)
      ..lineTo(cx - size.width / 2, cy)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(southPathLeft, southPaintLeft);

    final southPathRight = Path()
      ..moveTo(cx, size.height)
      ..lineTo(cx + size.width / 2, cy)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(southPathRight, southPaintRight);

    // 3. Center Pivot Pin
    final pivotPaint = Paint()..color = const Color(0xFF14132B);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    canvas.drawCircle(Offset(cx, cy), 3.2, pivotPaint);
    canvas.drawCircle(Offset(cx, cy), 3.2, borderPaint);

    // 4. White 'N' character on North needle
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, 3),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
