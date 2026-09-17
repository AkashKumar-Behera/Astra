import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/astra_theme.dart';
import '../home/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String phoneNumber;
  final String uid;

  const ProfileSetupScreen({
    super.key,
    required this.phoneNumber,
    required this.uid,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  File? _localImageFile;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 600,
        maxHeight: 600,
      );

      if (picked != null) {
        setState(() {
          _localImageFile = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _handleContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? photoUrl;

      // Upload profile image to Firebase Storage if selected
      // Stored at profile_pictures/{uid}.jpg to overwrite without storage bloat
      if (_localImageFile != null) {
        photoUrl = await AuthService.uploadProfilePicture(
          uid: widget.uid,
          file: _localImageFile!,
        );
      }

      // Save user profile in Firestore
      await AuthService.saveUserProfile(
        uid: widget.uid,
        name: name,
        phoneNumber: widget.phoneNumber,
        photoUrl: photoUrl,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Navigate directly to HomeScreen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userName: name,
            photoUrl: photoUrl,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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

          // Cosmic Dark Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AstraTheme.background.withValues(alpha: 0.5),
                    AstraTheme.background.withValues(alpha: 0.85),
                    AstraTheme.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Column(
                          children: [
                            const SizedBox(height: 36),

                  // Header Astra Icon & Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AstraTheme.primary.withValues(alpha: 0.2),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/Astra.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.auto_awesome,
                                    color: AstraTheme.primaryLight, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Astra',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: AstraTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Progress Step (1 of 2)
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
                          color: AstraTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '1 of 2',
                    style: TextStyle(
                      fontSize: 12,
                      color: AstraTheme.textMuted,
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Title & Subtitle
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Welcome to ',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: 'Astra',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AstraTheme.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Set up your profile for your private space.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AstraTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Profile Avatar Placeholder with Local Preview
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AstraTheme.primary.withValues(alpha: 0.6),
                              width: 2,
                            ),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AstraTheme.cardSurfaceLight,
                                AstraTheme.cardSurface,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AstraTheme.primary.withValues(alpha: 0.25),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: _localImageFile != null
                                ? Image.file(
                                    _localImageFile!,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 68,
                                    color: AstraTheme.textSecondary,
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AstraTheme.primary,
                              border: Border.all(
                                color: AstraTheme.background,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AstraTheme.primary.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 19,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Name Input Field
                  Container(
                    decoration: BoxDecoration(
                      color: AstraTheme.cardSurface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AstraTheme.borderSubtle.withValues(alpha: 0.8),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        color: AstraTheme.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: const InputDecoration(
                        icon: Icon(Icons.person_outline,
                            color: AstraTheme.textSecondary),
                        hintText: 'Your name',
                        hintStyle: TextStyle(color: AstraTheme.textMuted),
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Privacy Note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 14, color: AstraTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Your profile is only visible to your connection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AstraTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(flex: 2),

                  // Continue / Proceed Button
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
                        onTap: _isLoading ? null : _handleContinue,
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
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text(
                                      'Continue',
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

                  const SizedBox(height: 28),
                            ],
                          ),
                        ),
                      ),
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
