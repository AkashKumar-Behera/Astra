import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';

/// Represents real-time presence data for a user
class PartnerPresence {
  final bool isOnline;
  final int? lastSeen;

  const PartnerPresence({
    required this.isOnline,
    this.lastSeen,
  });

  /// Formatted status text for UI headers (e.g. "Online", "Last seen 5m ago")
  String get statusText {
    if (isOnline) return 'Online';
    if (lastSeen == null || lastSeen! <= 0) return 'Offline';

    final now = DateTime.now().millisecondsSinceEpoch;
    final diffMillis = now - lastSeen!;
    if (diffMillis < 0) return 'Online';

    final diffMinutes = diffMillis ~/ 60000;
    if (diffMinutes < 1) return 'Last seen just now';
    if (diffMinutes < 60) return 'Last seen ${diffMinutes}m ago';

    final diffHours = diffMinutes ~/ 60;
    if (diffHours < 24) return 'Last seen ${diffHours}h ago';

    final diffDays = diffHours ~/ 24;
    return 'Last seen ${diffDays}d ago';
  }

  /// Compact header status text (e.g. "🟢 Online" or "Last seen 2m ago")
  String get headerStatusText {
    if (isOnline) return '🟢 Online';
    return statusText;
  }
}

/// PresenceService
///
/// Production real-time presence engine using Firebase Realtime Database (RTDB).
/// Leverages `.info/connected` socket monitoring and `.onDisconnect()` hooks
/// to guarantee accurate online/offline state across app backgrounding, termination,
/// network losses, and phone reboots.
class PresenceService with WidgetsBindingObserver {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String? _currentUid;
  StreamSubscription<DatabaseEvent>? _connectedSub;
  bool _initialized = false;

  /// Initialize presence tracking for the authenticated user
  void init(String uid) {
    if (_initialized && _currentUid == uid) return;
    dispose();

    _currentUid = uid;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    final statusRef = _rtdb.ref('status/$uid');
    final connectedRef = _rtdb.ref('.info/connected');

    _connectedSub = connectedRef.onValue.listen((event) {
      final isConnected = event.snapshot.value as bool? ?? false;
      if (isConnected && _currentUid != null) {
        // Register onDisconnect hook on RTDB server
        statusRef.onDisconnect().update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });

        // Set active presence
        statusRef.update({
          'isOnline': true,
          'lastSeen': ServerValue.timestamp,
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_currentUid == null) return;
    final statusRef = _rtdb.ref('status/$_currentUid');

    if (state == AppLifecycleState.resumed) {
      statusRef.update({
        'isOnline': true,
        'lastSeen': ServerValue.timestamp,
      });
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      statusRef.update({
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      });
    }
  }

  /// Set offline manually (e.g. upon user logout)
  Future<void> setOffline() async {
    if (_currentUid != null) {
      try {
        await _rtdb.ref('status/$_currentUid').update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });
      } catch (_) {}
    }
  }

  /// Stream real-time presence of a partner
  static Stream<PartnerPresence> streamPartnerPresence(String partnerUid) {
    if (partnerUid.isEmpty) {
      return Stream.value(const PartnerPresence(isOnline: false));
    }

    return _rtdb.ref('status/$partnerUid').onValue.map((event) {
      if (event.snapshot.value == null) {
        return const PartnerPresence(isOnline: false);
      }
      try {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final isOnline = (data['isOnline'] as bool?) ?? false;
        final lastSeen = (data['lastSeen'] as num?)?.toInt();
        return PartnerPresence(isOnline: isOnline, lastSeen: lastSeen);
      } catch (_) {
        return const PartnerPresence(isOnline: false);
      }
    });
  }

  /// One-time fetch of partner presence
  static Future<PartnerPresence> getPartnerPresence(String partnerUid) async {
    if (partnerUid.isEmpty) return const PartnerPresence(isOnline: false);
    try {
      final snap = await _rtdb.ref('status/$partnerUid').get();
      if (snap.exists && snap.value != null) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        return PartnerPresence(
          isOnline: (data['isOnline'] as bool?) ?? false,
          lastSeen: (data['lastSeen'] as num?)?.toInt(),
        );
      }
    } catch (_) {}
    return const PartnerPresence(isOnline: false);
  }

  /// Dispose active subscriptions and observers
  void dispose() {
    _connectedSub?.cancel();
    _connectedSub = null;
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _initialized = false;
    }
    _currentUid = null;
  }
}
