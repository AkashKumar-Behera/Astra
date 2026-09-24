import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/astra_theme.dart';
import '../../core/widgets/astra_logo.dart';
import '../../core/widgets/glass_card.dart';
import '../auth/phone_auth_screen.dart';
import '../auth/profile_setup_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Smooth entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.70, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.80, curve: Curves.easeOutCubic),
      ),
    );

    _slideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.15, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Continuous breathing & glow pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _entranceController.forward();
    _checkUpdateAndProceed();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _checkUpdateAndProceed() async {
    // Fast non-blocking update check with quick entrance delay
    final updateFuture = UpdateService.checkForUpdate(
      timeout: const Duration(milliseconds: 1000),
    );
    final delayFuture = Future.delayed(const Duration(milliseconds: 500));

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
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: GlassCard(
            borderRadius: 28,
            padding: const EdgeInsets.all(24),
            backgroundColor: const Color(0xFF0F0D1C).withValues(alpha: 0.90),
            borderColor: AstraTheme.primary.withValues(alpha: 0.35),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AstraTheme.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AstraTheme.primary.withValues(alpha: 0.40),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),

                // Title
                const Text(
                  'Update Available',
                  style: TextStyle(
                    color: AstraTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Version Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AstraTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AstraTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'v${updateInfo.latestVersion}',
                    style: const TextStyle(
                      color: AstraTheme.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Changelog / Description
                Text(
                  updateInfo.releaseNotes?.isNotEmpty == true
                      ? updateInfo.releaseNotes!
                      : 'A new version of Astra is ready with performance improvements and new features.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AstraTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),

                // Action Buttons: Later | Visit Website | Update Now
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _proceedToApp();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(
                            color: AstraTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final uri = Uri.parse('https://astra.croto.in');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: AstraTheme.primary.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Website',
                          style: TextStyle(
                            color: AstraTheme.primaryLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AstraTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AstraTheme.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            final targetUrl = updateInfo.apkDownloadUrl ??
                                updateInfo.releasePageUrl ??
                                'https://astra.croto.in';
                            final uri = Uri.parse(targetUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Update',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _proceedToApp() async {
    final user = FirebaseAuth.instance.currentUser;
    Widget destination = const PhoneAuthScreen();

    if (user != null) {
      try {
        final profile = await AuthService.getUserProfile(user.uid)
            .timeout(const Duration(milliseconds: 900));
        if (profile != null &&
            profile['name'] != null &&
            (profile['name'] as String).trim().isNotEmpty) {
          destination = HomeScreen(
            userName: profile['name'],
            photoUrl: profile['photoUrl'] as String?,
          );
        } else {
          destination = ProfileSetupScreen(
            phoneNumber: user.phoneNumber ?? '',
            uid: user.uid,
          );
        }
      } catch (e) {
        debugPrint('[SplashScreen] Profile fetch timeout/offline fallback: $e');
        // Offline resilience: User is authenticated, boot straight to HomeScreen
        destination = HomeScreen(
          userName: user.displayName ?? 'Astra User',
          photoUrl: user.photoURL,
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
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Nebula Glow Backdrop (No bulky image, pure smooth vector radial gradients)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _pulseController.value;
              return CustomPaint(
                painter: _MinimalNebulaPainter(pulse: pulse),
              );
            },
          ),

          // 2. Central Hero Branding & Redesigned Astra Logo
          Center(
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value),
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Pure Shape Logo (No text, pure geometry)
                          const AstraLogo(
                            size: 110,
                            animate: true,
                            showGlow: true,
                          ),
                          const SizedBox(height: 32),

                          // Typography: "ASTRA" with clean letter spacing & cosmic sheen
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Colors.white,
                                Color(0xFFE0E7FF),
                                Color(0xFFA78BFA),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(bounds),
                            child: const Text(
                              'ASTRA',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 10.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Minimal Cosmic Subtitle Tag
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131124).withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AstraTheme.primary.withValues(alpha: 0.20),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AstraTheme.accentOnline,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AstraTheme.accentOnline,
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'REAL-TIME CONNECTION',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                    color: AstraTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. Bottom Loading Indicator & Version
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AstraTheme.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'v1.0.15',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          color: AstraTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimalist vector nebula painter creating deep OLED cosmic atmosphere with zero image overhead
class _MinimalNebulaPainter extends CustomPainter {
  final double pulse;

  _MinimalNebulaPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.44);

    // Deep Violet Primary Core Glow
    final primaryGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF7C3AED).withValues(alpha: 0.16 + (pulse * 0.05)),
          const Color(0xFF6366F1).withValues(alpha: 0.08 + (pulse * 0.03)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.75));

    canvas.drawCircle(center, size.width * 0.75, primaryGlow);

    // Secondary Cyan Cosmic Accent Orb
    final cyanCenter = Offset(size.width * 0.75, size.height * 0.30);
    final cyanGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.06 + (pulse * 0.02)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: cyanCenter, radius: size.width * 0.45));

    canvas.drawCircle(cyanCenter, size.width * 0.45, cyanGlow);
  }

  @override
  bool shouldRepaint(covariant _MinimalNebulaPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}
