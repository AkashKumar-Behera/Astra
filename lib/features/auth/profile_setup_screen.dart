import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/astra_theme.dart';
import '../../core/widgets/astra_logo.dart';
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
  final FocusNode _nameFocusNode = FocusNode();
  File? _localImageFile;
  bool _isLoading = false;
  bool _hasValidName = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      final valid = _nameController.text.trim().isNotEmpty;
      if (valid != _hasValidName) {
        setState(() => _hasValidName = valid);
      }
    });
  }

  Future<void> _showImagePickerSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AstraTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Choose Profile Photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AstraTheme.textPrimary,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AstraTheme.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: AstraTheme.primaryLight, size: 20),
                ),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AstraTheme.accentCyan.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AstraTheme.accentCyan, size: 20),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_localImageFile != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AstraTheme.accentDanger.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline, color: AstraTheme.accentDanger, size: 20),
                  ),
                  title: const Text('Remove Photo', style: TextStyle(color: AstraTheme.accentDanger, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _localImageFile = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 512,
        maxHeight: 512,
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
            content: Text('Failed to select image: $e'),
            backgroundColor: AstraTheme.accentDanger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _handleContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your name'),
          backgroundColor: AstraTheme.accentDanger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? photoUrl;

      if (_localImageFile != null) {
        photoUrl = await AuthService.uploadProfilePicture(
          uid: widget.uid,
          file: _localImageFile!,
        );
      }

      await AuthService.saveUserProfile(
        uid: widget.uid,
        name: name,
        phoneNumber: widget.phoneNumber,
        photoUrl: photoUrl,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userName: name,
            photoUrl: photoUrl,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: AstraTheme.accentDanger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AstraTheme.background,
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -100,
            left: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AstraTheme.primary.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AstraTheme.secondary.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top App Bar with Astra branding
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AstraLogo(
                        size: 32,
                        animate: false,
                        showGlow: false,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Astra',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: AstraTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Form
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),

                        // Title & Subtitle
                        const Text(
                          'Create Your Profile',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose your photo and enter your name to connect with friends.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AstraTheme.textSecondary,
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Profile Picture Picker
                        GestureDetector(
                          onTap: _showImagePickerSheet,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 124,
                                height: 124,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AstraTheme.primaryLight.withValues(alpha: 0.6),
                                    width: 2.2,
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
                                      color: AstraTheme.primary.withValues(alpha: 0.28),
                                      blurRadius: 24,
                                      spreadRadius: 2,
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
                                          Icons.person_rounded,
                                          size: 64,
                                          color: AstraTheme.textSecondary,
                                        ),
                                ),
                              ),

                              // Camera badge icon
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [AstraTheme.primary, AstraTheme.secondary],
                                  ),
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
                                  Icons.camera_alt_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _showImagePickerSheet,
                          child: Text(
                            _localImageFile != null ? 'Change photo' : 'Add profile photo',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AstraTheme.primaryLight,
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Name Input Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: AstraTheme.cardSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _nameFocusNode.hasFocus
                                  ? AstraTheme.primaryLight
                                  : AstraTheme.borderSubtle,
                              width: _nameFocusNode.hasFocus ? 1.6 : 1.0,
                            ),
                            boxShadow: _nameFocusNode.hasFocus
                                ? [
                                    BoxShadow(
                                      color: AstraTheme.primary.withValues(alpha: 0.2),
                                      blurRadius: 14,
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline_rounded, color: AstraTheme.textSecondary, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _nameController,
                                  focusNode: _nameFocusNode,
                                  textCapitalization: TextCapitalization.words,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AstraTheme.textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'Enter your name',
                                    hintStyle: TextStyle(
                                      fontSize: 15,
                                      color: AstraTheme.textMuted,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) {
                                    if (_hasValidName && !_isLoading) _handleContinue();
                                  },
                                ),
                              ),
                              if (_nameController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18, color: AstraTheme.textMuted),
                                  onPressed: () => _nameController.clear(),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Privacy Indicator
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: AstraTheme.textSecondary),
                            SizedBox(width: 6),
                            Text(
                              'Only shared with your mutual connections',
                              style: TextStyle(
                                fontSize: 12,
                                color: AstraTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 36),

                        // Continue Button
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: _hasValidName
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
                            boxShadow: _hasValidName
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
                              onTap: (_hasValidName && !_isLoading) ? _handleContinue : null,
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
                                            'Enter Astra',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _hasValidName ? Colors.white : AstraTheme.textMuted,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                            color: _hasValidName ? Colors.white : AstraTheme.textMuted,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
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
