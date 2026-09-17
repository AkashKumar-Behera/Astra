import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/astra_theme.dart';
import '../auth/phone_auth_screen.dart';
import '../auth/profile_setup_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.85).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    _checkUpdateAndProceed();
  }

  void _checkUpdateAndProceed() async {
    // Run update check in parallel with splash delay
    final updateFuture = UpdateService.checkForUpdate(
      timeout: const Duration(milliseconds: 1600),
    );
    final delayFuture = Future.delayed(const Duration(milliseconds: 2400));

    final results = await Future.wait([updateFuture, delayFuture]);
    final updateInfo = results[0] as UpdateInfo?;

    if (!mounted) return;

    if (updateInfo != null && updateInfo.hasUpdate) {
      _showUpdateDialog(updateInfo);
    } else {
      _proceedToApp();
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AstraTheme.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AstraTheme.primary.withValues(alpha: 0.5)),
          ),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AstraTheme.primary.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.system_update,
                    color: AstraTheme.primaryLight, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'New Update Available',
                style: TextStyle(
                  color: AstraTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (v${updateInfo.latestVersion}) is ready. Current version is v${updateInfo.currentVersion}.',
                style: const TextStyle(
                  color: AstraTheme.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (updateInfo.releaseNotes != null &&
                  updateInfo.releaseNotes!.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AstraTheme.background.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AstraTheme.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      updateInfo.releaseNotes!,
                      style: const TextStyle(
                        color: AstraTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _proceedToApp();
              },
              child: const Text(
                'Later',
                style: TextStyle(color: AstraTheme.textMuted),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AstraTheme.primary, AstraTheme.secondary],
                ),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () async {
                  final targetUrl = updateInfo.apkDownloadUrl ??
                      updateInfo.releasePageUrl ??
                      'https://github.com/AkashKumar-Behera/Astra/releases/latest';
                  final uri = Uri.parse(targetUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  'Update Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _proceedToApp() async {
    final user = FirebaseAuth.instance.currentUser;
    Widget destination = const PhoneAuthScreen();

    if (user != null) {
      final profile = await AuthService.getUserProfile(user.uid);
      if (profile != null &&
          profile['name'] != null &&
          (profile['name'] as String).isNotEmpty) {
        destination = HomeScreen(
          userName: profile['name'],
          photoUrl: profile['photo_url'] as String?,
        );
      } else {
        destination = ProfileSetupScreen(
          phoneNumber: user.phoneNumber ?? '',
          uid: user.uid,
        );
      }
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => destination,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
        fit: StackFit.expand,
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

          // Cosmic Dark Overlay Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AstraTheme.background.withOpacity(0.3),
                    AstraTheme.background.withOpacity(0.7),
                    AstraTheme.background.withOpacity(0.95),
                  ],
                ),
              ),
            ),
          ),

          // Main Logo & Branding
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Glowing Planet / Nebula aura
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AstraTheme.primary.withOpacity(
                                    _glowAnimation.value * 0.6),
                                blurRadius: 48,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(70),
                            child: Image.asset(
                              'assets/images/Astra.png',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.auto_awesome,
                                  size: 64,
                                  color: AstraTheme.primaryLight,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // App Name
                        const Text(
                          'Astra',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 4.0,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Tagline
                        Text(
                          'Closer. Always.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 3.0,
                            color: AstraTheme.primaryLight.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Loading Space Text
          Positioned(
            bottom: 64,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AstraTheme.primaryLight),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading your space...',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 1.2,
                    color: AstraTheme.textSecondary.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
