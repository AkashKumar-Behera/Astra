import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/astra_theme.dart';
import 'profile_setup_screen.dart';
import 'qr_pairing_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  late String _currentVerificationId;
  int? _currentResendToken;
  bool _isLoading = false;

  int _resendCountdown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _currentResendToken = widget.resendToken;
    _startCountdown();
  }

  void _startCountdown() {
    setState(() => _resendCountdown = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _resendCode() async {
    if (_resendCountdown > 0) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _currentResendToken,
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Resend failed.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _currentVerificationId = verificationId;
            _currentResendToken = resendToken;
            _isLoading = false;
          });
          _startCountdown();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP sent successfully!'),
              backgroundColor: AstraTheme.primary,
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _currentVerificationId,
        smsCode: code,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        // Check if user profile already exists in Firestore
        final profile = await AuthService.getUserProfile(user.uid);

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (profile != null &&
            profile['name'] != null &&
            (profile['name'] as String).isNotEmpty) {
          // Existing User: Navigate to Pairing Screen or Home
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => QrPairingScreen(
                userName: profile['name'],
              ),
            ),
            (route) => false,
          );
        } else {
          // New User: Navigate to Profile Setup Screen (Screen 2)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => ProfileSetupScreen(
                phoneNumber: widget.phoneNumber,
                uid: user.uid,
              ),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
        children: [
          // Background Space Cosmic Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/Bg image.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),

          // Cosmic Dark Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AstraTheme.background.withValues(alpha: 0.5),
                    AstraTheme.background.withValues(alpha: 0.82),
                    AstraTheme.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // Header with Back & Change Number
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AstraTheme.cardSurface.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AstraTheme.borderSubtle.withValues(alpha: 0.5),
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: AstraTheme.textPrimary, size: 18),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Change number',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AstraTheme.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // Astra Glowing Logo
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AstraTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/Astra.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.auto_awesome,
                                color: AstraTheme.primaryLight, size: 40),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // App Title & Tagline
                  const Text(
                    'Astra',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: AstraTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Closer. Always.',
                    style: TextStyle(
                      fontSize: 13,
                      letterSpacing: 1.5,
                      color: AstraTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Heading
                  const Text(
                    'Enter verification code',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AstraTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Phone representation with Edit option
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'We\'ve sent a 6-digit code to\n${widget.phoneNumber}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AstraTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AstraTheme.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // 6 Digit OTP input boxes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return Container(
                        width: 46,
                        height: 58,
                        decoration: BoxDecoration(
                          color: AstraTheme.cardSurface.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _focusNodes[index].hasFocus
                                ? AstraTheme.primaryLight
                                : (_otpControllers[index].text.isNotEmpty
                                    ? AstraTheme.primary.withValues(alpha: 0.7)
                                    : AstraTheme.borderSubtle),
                            width: _focusNodes[index].hasFocus ? 1.8 : 1.2,
                          ),
                          boxShadow: _focusNodes[index].hasFocus
                              ? [
                                  BoxShadow(
                                    color: AstraTheme.primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: TextField(
                            controller: _otpControllers[index],
                            focusNode: _focusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AstraTheme.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && index < 5) {
                                _focusNodes[index + 1].requestFocus();
                              } else if (value.isEmpty && index > 0) {
                                _focusNodes[index - 1].requestFocus();
                              }
                              setState(() {});
                            },
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 24),

                  // Resend Timer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Didn\'t receive the code? ',
                        style: TextStyle(
                          fontSize: 13,
                          color: AstraTheme.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: _resendCountdown == 0 ? _resendCode : null,
                        child: Text(
                          _resendCountdown > 0
                              ? 'Resend in 00:${_resendCountdown.toString().padLeft(2, '0')}'
                              : 'Resend',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _resendCountdown > 0
                                ? AstraTheme.primaryLight
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Verify Button
                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          AstraTheme.primary,
                          AstraTheme.secondary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AstraTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isLoading ? null : _verifyOtp,
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Verify',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Bottom Shield & Privacy Note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 15, color: AstraTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Your number is only used to secure your Astra account.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AstraTheme.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
