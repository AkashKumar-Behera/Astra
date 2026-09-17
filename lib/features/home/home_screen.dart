import 'package:flutter/material.dart';
import '../../core/theme/astra_theme.dart';
import '../auth/qr_pairing_screen.dart';
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
  // Temporary local connections list for multiple people pairing
  final List<Map<String, String>> _connections = [];

  void _openAddConnectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
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
              'Add Connection',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AstraTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect with your loved ones using QR or Pairing Code.',
              style: TextStyle(
                fontSize: 13,
                color: AstraTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AstraTheme.primary.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.qr_code, color: AstraTheme.primaryLight),
              ),
              title: const Text(
                'Show My QR Code',
                style: TextStyle(
                  color: AstraTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Let others scan your code to connect',
                style: TextStyle(color: AstraTheme.textMuted, fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AstraTheme.textSecondary),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        QrPairingScreen(userName: widget.userName),
                  ),
                );
              },
            ),
            const Divider(color: AstraTheme.borderSubtle, height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AstraTheme.secondary.withValues(alpha: 0.2),
                ),
                child: const Icon(Icons.qr_code_scanner,
                    color: AstraTheme.secondary),
              ),
              title: const Text(
                'Scan Partner QR',
                style: TextStyle(
                  color: AstraTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Scan someone else\'s QR code',
                style: TextStyle(color: AstraTheme.textMuted, fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 16, color: AstraTheme.textSecondary),
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const QrScannerModal(),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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
                                color: AstraTheme.primary.withValues(alpha: 0.5),
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

                  const SizedBox(height: 32),

                  // Empty State or Connections List
                  Expanded(
                    child: _connections.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AstraTheme.primary
                                        .withValues(alpha: 0.15),
                                    border: Border.all(
                                      color: AstraTheme.primary
                                          .withValues(alpha: 0.3),
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
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 32.0),
                                  child: Text(
                                    'Connect with your partner, family, or best friend to start sharing status, widgets, and private space.',
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                    ),
                                    onPressed: _openAddConnectionModal,
                                    icon: const Icon(Icons.add,
                                        color: Colors.white, size: 20),
                                    label: const Text(
                                      'Add New Person',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _connections.length,
                            itemBuilder: (context, index) {
                              final conn = _connections[index];
                              return Card(
                                color: AstraTheme.cardSurface,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(
                                      color: AstraTheme.borderSubtle),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AstraTheme.primary,
                                    child: Text(conn['name']?[0] ?? 'U'),
                                  ),
                                  title: Text(conn['name'] ?? 'User',
                                      style: const TextStyle(
                                          color: AstraTheme.textPrimary)),
                                  subtitle: const Text('Connected',
                                      style: TextStyle(
                                          color: AstraTheme.primaryLight)),
                                ),
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
}
