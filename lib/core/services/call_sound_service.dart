import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// CallSoundService
///
/// In-memory synthesized high-fidelity audio tone generator for Astra Calls:
/// - Dialing ringback tone (Periodic 440Hz + 480Hz dual-frequency tone)
/// - Incoming celestial ringtone (Chirping cosmic electronic marimba melody)
/// - Call connected chime (Rising affirmative 2-note chime)
/// - Call ended drop tone (Descending graceful 2-note chime)
///
/// 100% offline, zero network dependencies, instant zero-latency playback.
class CallSoundService {
  static final CallSoundService instance = CallSoundService._internal();
  CallSoundService._internal();

  AudioPlayer? _player;
  Timer? _loopTimer;
  bool _isPlaying = false;

  Future<void> _initPlayer() async {
    _player ??= AudioPlayer();
    try {
      await _player!.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
  }

  /// Generate a valid 44.1kHz 16-bit Mono WAV byte buffer from sample generator
  static Uint8List _generateWav({
    required double durationSec,
    required double Function(double t) sampleGen,
    double sampleRate = 44100.0,
  }) {
    final numSamples = (durationSec * sampleRate).toInt();
    final dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
    final totalFileSize = 44 + dataSize;

    final buffer = Uint8List(totalFileSize);
    final byteData = ByteData.view(buffer.buffer);

    // RIFF header
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    byteData.setUint32(4, totalFileSize - 8, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate.toInt(), Endian.little); // SampleRate
    byteData.setUint32(28, (sampleRate * 2).toInt(), Endian.little); // ByteRate
    byteData.setUint16(32, 2, Endian.little);  // BlockAlign
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    buffer.setRange(36, 40, 'data'.codeUnits);
    byteData.setUint32(40, dataSize, Endian.little);

    // PCM Sample Data
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final sample = sampleGen(t).clamp(-1.0, 1.0);
      final intSample = (sample * 32767.0).toInt().clamp(-32768, 32767);
      byteData.setInt16(44 + (i * 2), intSample, Endian.little);
    }

    return buffer;
  }

  // 1. Dialing Ringback Tone: 1.5s tone + 2.5s silence cycle
  static final Uint8List _dialToneWav = _generateWav(
    durationSec: 4.0,
    sampleGen: (t) {
      if (t > 1.5) return 0.0;
      // Envelope to soften clicks
      final env = (t < 0.05) ? (t / 0.05) : (t > 1.45 ? (1.5 - t) / 0.05 : 1.0);
      final f1 = math.sin(2 * math.pi * 440.0 * t);
      final f2 = math.sin(2 * math.pi * 480.0 * t);
      return 0.35 * env * (0.5 * f1 + 0.5 * f2);
    },
  );

  // 2. Incoming Ringtone: Cosmic Harmonic Arpeggio
  static final Uint8List _incomingRingWav = _generateWav(
    durationSec: 3.5,
    sampleGen: (t) {
      // 4-note melodic sequence repeating every 3.5s
      const notes = [523.25, 659.25, 783.99, 1046.50]; // C5, E5, G5, C6
      const noteDuration = 0.35;
      final noteIndex = (t / noteDuration).floor();

      if (noteIndex >= 4) return 0.0;

      final noteFreq = notes[noteIndex];
      final noteTime = t - (noteIndex * noteDuration);
      final env = math.exp(-noteTime * 4.5); // decay
      final wave = math.sin(2 * math.pi * noteFreq * noteTime) +
          0.3 * math.sin(2 * math.pi * (noteFreq * 2) * noteTime);

      return 0.45 * env * wave;
    },
  );

  // 3. Connected Chime: Quick 2-note ascending
  static final Uint8List _connectedWav = _generateWav(
    durationSec: 0.6,
    sampleGen: (t) {
      final freq = (t < 0.25) ? 587.33 : 880.00; // D5 -> A5
      final env = math.exp(-((t % 0.25) * 6.0));
      return 0.40 * env * math.sin(2 * math.pi * freq * t);
    },
  );

  // 4. Ended Tone: Descending soft drop
  static final Uint8List _endedWav = _generateWav(
    durationSec: 0.5,
    sampleGen: (t) {
      final freq = (t < 0.20) ? 659.25 : 440.00; // E5 -> A4
      final env = math.exp(-((t % 0.20) * 8.0));
      return 0.35 * env * math.sin(2 * math.pi * freq * t);
    },
  );

  /// Start playing dialing ringback tone on loop (Caller side)
  Future<void> startDialingTone() async {
    await stop();
    await _initPlayer();
    _isPlaying = true;

    try {
      await _player?.play(BytesSource(_dialToneWav));
      _loopTimer = Timer.periodic(const Duration(milliseconds: 4050), (_) async {
        if (_isPlaying && _player != null) {
          try {
            await _player?.play(BytesSource(_dialToneWav));
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[CallSoundService] Error playing dial tone: $e');
    }
  }

  /// Start playing incoming ringtone on loop (Receiver side)
  Future<void> startIncomingRingtone() async {
    await stop();
    await _initPlayer();
    _isPlaying = true;

    try {
      await _player?.play(BytesSource(_incomingRingWav));
      _loopTimer = Timer.periodic(const Duration(milliseconds: 3600), (_) async {
        if (_isPlaying && _player != null) {
          try {
            await _player?.play(BytesSource(_incomingRingWav));
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[CallSoundService] Error playing incoming ringtone: $e');
    }
  }

  /// Play short connected affirmative chime
  Future<void> playConnectedChime() async {
    await stop();
    await _initPlayer();
    try {
      await _player?.play(BytesSource(_connectedWav));
    } catch (_) {}
  }

  /// Play call ended drop tone
  Future<void> playEndedTone() async {
    await stop();
    await _initPlayer();
    try {
      await _player?.play(BytesSource(_endedWav));
    } catch (_) {}
  }

  /// Stop all active audio playback and loop timers
  Future<void> stop() async {
    _isPlaying = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    stop();
    _player?.dispose();
    _player = null;
  }
}
