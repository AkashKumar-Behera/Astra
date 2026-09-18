import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/background_location_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/astra_theme.dart';
import 'features/splash/splash_screen.dart';

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
