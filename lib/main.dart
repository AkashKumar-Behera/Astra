import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/background_location_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/astra_theme.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize FCM Push Notifications
  await NotificationService.initialize();

  // Initialize 30-minute background location sync via Workmanager
  await BackgroundLocationManager.initialize();

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
