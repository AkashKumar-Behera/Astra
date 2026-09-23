import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/astra_theme.dart';
import '../../core/widgets/astra_logo.dart';
import 'otp_verification_screen.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isValid = false;
  final String _countryCode = '+91';

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() {
    final raw = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final valid = raw.length == 10;
    if (valid != _isValid) {
      setState(() => _isValid = valid);
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _sendOtp() async {
    final rawNumber = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawNumber.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: AstraTheme.accentDanger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final fullPhoneNumber = '$_countryCode$rawNumber';
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification on supported Android devices handled seamlessly
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Verification failed. Please try again.'),
              backgroundColor: AstraTheme.accentDanger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => OtpVerificationScreen(
                phoneNumber: fullPhoneNumber,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending code: $e'),
            backgroundColor: AstraTheme.accentDanger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AstraTheme.primary.withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AstraTheme.secondary.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      if (canPop)
                        Container(
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: AstraTheme.textPrimary, size: 18),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        )
                      else
                        const SizedBox(width: 44, height: 44),
                      const Spacer(),
                    ],
                  ),
                ),

                // Scrollable Content
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),

                        // Clean Astra Vector Shape Logo
                        const Center(
                          child: AstraLogo(
                            size: 84,
                            animate: true,
                            showGlow: true,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Title & Subtitle
                        const Text(
                          'Welcome to Astra',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter your mobile number to get an instant verification code.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AstraTheme.textSecondary,
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Phone Input Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _phoneFocusNode.hasFocus
                                  ? AstraTheme.primaryLight
                                  : AstraTheme.borderSubtle,
                              width: _phoneFocusNode.hasFocus ? 1.6 : 1.0,
                            ),
                            boxShadow: _phoneFocusNode.hasFocus
                                ? [
                                    BoxShadow(
                                      color: AstraTheme.primary.withValues(alpha: 0.25),
                                      blurRadius: 16,
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              // Country Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AstraTheme.backgroundSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AstraTheme.borderSubtle),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🇮🇳', style: TextStyle(fontSize: 18)),
                                    SizedBox(width: 6),
                                    Text(
                                      '+91',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AstraTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 14),

                              // Digits Input Field
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  focusNode: _phoneFocusNode,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                    color: AstraTheme.textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '98765 43210',
                                    hintStyle: TextStyle(
                                      fontSize: 16,
                                      letterSpacing: 1.0,
                                      color: AstraTheme.textMuted,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) {
                                    if (_isValid && !_isLoading) _sendOtp();
                                  },
                                ),
                              ),

                              if (_phoneController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18, color: AstraTheme.textMuted),
                                  onPressed: () {
                                    _phoneController.clear();
                                    setState(() => _isValid = false);
                                  },
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Action Button
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: _isValid
                                ? const LinearGradient(
                                    colors: [AstraTheme.primary, AstraTheme.secondary],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : LinearGradient(
                                    colors: [
                                      AstraTheme.cardSurfaceLight,
                                      AstraTheme.cardSurface,
                                    ],
                                  ),
                            boxShadow: _isValid
                                ? [
                                    BoxShadow(
                                      color: AstraTheme.primary.withValues(alpha: 0.4),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: (_isValid && !_isLoading) ? _sendOtp : null,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Continue',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _isValid ? Colors.white : AstraTheme.textMuted,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                            color: _isValid ? Colors.white : AstraTheme.textMuted,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Security Guarantee Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_outlined, size: 16, color: AstraTheme.accentOnline),
                              SizedBox(width: 8),
                              Text(
                                'End-to-End Encrypted & Private',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AstraTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
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
