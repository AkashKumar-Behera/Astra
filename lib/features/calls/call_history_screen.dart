import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/webrtc_call_service.dart';
import '../../core/theme/astra_theme.dart';
import 'voice_call_screen.dart';
import 'video_call_screen.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  bool _showMissedOnly = false;
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _makeCall(CallRecord record, CallType type) async {
    if (_myUid.isEmpty) return;

    await WebRtcCallService.instance.startCall(
      myUid: _myUid,
      partnerUid: record.partnerUid,
      partnerName: record.partnerName,
      partnerPhoto: record.partnerPhoto,
      type: type,
    );

    if (mounted) {
      if (type == CallType.video) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoCallScreen(
              partnerName: record.partnerName,
              partnerPhoto: record.partnerPhoto,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VoiceCallScreen(
              partnerName: record.partnerName,
              partnerPhoto: record.partnerPhoto,
            ),
          ),
        );
      }
    }
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final timeStr =
        '${date.hour > 12 ? date.hour - 12 : date.hour == 0 ? 12 : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';

    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final isYesterday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.subtract(const Duration(days: 1)).day;

    if (isToday) return 'Today • $timeStr';
    if (isYesterday) return 'Yesterday • $timeStr';

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day} • $timeStr';
  }

  String _getDateSection(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday';
    }
    return 'Earlier';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    return '$m min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A12),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar: Back | Calls | More
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Calls',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: Colors.white, size: 24),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Segmented Control: All | Missed
            Center(
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161828),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showMissedOnly = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !_showMissedOnly
                                ? const Color(0xFF4834D4)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'All',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: !_showMissedOnly
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _showMissedOnly = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _showMissedOnly
                                ? const Color(0xFF4834D4)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Missed',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: _showMissedOnly
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Call Records List Stream
            Expanded(
              child: StreamBuilder<List<CallRecord>>(
                stream: WebRtcCallService.streamCallHistory(_myUid),
                builder: (context, snapshot) {
                  var records = snapshot.data ?? [];
                  if (_showMissedOnly) {
                    records = records.where((r) => r.isMissed).toList();
                  }

                  if (records.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_in_talk_outlined,
                              size: 48, color: Colors.white.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            _showMissedOnly ? 'No missed calls' : 'No call history yet',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Group records by Date Section
                  final Map<String, List<CallRecord>> grouped = {};
                  for (final r in records) {
                    final section = _getDateSection(r.timestamp);
                    grouped.putIfAbsent(section, () => []).add(r);
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: grouped.keys.length,
                    itemBuilder: (context, index) {
                      final section = grouped.keys.elementAt(index);
                      final items = grouped[section]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            child: Text(
                              section,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ...items.map((record) => _buildCallTile(record)),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallTile(CallRecord record) {
    final isVideo = record.type == CallType.video;
    final isMissed = record.isMissed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131522),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 26,
            backgroundColor: AstraTheme.primary.withValues(alpha: 0.3),
            backgroundImage: record.partnerPhoto != null
                ? NetworkImage(record.partnerPhoto!)
                : null,
            child: record.partnerPhoto == null
                ? Text(
                    record.partnerName.isNotEmpty
                        ? record.partnerName[0].toUpperCase()
                        : 'P',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  )
                : null,
          ),

          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.partnerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Direction Arrow
                    Icon(
                      record.isOutgoing
                          ? Icons.call_made_rounded
                          : isMissed
                              ? Icons.call_missed_rounded
                              : Icons.call_received_rounded,
                      size: 14,
                      color: isMissed
                          ? const Color(0xFFFF4757)
                          : const Color(0xFF2ED573),
                    ),
                    const SizedBox(width: 5),

                    // Call Type icon
                    Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      size: 13,
                      color: isMissed
                          ? const Color(0xFFFF4757)
                          : const Color(0xFFA594F9),
                    ),
                    const SizedBox(width: 5),

                    // Label e.g. Video Call • 12 min
                    Text(
                      isMissed
                          ? (isVideo ? 'Missed Video Call' : 'Missed Audio Call')
                          : '${isVideo ? "Video Call" : "Audio Call"}${record.durationSeconds > 0 ? " • ${_formatDuration(record.durationSeconds)}" : ""}',
                      style: TextStyle(
                        color: isMissed
                            ? const Color(0xFFFF4757)
                            : Colors.white.withValues(alpha: 0.6),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTimestamp(record.timestamp),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Quick Call Button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: const Color(0xFFA594F9),
                size: 20,
              ),
            ),
            onPressed: () => _makeCall(record, record.type),
          ),
        ],
      ),
    );
  }
}
