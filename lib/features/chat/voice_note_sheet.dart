import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class VoiceNoteSheet extends StatefulWidget {
  final Function(int durationSec) onSend;
  final VoidCallback onCancel;

  const VoiceNoteSheet({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VoiceNoteSheet> createState() => _VoiceNoteSheetState();
}

class _VoiceNoteSheetState extends State<VoiceNoteSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveformController;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveformController.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF131525),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 16),

          // "Recording..." text
          const Text(
            'Recording...',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 6),

          // Timer (00:12)
          Text(
            _formatDuration(_seconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 24),

          // Controls Row: Cancel | Waveform | Send
          Row(
            children: [
              // Cancel Button (X)
              GestureDetector(
                onTap: () {
                  widget.onCancel();
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 24),
                ),
              ),

              // Animated Waveform in center
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedBuilder(
                    animation: _waveformController,
                    builder: (context, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(24, (index) {
                          final phase = (_waveformController.value * 2 * math.pi) +
                              (index * 0.35);
                          final height = 8.0 + (math.sin(phase).abs() * 32.0);
                          final isHighlight = index >= 10 && index <= 14;

                          return Container(
                            width: 3.2,
                            height: height,
                            decoration: BoxDecoration(
                              color: isHighlight
                                  ? Colors.white
                                  : const Color(0xFFA594F9)
                                      .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
              ),

              // Send Button (Purple with send plane)
              GestureDetector(
                onTap: () {
                  final duration = _seconds > 0 ? _seconds : 1;
                  widget.onSend(duration);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFF4834D4)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 24),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Slide up to lock recording
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white38),
              SizedBox(width: 6),
              Text(
                'Slide up to lock recording',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
