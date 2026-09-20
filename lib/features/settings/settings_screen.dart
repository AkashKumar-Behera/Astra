import 'package:flutter/material.dart';
import '../../core/services/presence_service.dart';
import '../../core/theme/astra_theme.dart';
import '../calls/call_history_screen.dart';
import 'profile_settings_modal.dart';

class SettingsScreen extends StatelessWidget {
  final String userName;
  final String? photoUrl;
  final String? myPhone;
  final String? partnerUid;
  final String? partnerName;
  final VoidCallback? onDisconnect;

  const SettingsScreen({
    super.key,
    required this.userName,
    this.photoUrl,
    this.myPhone,
    this.partnerUid,
    this.partnerName,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A12),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),

              const SizedBox(height: 12),

              // Title "Settings"
              const Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(height: 20),

              // User Profile Card
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ProfileSettingsModal(
                      initialName: userName,
                      initialPhotoUrl: photoUrl,
                      myPhone: myPhone ?? '',
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131522),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
                        backgroundImage:
                            photoUrl != null ? NetworkImage(photoUrl!) : null,
                        child: photoUrl == null
                            ? Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Your Astra profile',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white38, size: 22),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Main Preferences Group Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131522),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(
                      icon: Icons.nightlight_round,
                      title: 'Appearance',
                      subtitle: 'Dark',
                      onTap: () {},
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.05)),
                    _buildSettingsTile(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      subtitle: 'Calls, messages & alerts',
                      onTap: () {},
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.05)),
                    _buildSettingsTile(
                      icon: Icons.call_outlined,
                      title: 'Call settings',
                      subtitle: 'Audio & video',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
                        );
                      },
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.05)),
                    _buildSettingsTile(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      subtitle: 'Live location & permissions',
                      onTap: () {},
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.05)),
                    _buildSettingsTile(
                      icon: Icons.shield_outlined,
                      title: 'Privacy & Security',
                      subtitle: 'Permissions, connection & data',
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Connection & About Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF131522),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  children: [
                    if (partnerUid != null && partnerUid!.isNotEmpty) ...[
                      StreamBuilder<PartnerPresence>(
                        stream: PresenceService.streamPartnerPresence(partnerUid!),
                        builder: (context, snapshot) {
                          final isOnline = snapshot.data?.isOnline ?? false;

                          return _buildSettingsTile(
                            icon: Icons.link_rounded,
                            title: 'Connection',
                            subtitle: 'Connected to ${partnerName ?? "Partner"}',
                            trailingWidget: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? const Color(0xFF2ED573)
                                        : Colors.white30,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  isOnline ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    color: isOnline
                                        ? const Color(0xFF2ED573)
                                        : Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    color: Colors.white38, size: 20),
                              ],
                            ),
                            onTap: () {},
                          );
                        },
                      ),
                      Divider(color: Colors.white.withValues(alpha: 0.05)),
                    ],
                    _buildSettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About Astra',
                      subtitle: 'Version 1.0.9',
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Danger Zone: Remove Connection
              if (partnerUid != null && partnerUid!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131522),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4757).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFFF6B81), size: 20),
                    ),
                    title: const Text(
                      'Remove connection',
                      style: TextStyle(
                        color: Color(0xFFFF6B81),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white38, size: 20),
                    onTap: onDisconnect,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'This removes your connection with ${partnerName ?? "your partner"}.',
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailingWidget,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailingWidget ??
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}
