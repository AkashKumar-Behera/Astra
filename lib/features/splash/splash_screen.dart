import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/update_service.dart';
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
      duration: const Duration(milliseconds: 1800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _slideAnimation = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Continuous breathing & glow pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
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
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0B24).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFA594F9).withValues(alpha: 0.20),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.75),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glowing Rocket Badge Orb
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFFA594F9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFA594F9).withValues(alpha: 0.45),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.rocket_launch_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    const Text(
                      'New Update Available',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Version Comparison Badge Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B4B).withValues(alpha: 0.60),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFA594F9).withValues(alpha: 0.30),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            updateInfo.currentVersion.startsWith('v')
                                ? updateInfo.currentVersion
                                : 'v${updateInfo.currentVersion}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFFA594F9)),
                          ),
                          Text(
                            updateInfo.latestVersion.startsWith('v')
                                ? updateInfo.latestVersion
                                : 'v${updateInfo.latestVersion}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6), width: 0.8),
                            ),
                            child: Text(
                              updateInfo.isBeta ? 'BETA' : 'NEW',
                              style: const TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Release Notes / What's New Box
                    if (updateInfo.releaseNotes != null && updateInfo.releaseNotes!.trim().isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 140),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13112E).withValues(alpha: 0.70),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 14, color: Color(0xFFA594F9)),
                                SizedBox(width: 6),
                                Text(
                                  'What\'s New',
                                  style: TextStyle(
                                    color: Color(0xFFA594F9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Flexible(
                              child: SingleChildScrollView(
                                child: Text(
                                  updateInfo.releaseNotes!.trim(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      const Text(
                        'A new update is ready with performance improvements, bug fixes, and new features.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Action buttons
                    // 1. Update Now Gradient Button
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFFA594F9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFA594F9).withValues(alpha: 0.40),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final urlStr = updateInfo.apkDownloadUrl ??
                                updateInfo.releasePageUrl ??
                                'https://github.com/AkashKumar-Behera/Astra/releases';
                            final url = Uri.parse(urlStr);
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: const Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.download_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Update Now',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 2. Later Button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _proceedToApp();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Maybe Later',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060515),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Subtle Background Cosmic Graphic
          Positioned.fill(
            child: Opacity(
              opacity: 0.20,
              child: Image.asset(
                'assets/images/Bg image.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          ),

          // 2. Twinkling Ambient Constellation Starfield
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _StarfieldPainter(pulse: _pulseController.value),
                );
              },
            ),
          ),

          // 3. Central Ambient Nebula Glow Orbs
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = _pulseController.value;
              return Stack(
                children: [
                  // Violet / Indigo Nebula Center
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.30,
                    left: MediaQuery.of(context).size.width * 0.18,
                    child: Container(
                      width: 250 + (pulse * 25),
                      height: 250 + (pulse * 25),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.18 + (pulse * 0.08)),
                            blurRadius: 100,
                            spreadRadius: 30,
                          ),
                          BoxShadow(
                            color: const Color(0xFFA594F9).withValues(alpha: 0.14 + (pulse * 0.06)),
                            blurRadius: 80,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // 4. Hero Logo & App Branding
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
                          // Hero Logo Floating Frame
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final floatOffset = math.sin(_pulseController.value * math.pi) * 4.0;
                              return Transform.translate(
                                offset: Offset(0, floatOffset),
                                child: Container(
                                  width: 146,
                                  height: 146,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF14132B).withValues(alpha: 0.60),
                                    border: Border.all(
                                      color: const Color(0xFFA594F9).withValues(alpha: 0.35),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFA594F9).withValues(alpha: 0.35),
                                        blurRadius: 40,
                                        spreadRadius: 4,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.60),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                      child: Center(
                                        child: Image.asset(
                                          'assets/images/transparent_logo.png',
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Image.asset(
                                              'assets/images/Astra.png',
                                              width: 96,
                                              height: 96,
                                              fit: BoxFit.contain,
                                              errorBuilder: (ctx, err, trace) =>
                                                  const Icon(Icons.auto_awesome, size: 64, color: Color(0xFFA594F9)),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 36),

                          // App Name "ASTRA" with Shimmering Gradient
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.white, Color(0xFFDDD6FE)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ).createShader(bounds),
                            child: const Text(
                              'ASTRA',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 8.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Elegant Tagline Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1B4B).withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.0,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'CLOSER',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 3.5,
                                    color: Color(0xFFA594F9),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white38,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'ALWAYS',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 3.5,
                                    color: Colors.white70,
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

          // 5. Bottom Loading Indicator & Encrypted Badge
          Positioned(
            bottom: 52,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Frosted Glass Status Capsule
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0E26).withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing Emerald Beacon
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF34D399),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF34D399)
                                      .withValues(alpha: 0.40 + (_pulseController.value * 0.50)),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Connecting to live network...',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Sleek Animated Linear Progress Bar
                SizedBox(
                  width: 160,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFA594F9)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Subtle Privacy Badge
                const Text(
                  'END-TO-END ENCRYPTED TELEMETRY',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    color: Colors.white24,
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

/// Custom painter that renders deterministic twinkling cosmic starfield
class _StarfieldPainter extends CustomPainter {
  final double pulse;
  _StarfieldPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42); // Deterministic seed
    final paint = Paint()..color = Colors.white;

    for (int i = 0; i < 48; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      final baseAlpha = 0.15 + (rand.nextDouble() * 0.45);
      final twinkle = math.sin((pulse * 2 * math.pi) + (i * 0.5));
      final alpha = (baseAlpha + (twinkle * 0.15)).clamp(0.05, 0.85);

      paint.color = (i % 5 == 0)
          ? const Color(0xFFA594F9).withValues(alpha: alpha)
          : Colors.white.withValues(alpha: alpha);

      final radius = (i % 7 == 0) ? 1.6 : 1.0;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) =>
      oldDelegate.pulse != pulse;
}
