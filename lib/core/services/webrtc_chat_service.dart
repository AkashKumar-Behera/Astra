import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../network/websocket_client.dart';
import '../repositories/call_repository.dart';

class WebRtcChatService {
  final String currentUid;
  final String partnerUid;
  final Function(String message, DateTime time, bool isMe) onMessageReceived;
  final Function(bool isConnected) onConnectionStateChanged;
  final AstraWebSocketClient? wsClient;

  static const String _cfTurnKeyId = String.fromEnvironment('CLOUDFLARE_TURN_KEY_ID');
  static const String _cfApiToken = String.fromEnvironment('CLOUDFLARE_TURN_API_TOKEN');

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  CallRepository? _callRepo;
  StreamSubscription? _offerSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _iceSub;

  WebRtcChatService({
    required this.currentUid,
    required this.partnerUid,
    required this.onMessageReceived,
    required this.onConnectionStateChanged,
    this.wsClient,
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

    if (wsClient != null) {
      _callRepo = CallRepository(wsClient: wsClient!);
    }

    _peerConnection?.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        onConnectionStateChanged(true);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        onConnectionStateChanged(false);
      }
    };

    _peerConnection?.onIceCandidate = (candidate) {
      if (_callRepo != null) {
        _callRepo!.sendIceCandidate(
          callId: _roomKey,
          recipientId: partnerUid,
          candidate: candidate.candidate ?? '',
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        );
      }
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
      if (_callRepo != null) {
        _callRepo!.sendOffer(
          callId: _roomKey,
          recipientId: partnerUid,
          sdp: offer.sdp ?? '',
        );
      }
    }
  }

  Future<void> _createAnswer(RTCSessionDescription offer) async {
    await _peerConnection?.setRemoteDescription(offer);
    final answer = await _peerConnection?.createAnswer();
    if (answer != null) {
      await _peerConnection?.setLocalDescription(answer);
      if (_callRepo != null) {
        _callRepo!.sendAnswer(
          callId: _roomKey,
          recipientId: partnerUid,
          sdp: answer.sdp ?? '',
        );
      }
    }
  }

  void _listenSignaling() {
    if (_callRepo == null) return;

    _answerSub = _callRepo!.onCallAnswer.listen((event) async {
      final payload = event.payload;
      if (currentUid.compareTo(partnerUid) < 0 && payload['sender_id'] == partnerUid) {
        final sdp = payload['sdp'] as String?;
        if (sdp != null) {
          final desc = RTCSessionDescription(sdp, 'answer');
          await _peerConnection?.setRemoteDescription(desc);
        }
      }
    });

    _offerSub = _callRepo!.onCallOffer.listen((event) async {
      final payload = event.payload;
      if (currentUid.compareTo(partnerUid) > 0 && payload['sender_id'] == partnerUid) {
        final sdp = payload['sdp'] as String?;
        if (sdp != null && _peerConnection?.getRemoteDescription() == null) {
          final desc = RTCSessionDescription(sdp, 'offer');
          await _createAnswer(desc);
        }
      }
    });

    _iceSub = _callRepo!.onIceCandidate.listen((event) async {
      final payload = event.payload;
      if (payload['sender_id'] == partnerUid) {
        final candidateStr = payload['candidate'] as String?;
        if (candidateStr != null && candidateStr.isNotEmpty) {
          final candidate = RTCIceCandidate(
            candidateStr,
            payload['sdp_mid'] as String?,
            payload['sdp_m_line_index'] as int?,
          );
          await _peerConnection?.addCandidate(candidate);
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
    }
    return false;
  }

  void dispose() {
    _offerSub?.cancel();
    _answerSub?.cancel();
    _iceSub?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
  }
}
