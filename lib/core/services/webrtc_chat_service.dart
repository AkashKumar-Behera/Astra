import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class WebRtcChatService {
  final String currentUid;
  final String partnerUid;
  final Function(String message, DateTime time, bool isMe) onMessageReceived;
  final Function(bool isConnected) onConnectionStateChanged;

  static const String _cfTurnKeyId = String.fromEnvironment('CLOUDFLARE_TURN_KEY_ID');
  static const String _cfApiToken = String.fromEnvironment('CLOUDFLARE_TURN_API_TOKEN');

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  StreamSubscription? _signalingSub;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  WebRtcChatService({
    required this.currentUid,
    required this.partnerUid,
    required this.onMessageReceived,
    required this.onConnectionStateChanged,
  });

  String get _roomKey {
    final list = [currentUid, partnerUid]..sort();
    return '${list[0]}_${list[1]}';
  }

  Future<Map<String, dynamic>> _getIceConfiguration() async {
    final fallbackConfig = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {
          'urls': [
            'stun:stun.cloudflare.com:3478',
            'turn:turn.cloudflare.com:3478?transport=udp',
            'turn:turn.cloudflare.com:3478?transport=tcp',
            'turns:turn.cloudflare.com:5349?transport=tcp',
          ],
        }
      ]
    };

    if (_cfTurnKeyId.isEmpty || _cfApiToken.isEmpty) {
      debugPrint('Cloudflare TURN tokens not provided in env. Using default STUN servers.');
      return fallbackConfig;
    }

    try {
      final url = Uri.parse('https://rtc.live.cloudflare.com/v1/turn/keys/$_cfTurnKeyId/credentials/generate');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_cfApiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'ttl': 86400}),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data['iceServers'] != null) {
          final dynamic rawIce = data['iceServers'];
          List<dynamic> iceServersList = [];
          if (rawIce is List) {
            iceServersList = rawIce;
          } else if (rawIce is Map) {
            iceServersList = [rawIce];
          }
          if (iceServersList.isNotEmpty) {
            return {'iceServers': iceServersList};
          }
        }
      }
    } catch (e) {
      debugPrint('Cloudflare TURN fetch error (using fallback): $e');
    }

    return fallbackConfig;
  }

  Future<void> init() async {
    final config = await _getIceConfiguration();

    _peerConnection = await createPeerConnection(config);

    _peerConnection?.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        onConnectionStateChanged(true);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                 state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        onConnectionStateChanged(false);
      }
    };

    _peerConnection?.onIceCandidate = (candidate) {
      _rtdb.ref('webrtc_signaling/$_roomKey/candidates/$currentUid').push().set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Determine who creates the DataChannel (lexicographically first UID)
    if (currentUid.compareTo(partnerUid) < 0) {
      final init = RTCDataChannelInit()..ordered = true;
      _dataChannel = await _peerConnection?.createDataChannel('chat', init);
      _setupDataChannel();
      await _createOffer();
    } else {
      _peerConnection?.onDataChannel = (channel) {
        _dataChannel = channel;
        _setupDataChannel();
      };
    }

    _listenSignaling();
  }

  void _setupDataChannel() {
    _dataChannel?.onMessage = (RTCDataChannelMessage message) {
      try {
        final decoded = jsonDecode(message.text);
        final text = decoded['text'] as String? ?? '';
        final timestamp = decoded['time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(decoded['time'] as int)
            : DateTime.now();
        onMessageReceived(text, timestamp, false);
      } catch (_) {
        onMessageReceived(message.text, DateTime.now(), false);
      }
    };

    _dataChannel?.onDataChannelState = (state) {
      onConnectionStateChanged(state == RTCDataChannelState.RTCDataChannelOpen);
    };
  }

  Future<void> _createOffer() async {
    final offer = await _peerConnection?.createOffer();
    if (offer != null) {
      await _peerConnection?.setLocalDescription(offer);
      await _rtdb.ref('webrtc_signaling/$_roomKey/offer').set({
        'sdp': offer.sdp,
        'type': offer.type,
        'sender': currentUid,
      });
    }
  }

  Future<void> _createAnswer(RTCSessionDescription offer) async {
    await _peerConnection?.setRemoteDescription(offer);
    final answer = await _peerConnection?.createAnswer();
    if (answer != null) {
      await _peerConnection?.setLocalDescription(answer);
      await _rtdb.ref('webrtc_signaling/$_roomKey/answer').set({
        'sdp': answer.sdp,
        'type': answer.type,
        'sender': currentUid,
      });
    }
  }

  void _listenSignaling() {
    _signalingSub = _rtdb.ref('webrtc_signaling/$_roomKey').onValue.listen((event) async {
      if (!event.snapshot.exists || event.snapshot.value == null) return;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);

      // 1. Answer received
      if (data.containsKey('answer') && currentUid.compareTo(partnerUid) < 0) {
        final ans = Map<dynamic, dynamic>.from(data['answer'] as Map);
        if (ans['sender'] != currentUid) {
          final desc = RTCSessionDescription(ans['sdp'], ans['type']);
          await _peerConnection?.setRemoteDescription(desc);
        }
      }

      // 2. Offer received
      if (data.containsKey('offer') && currentUid.compareTo(partnerUid) > 0) {
        final off = Map<dynamic, dynamic>.from(data['offer'] as Map);
        if (off['sender'] != currentUid && _peerConnection?.getRemoteDescription() == null) {
          final desc = RTCSessionDescription(off['sdp'], off['type']);
          await _createAnswer(desc);
        }
      }

      // 3. ICE Candidates
      if (data.containsKey('candidates')) {
        final candidatesMap = Map<dynamic, dynamic>.from(data['candidates'] as Map);
        if (candidatesMap.containsKey(partnerUid)) {
          final partnerCandidates = Map<dynamic, dynamic>.from(candidatesMap[partnerUid] as Map);
          for (final cData in partnerCandidates.values) {
            final c = Map<dynamic, dynamic>.from(cData as Map);
            final candidate = RTCIceCandidate(
              c['candidate'],
              c['sdpMid'],
              c['sdpMLineIndex'],
            );
            await _peerConnection?.addCandidate(candidate);
          }
        }
      }
    });
  }

  bool sendMessage(String text) {
    final now = DateTime.now();
    final payload = jsonEncode({
      'text': text,
      'time': now.millisecondsSinceEpoch,
    });

    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(payload));
      onMessageReceived(text, now, true);
      return true;
    } else {
      // Fallback message over RTDB if P2P channel not yet open
      _rtdb.ref('chat_fallback/$_roomKey').push().set({
        'text': text,
        'sender': currentUid,
        'time': now.millisecondsSinceEpoch,
      });
      onMessageReceived(text, now, true);
      return true;
    }
  }

  void dispose() {
    _signalingSub?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
  }
}
