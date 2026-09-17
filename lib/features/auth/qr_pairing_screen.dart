import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/astra_theme.dart';
import '../scanner/qr_scanner_modal.dart';

class QrPairingScreen extends StatefulWidget {
  final String userName;
  const QrPairingScreen({super.key, required this.userName});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  final String _pairingCode = "7F3K - 9Q2D - L8MV";
  final TextEditingController _enterCodeController = TextEditingController();
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _pairingCode.replaceAll(' ', '')));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Pairing code copied to clipboard!"),
        duration: Duration(seconds: 2),
        backgroundColor: AstraTheme.cardSurfaceLight,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QrScannerModal(),
    );
  }

  @override
  void dispose() {
    _enterCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
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

          // Cosmic Dark Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AstraTheme.background.withOpacity(0.4),
                    AstraTheme.background.withOpacity(0.85),
                    AstraTheme.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // Top Navigation & Step Indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: AstraTheme.textPrimary, size: 20),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AstraTheme.primary.withOpacity(0.2),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/Astra.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.auto_awesome,
                                        color: AstraTheme.primaryLight, size: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Astra',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AstraTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: _openScanner,
                        icon: const Icon(Icons.qr_code_scanner,
                            color: AstraTheme.primaryLight),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Progress Step (2 of 2)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AstraTheme.primaryLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AstraTheme.primaryLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '2 of 2',
                    style: TextStyle(
                      fontSize: 12,
                      color: AstraTheme.textMuted,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title & Subtitle
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: "Let's ",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: 'Connect',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AstraTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pair with your person to start your private space.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AstraTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // QR Code Card Container
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AstraTheme.cardSurface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AstraTheme.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: AstraTheme.primary.withOpacity(0.15),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Your Pairing QR Code',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Have them scan this code in Astra.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AstraTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // QR Code with Logo Badge Center
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              QrImageView(
                                data: "astra://connect?code=$_pairingCode&user=${widget.userName}",
                                version: QrVersions.auto,
                                size: 190.0,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF0E0E22),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF0E0E22),
                                ),
                              ),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AstraTheme.cardSurface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/Astra.png',
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(Icons.auto_awesome,
                                                color: AstraTheme.primaryLight,
                                                size: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Code Pill with Copy Action
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurfaceLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.copy_outlined,
                                  size: 16, color: AstraTheme.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _pairingCode,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.0,
                                    color: AstraTheme.textPrimary,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _copyCode,
                                child: Text(
                                  _copied ? 'Copied!' : 'Copy',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _copied
                                        ? AstraTheme.accentOnline
                                        : AstraTheme.primaryLight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Divider OR
                  Row(
                    children: [
                      Expanded(
                          child: Divider(color: AstraTheme.borderSubtle)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AstraTheme.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: AstraTheme.borderSubtle)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Enter Pairing Code Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AstraTheme.cardSurface.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AstraTheme.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enter Pairing Code',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'If you have a code from your connection.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AstraTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AstraTheme.borderSubtle),
                          ),
                          child: TextField(
                            controller: _enterCodeController,
                            style: const TextStyle(
                              color: AstraTheme.textPrimary,
                              letterSpacing: 1.5,
                            ),
                            decoration: const InputDecoration(
                              icon: Icon(Icons.link,
                                  size: 18, color: AstraTheme.textSecondary),
                              hintText: 'Enter code',
                              hintStyle: TextStyle(
                                  color: AstraTheme.textMuted, letterSpacing: 0),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Complete Setup Button
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
                          color: AstraTheme.primary.withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          // Trigger Request notification modal or Complete pairing
                          _showRequestSentPopup(context);
                        },
                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Complete Setup',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward,
                                  size: 18, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Just us. Always.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AstraTheme.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestSentPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AstraTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AstraTheme.borderSubtle),
        ),
        title: Row(
          children: const [
            Icon(Icons.send_rounded, color: AstraTheme.primaryLight),
            SizedBox(width: 10),
            Text(
              "Connection Sent!",
              style: TextStyle(color: AstraTheme.textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          "Your connection request has been sent. Once they accept, your private Astra space will open!",
          style: TextStyle(color: AstraTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              "OK",
              style: TextStyle(color: AstraTheme.primaryLight),
            ),
          ),
        ],
      ),
    );
  }
}
