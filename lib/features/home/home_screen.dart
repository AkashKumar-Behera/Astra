import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/astra_theme.dart';
import '../scanner/qr_scanner_modal.dart';

class HomeScreen extends StatefulWidget {
  final String userName;
  final String? photoUrl;

  const HomeScreen({
    super.key,
    required this.userName,
    this.photoUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _openAddConnectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _PhoneSearchConnectionModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

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
                    AstraTheme.background.withValues(alpha: 0.5),
                    AstraTheme.background.withValues(alpha: 0.85),
                    AstraTheme.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Top Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    AstraTheme.primary.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: ClipOval(
                              child: widget.photoUrl != null
                                  ? Image.network(
                                      widget.photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, e, s) =>
                                          const Icon(Icons.person,
                                              color: AstraTheme.textSecondary),
                                    )
                                  : const Icon(Icons.person,
                                      color: AstraTheme.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hi, ${widget.userName}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AstraTheme.textPrimary,
                                ),
                              ),
                              const Text(
                                'Your Cosmic Space',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AstraTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add_alt_1,
                            color: AstraTheme.primaryLight),
                        onPressed: _openAddConnectionModal,
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Realtime Stream of Connections
                  Expanded(
                    child: currentUser == null
                        ? const SizedBox.shrink()
                        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: AuthService.streamUser(currentUser.uid),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                      color: AstraTheme.primary),
                                );
                              }

                              final userData = snapshot.data?.data();
                              final connectionUids = List<String>.from(
                                  userData?['connections'] ?? []);

                              if (connectionUids.isEmpty) {
                                return _buildEmptyState();
                              }

                              return FutureBuilder<List<Map<String, dynamic>>>(
                                future: _fetchConnectedProfiles(connectionUids),
                                builder: (context, profilesSnap) {
                                  if (profilesSnap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                          color: AstraTheme.primary),
                                    );
                                  }

                                  final profiles = profilesSnap.data ?? [];
                                  if (profiles.isEmpty) {
                                    return _buildEmptyState();
                                  }

                                  return ListView.builder(
                                    itemCount: profiles.length,
                                    itemBuilder: (context, index) {
                                      final conn = profiles[index];
                                      final name = conn['name'] ?? 'Partner';
                                      final phone = conn['phoneNumber'] ?? '';
                                      final photo = conn['photoUrl'] as String?;

                                      return Card(
                                        color: AstraTheme.cardSurface,
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: const BorderSide(
                                              color: AstraTheme.borderSubtle),
                                        ),
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: AstraTheme.primary,
                                            backgroundImage: photo != null
                                                ? NetworkImage(photo)
                                                : null,
                                            child: photo == null
                                                ? Text(
                                                    name.isNotEmpty
                                                        ? name[0]
                                                        : 'P',
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                  )
                                                : null,
                                          ),
                                          title: Text(
                                            name,
                                            style: const TextStyle(
                                              color: AstraTheme.textPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            phone,
                                            style: const TextStyle(
                                              color: AstraTheme.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AstraTheme.primary
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Connected',
                                              style: TextStyle(
                                                color: AstraTheme.primaryLight,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchConnectedProfiles(
      List<String> uids) async {
    final List<Map<String, dynamic>> list = [];
    for (final uid in uids) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        list.add(doc.data()!);
      }
    }
    return list;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AstraTheme.primary.withValues(alpha: 0.15),
              border: Border.all(
                color: AstraTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.group_add_outlined,
              size: 42,
              color: AstraTheme.primaryLight,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Connections Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AstraTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Connect with your partner, family, or friend simply using their mobile phone number (WhatsApp style).',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AstraTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [
                  AstraTheme.primary,
                  AstraTheme.secondary,
                ],
              ),
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              onPressed: _openAddConnectionModal,
              icon: const Icon(Icons.person_search,
                  color: Colors.white, size: 20),
              label: const Text(
                'Add by Phone Number',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneSearchConnectionModal extends StatefulWidget {
  const _PhoneSearchConnectionModal();

  @override
  State<_PhoneSearchConnectionModal> createState() =>
      _PhoneSearchConnectionModalState();
}

class _PhoneSearchConnectionModalState
    extends State<_PhoneSearchConnectionModal> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isConnecting = false;
  Map<String, dynamic>? _foundUser;
  bool _searched = false;

  void _searchUser() async {
    final query = _searchController.text.trim();
    if (query.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number (min 10 digits)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _searched = true;
      _foundUser = null;
    });

    final user = await AuthService.searchUserByPhone(query);

    if (mounted) {
      setState(() {
        _isSearching = false;
        _foundUser = user;
      });
    }
  }

  void _connect(Map<String, dynamic> targetUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (targetUser['uid'] == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot connect with your own phone number.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isConnecting = true);

    try {
      await AuthService.addConnection(
        currentUid: currentUser.uid,
        targetUser: targetUser,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected with ${targetUser['name'] ?? 'partner'}! 🎉'),
            backgroundColor: AstraTheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AstraTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AstraTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AstraTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Find & Connect',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AstraTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Search any user simply by mobile number, just like WhatsApp.',
            style: TextStyle(
              fontSize: 13,
              color: AstraTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Search Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AstraTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter phone (e.g. 9876543210)',
                    hintStyle: const TextStyle(color: AstraTheme.textMuted),
                    prefixIcon: const Icon(Icons.phone_android,
                        color: AstraTheme.primaryLight, size: 20),
                    filled: true,
                    fillColor: AstraTheme.background.withValues(alpha: 0.6),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AstraTheme.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AstraTheme.primary, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _searchUser(),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AstraTheme.primary,
                ),
                child: IconButton(
                  icon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.search, color: Colors.white),
                  onPressed: _isSearching ? null : _searchUser,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Search Result Box
          if (_foundUser != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AstraTheme.background.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AstraTheme.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AstraTheme.primary,
                    backgroundImage: _foundUser!['photoUrl'] != null
                        ? NetworkImage(_foundUser!['photoUrl'])
                        : null,
                    child: _foundUser!['photoUrl'] == null
                        ? Text(
                            (_foundUser!['name'] as String?)?.isNotEmpty == true
                                ? (_foundUser!['name'] as String)[0]
                                : 'U',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _foundUser!['name'] ?? 'Astra User',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AstraTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _foundUser!['phoneNumber'] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AstraTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AstraTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onPressed:
                        _isConnecting ? null : () => _connect(_foundUser!),
                    child: _isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Connect',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ] else if (_searched && !_isSearching) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: const [
                    Icon(Icons.person_off_outlined,
                        color: AstraTheme.textMuted, size: 36),
                    SizedBox(height: 8),
                    Text(
                      'No user found with this phone number.',
                      style: TextStyle(color: AstraTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          // Fallback option: Scan QR
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.qr_code_scanner,
                  color: AstraTheme.textSecondary, size: 18),
              label: const Text(
                'Or scan Partner QR Code instead',
                style: TextStyle(color: AstraTheme.textSecondary, fontSize: 13),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const QrScannerModal(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
