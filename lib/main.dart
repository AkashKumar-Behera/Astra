import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'core/services/background_location_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/websocket_service.dart';
import 'core/services/widget_sync_service.dart';
import 'core/services/webrtc_call_service.dart';
import 'core/theme/astra_theme.dart';
import 'features/calls/incoming_call_screen.dart';
import 'features/splash/splash_screen.dart';

StreamSubscription? _globalCallSub;

void _initGlobalCallListener(String myUid) {
  _globalCallSub?.cancel();
  _globalCallSub = WebRtcCallService.listenToIncomingCalls(myUid).listen((callData) {
    if (callData != null) {
      final callId = callData['callId'] as String? ?? '';
      final callerUid = callData['callerUid'] as String? ?? '';
      final callerName = callData['callerName'] as String? ?? 'Partner';
      final callerPhoto = callData['callerPhoto'] as String?;
      final typeStr = callData['type'] as String? ?? 'audio';
      final type = typeStr == 'video' ? CallType.video : CallType.audio;

      if (WebRtcCallService.instance.status == CallStatus.idle && callId.isNotEmpty) {
        WebRtcCallService.instance.status = CallStatus.ringing;
        NotificationService.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(
              callId: callId,
              callerUid: callerUid,
              callerName: callerName,
              callerPhoto: callerPhoto,
              type: type,
              myUid: myUid,
            ),
          ),
        );
      }
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase.initializeApp ignored error: $e');
  }

  // Initialize FCM Push Notifications safely
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('NotificationService.initialize ignored error: $e');
  }

  // Initialize background location sync via Workmanager (Android only)
  try {
    await BackgroundLocationManager.initialize();
  } catch (e) {
    debugPrint('BackgroundLocationManager.initialize ignored error: $e');
  }

  // Initialize Home Screen Widget Sync
  try {
    await WidgetSyncService.init();
  } catch (e) {
    debugPrint('WidgetSyncService.init error: $e');
  }

  // Initialize Astra VPS WebSocket Service & Global Incoming Call Listener
  try {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        WebSocketService.connect();
        _initGlobalCallListener(user.uid);
      } else {
        WebSocketService.disconnect();
        _globalCallSub?.cancel();
        _globalCallSub = null;
      }
    });
  } catch (e) {
    debugPrint('Auth listener error: $e');
  }

  runApp(const AstraApp());
}

class AstraApp extends StatelessWidget {
  const AstraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'Astra',
      debugShowCheckedModeBanner: false,
      theme: AstraTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
