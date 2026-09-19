import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

enum CallType { audio, video }
enum CallRole { caller, receiver }
enum CallStatus { idle, calling, ringing, connected, ended, declined, failed }

class CallRecord {
  final String callId;
  final String partnerUid;
  final String partnerName;
  final String? partnerPhoto;
  final CallType type;
  final bool isOutgoing;
  final bool isMissed;
  final int durationSeconds;
  final int timestamp;

  const CallRecord({
    required this.callId,
    required this.partnerUid,
    required this.partnerName,
    this.partnerPhoto,
    required this.type,
    required this.isOutgoing,
    required this.isMissed,
    required this.durationSeconds,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'callId': callId,
        'partnerUid': partnerUid,
        'partnerName': partnerName,
        'partnerPhoto': partnerPhoto,
        'type': type.name,
        'isOutgoing': isOutgoing,
        'isMissed': isMissed,
        'durationSeconds': durationSeconds,
        'timestamp': timestamp,
      };

  factory CallRecord.fromMap(Map<dynamic, dynamic> map) => CallRecord(
        callId: map['callId'] as String? ?? '',
        partnerUid: map['partnerUid'] as String? ?? '',
        partnerName: map['partnerName'] as String? ?? 'Partner',
        partnerPhoto: map['partnerPhoto'] as String?,
        type: (map['type'] as String?) == 'video' ? CallType.video : CallType.audio,
        isOutgoing: (map['isOutgoing'] as bool?) ?? false,
        isMissed: (map['isMissed'] as bool?) ?? false,
        durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
        timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      );
}

class WebRtcCallService {
  static final WebRtcCallService instance = WebRtcCallService._internal();
  WebRtcCallService._internal();

  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  static const String _cfTurnKeyId = String.fromEnvironment(
    'CLOUDFLARE_TURN_KEY_ID',
    defaultValue: '74dabf4d4fa71affb7922a6ac35e29d4',
  );
  static const String _cfApiToken = String.fromEnvironment(
    'CLOUDFLARE_TURN_API_TOKEN',
    defaultValue: '6dfbbb905ba48e0c90a7fee9907b71f0149cbfb7409d12e51825159c11d3fa32',
  );

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallStatus status = CallStatus.idle;
  CallType currentCallType = CallType.audio;
  CallRole currentRole = CallRole.caller;

  String? currentCallId;
  String? currentPartnerUid;
  String? currentPartnerName;
  String? currentPartnerPhoto;

  bool isMuted = false;
  bool isSpeakerOn = true;
  bool isCameraOff = false;
  bool isFrontCamera = true;

  Timer? _durationTimer;
  int durationSeconds = 0;

  StreamSubscription<DatabaseEvent>? _callSub;
  StreamSubscription<DatabaseEvent>? _iceCandidateSub;

  final StreamController<CallStatus> _statusController = StreamController<CallStatus>.broadcast();
  Stream<CallStatus> get onStatusChanged => _statusController.stream;

  final StreamController<int> _durationController = StreamController<int>.broadcast();
  Stream<int> get onDurationChanged => _durationController.stream;

  bool _renderersInitialized = false;

  Future<void> initRenderers() async {
    if (!_renderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    }
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

    if (_cfTurnKeyId.isEmpty || _cfApiToken.isEmpty) return fallbackConfig;

    try {
      final url = Uri.parse('https://rtc.live.cloudflare.com/v1/turn/keys/$_cfTurnKeyId/credentials/generate');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_cfApiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'ttl': 86400}),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data['iceServers'] != null) {
          final dynamic rawIce = data['iceServers'];
          List<dynamic> iceList = [];
          if (rawIce is List) iceList = rawIce;
          if (rawIce is Map) iceList = [rawIce];
          if (iceList.isNotEmpty) return {'iceServers': iceList};
        }
      }
    } catch (_) {}

    return fallbackConfig;
  }

  /// Start outgoing call (Audio or Video)
  Future<void> startCall({
    required String myUid,
    required String partnerUid,
    required String partnerName,
    String? partnerPhoto,
    required CallType type,
  }) async {
    await initRenderers();
    currentRole = CallRole.caller;
    currentCallType = type;
    currentPartnerUid = partnerUid;
    currentPartnerName = partnerName;
    currentPartnerPhoto = partnerPhoto;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = 'call_${myUid}_${partnerUid}_$timestamp';
    currentCallId = callId;

    _updateStatus(CallStatus.calling);

    // 1. Get media streams
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': type == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Error getting user media: $e');
      _updateStatus(CallStatus.failed);
      return;
    }

    // 2. Create peer connection
    final config = await _getIceConfiguration();
    _peerConnection = await createPeerConnection(config);

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _rtdb.ref('calls/$callId/caller_candidates').push().set({
        'serverCandidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMlineIndex': candidate.sdpMLineIndex,
      });
    };

    // 3. Create Offer
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    // 4. Save call in RTDB
    await _rtdb.ref('calls/$callId').set({
      'callId': callId,
      'callerUid': myUid,
      'receiverUid': partnerUid,
      'partnerName': partnerName,
      'type': type.name,
      'status': 'calling',
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'timestamp': ServerValue.timestamp,
    });

    // 5. Send incoming call notification trigger in RTDB
    await _rtdb.ref('users/$partnerUid/incoming_call').set({
      'callId': callId,
      'callerUid': myUid,
      'callerName': 'Partner',
      'callerPhoto': partnerPhoto,
      'type': type.name,
      'timestamp': ServerValue.timestamp,
    });

    // 6. Listen to call status & answer
    _listenToCallStatus(callId, isCaller: true);
    _listenToIceCandidates(callId, candidateNode: 'receiver_candidates');
  }

  /// Answer an incoming call
  Future<void> answerCall({
    required String callId,
    required String myUid,
    required String callerUid,
    required CallType type,
  }) async {
    await initRenderers();
    currentRole = CallRole.receiver;
    currentCallType = type;
    currentCallId = callId;
    currentPartnerUid = callerUid;

    _updateStatus(CallStatus.ringing);

    // 1. Get media streams
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': type == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Error getting receiver media: $e');
      _updateStatus(CallStatus.failed);
      return;
    }

    // 2. Create peer connection
    final config = await _getIceConfiguration();
    _peerConnection = await createPeerConnection(config);

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
      }
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _rtdb.ref('calls/$callId/receiver_candidates').push().set({
        'serverCandidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMlineIndex': candidate.sdpMLineIndex,
      });
    };

    // 3. Read Offer from RTDB
    final snap = await _rtdb.ref('calls/$callId/offer').get();
    if (!snap.exists || snap.value == null) {
      _updateStatus(CallStatus.failed);
      return;
    }

    final offerMap = Map<dynamic, dynamic>.from(snap.value as Map);
    final offer = RTCSessionDescription(
      offerMap['sdp'] as String,
      offerMap['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);

    // 4. Create Answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // 5. Write Answer to RTDB and update status to connected
    await _rtdb.ref('calls/$callId').update({
      'status': 'connected',
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });

    // Remove incoming call trigger
    await _rtdb.ref('users/$myUid/incoming_call').remove();

    _onCallConnected();
    _listenToCallStatus(callId, isCaller: false);
    _listenToIceCandidates(callId, candidateNode: 'caller_candidates');
  }

  /// Decline an incoming call
  Future<void> declineCall({
    required String callId,
    required String myUid,
  }) async {
    try {
      await _rtdb.ref('calls/$callId').update({'status': 'declined'});
      await _rtdb.ref('users/$myUid/incoming_call').remove();
    } catch (_) {}
    _updateStatus(CallStatus.declined);
    _recordCallHistory(isMissed: true);
    await cleanUp();
  }

  /// End active call
  Future<void> endCall() async {
    if (currentCallId != null) {
      try {
        await _rtdb.ref('calls/$currentCallId').update({
          'status': 'ended',
          'endedAt': ServerValue.timestamp,
        });
        if (currentPartnerUid != null) {
          await _rtdb.ref('users/$currentPartnerUid/incoming_call').remove();
        }
      } catch (_) {}
    }
    _updateStatus(CallStatus.ended);
    _recordCallHistory(isMissed: status == CallStatus.calling);
    await cleanUp();
  }

  void _listenToCallStatus(String callId, {required bool isCaller}) {
    _callSub?.cancel();
    _callSub = _rtdb.ref('calls/$callId/status').onValue.listen((event) async {
      final val = event.snapshot.value as String?;
      if (val == null) return;

      if (val == 'connected' && isCaller && status != CallStatus.connected) {
        // Read Answer
        final ansSnap = await _rtdb.ref('calls/$callId/answer').get();
        if (ansSnap.exists && ansSnap.value != null) {
          final ansMap = Map<dynamic, dynamic>.from(ansSnap.value as Map);
          final answer = RTCSessionDescription(
            ansMap['sdp'] as String,
            ansMap['type'] as String,
          );
          await _peerConnection?.setRemoteDescription(answer);
          _onCallConnected();
        }
      } else if (val == 'ended') {
        _updateStatus(CallStatus.ended);
        _recordCallHistory(isMissed: false);
        await cleanUp();
      } else if (val == 'declined') {
        _updateStatus(CallStatus.declined);
        _recordCallHistory(isMissed: true);
        await cleanUp();
      }
    });
  }

  void _listenToIceCandidates(String callId, {required String candidateNode}) {
    _iceCandidateSub?.cancel();
    _iceCandidateSub = _rtdb.ref('calls/$callId/$candidateNode').onChildAdded.listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final candidate = RTCIceCandidate(
            data['serverCandidate'] as String?,
            data['sdpMid'] as String?,
            (data['sdpMlineIndex'] as num?)?.toInt(),
          );
          _peerConnection?.addCandidate(candidate);
        } catch (_) {}
      }
    });
  }

  void _onCallConnected() {
    durationSeconds = 0;
    _updateStatus(CallStatus.connected);

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      durationSeconds++;
      _durationController.add(durationSeconds);
    });
  }

  void _updateStatus(CallStatus newStatus) {
    status = newStatus;
    _statusController.add(newStatus);
  }

  /// Toggle audio mute
  void toggleMute() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      isMuted = !isMuted;
      _localStream!.getAudioTracks()[0].enabled = !isMuted;
    }
  }

  /// Toggle speakerphone
  void toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    _localStream?.getAudioTracks().forEach((track) {
      track.enableSpeakerphone(isSpeakerOn);
    });
  }

  /// Toggle video camera on/off
  void toggleCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      isCameraOff = !isCameraOff;
      _localStream!.getVideoTracks()[0].enabled = !isCameraOff;
    }
  }

  /// Flip front/back camera
  Future<void> switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final videoTrack = _localStream!.getVideoTracks()[0];
      await Helper.switchCamera(videoTrack);
      isFrontCamera = !isFrontCamera;
    }
  }

  Future<void> _recordCallHistory({required bool isMissed}) async {
    if (currentCallId == null || currentPartnerUid == null) return;
    try {
      final record = CallRecord(
        callId: currentCallId!,
        partnerUid: currentPartnerUid!,
        partnerName: currentPartnerName ?? 'Partner',
        partnerPhoto: currentPartnerPhoto,
        type: currentCallType,
        isOutgoing: currentRole == CallRole.caller,
        isMissed: isMissed,
        durationSeconds: durationSeconds,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Save in RTDB under user's call logs
      await _rtdb.ref('call_logs/$currentPartnerUid/${record.callId}').set(record.toMap());
    } catch (_) {}
  }

  /// Stream call history logs from RTDB
  static Stream<List<CallRecord>> streamCallHistory(String uid) {
    return _rtdb.ref('call_logs/$uid').onValue.map((event) {
      if (event.snapshot.value == null) return [];
      try {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final list = <CallRecord>[];
        data.forEach((k, v) {
          if (v is Map) list.add(CallRecord.fromMap(v));
        });
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      } catch (_) {
        return [];
      }
    });
  }

  /// Listen to incoming call alerts for a given user
  static Stream<Map<String, dynamic>?> listenToIncomingCalls(String myUid) {
    return _rtdb.ref('users/$myUid/incoming_call').onValue.map((event) {
      if (event.snapshot.value == null) return null;
      try {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> cleanUp() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    _callSub?.cancel();
    _callSub = null;
    _iceCandidateSub?.cancel();
    _iceCandidateSub = null;

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      _remoteStream?.getTracks().forEach((track) => track.stop());
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    status = CallStatus.idle;
    currentCallId = null;
    currentPartnerUid = null;
    durationSeconds = 0;
    isMuted = false;
    isCameraOff = false;
    isSpeakerOn = true;
  }
}
