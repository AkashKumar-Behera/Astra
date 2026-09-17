import 'package:flutter/material.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/astra_theme.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();

  runApp(const AstraApp());
}

class AstraApp extends StatelessWidget {
  const AstraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Astra',
      debugShowCheckedModeBanner: false,
      theme: AstraTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
