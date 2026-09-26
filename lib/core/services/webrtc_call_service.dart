import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import 'call_sound_service.dart';

enum CallType { audio, video }
enum CallRole { caller, receiver }
enum CallStatus { idle, calling, ringing, connected, ended, declined, failed }

class CallDiagnostics {
  final String iceConnectionState;
  final int bytesSent;
  final int bytesReceived;
  final bool isAudioActive;

  const CallDiagnostics({
    this.iceConnectionState = 'checking',
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.isAudioActive = true,
  });
}

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
  bool isScreenSharing = false;
  MediaStream? _screenStream;

  Timer? _durationTimer;
  int durationSeconds = 0;

  StreamSubscription<DatabaseEvent>? _callSub;
  StreamSubscription<DatabaseEvent>? _iceCandidateSub;

  final List<RTCIceCandidate> _earlyIceCandidates = [];
  bool _isRemoteDescriptionSet = false;

  final StreamController<CallStatus> _statusController = StreamController<CallStatus>.broadcast();
  Stream<CallStatus> get onStatusChanged => _statusController.stream;

  final StreamController<int> _durationController = StreamController<int>.broadcast();
  Stream<int> get onDurationChanged => _durationController.stream;

  bool isMinimized = false;
  final StreamController<bool> _minimizedController = StreamController<bool>.broadcast();
  Stream<bool> get onMinimizedChanged => _minimizedController.stream;

  void setMinimized(bool val) {
    if (isMinimized != val) {
      isMinimized = val;
      _minimizedController.add(val);
    }
  }

  Timer? _statsTimer;
  final StreamController<CallDiagnostics> _diagController = StreamController<CallDiagnostics>.broadcast();
  Stream<CallDiagnostics> get onDiagnosticsChanged => _diagController.stream;
  CallDiagnostics diagnostics = const CallDiagnostics();

  bool _renderersInitialized = false;

  Future<void> initRenderers() async {
    if (!_renderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    }
  }

  Future<bool> _requestPermissions(CallType type) async {
    try {
      final micStatus = await Permission.microphone.request();
      if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
        debugPrint('[WebRtcCallService] Microphone permission denied');
        return false;
      }

      if (type == CallType.video) {
        final camStatus = await Permission.camera.request();
        if (camStatus.isDenied || camStatus.isPermanentlyDenied) {
          debugPrint('[WebRtcCallService] Camera permission denied');
          return false;
        }
      }
      return true;
    } catch (e) {
      debugPrint('[WebRtcCallService] Permission request error: $e');
      return true;
    }
  }

  Future<Map<String, dynamic>> _getIceConfiguration() async {
    final List<Map<String, dynamic>> iceServers = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.relay.metered.ca:80'},
      {
        'urls': [
          'turn:global.relay.metered.ca:80',
          'turn:global.relay.metered.ca:443',
          'turn:global.relay.metered.ca:443?transport=tcp',
          'turns:global.relay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ];

    if (_cfTurnKeyId.isNotEmpty && _cfApiToken.isNotEmpty) {
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

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data != null && data['iceServers'] != null) {
            final dynamic rawIce = data['iceServers'];
            if (rawIce is Map) {
              iceServers.insert(0, Map<String, dynamic>.from(rawIce));
              debugPrint('[WebRtcCallService] Cloudflare TURN credentials generated successfully');
            } else if (rawIce is List) {
              for (final s in rawIce.reversed) {
                if (s is Map) iceServers.insert(0, Map<String, dynamic>.from(s));
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[WebRtcCallService] Cloudflare TURN generate error: $e');
      }
    }

    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
  }

  /// Start outgoing call (Audio or Video)
  Future<void> startCall({
    required String myUid,
    required String partnerUid,
    required String partnerName,
    String? partnerPhoto,
    required CallType type,
  }) async {
    final hasPerms = await _requestPermissions(type);
    if (!hasPerms) {
      _updateStatus(CallStatus.failed);
      return;
    }

    await initRenderers();
    currentRole = CallRole.caller;
    currentCallType = type;
    currentPartnerUid = partnerUid;
    currentPartnerName = partnerName;
    currentPartnerPhoto = partnerPhoto;
    _isRemoteDescriptionSet = false;
    _earlyIceCandidates.clear();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = 'call_${myUid}_${partnerUid}_$timestamp';
    currentCallId = callId;

    _updateStatus(CallStatus.calling);

    // 1. Get media streams (Opus HD Audio + adaptive video)
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': type == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'idealWidth': '1280',
                'idealHeight': '720',
                'maxWidth': '1920',
                'maxHeight': '1080',
                'minFrameRate': '30',
                'maxFrameRate': '60',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = _localStream;

      // Enable all audio tracks explicitly
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = true;
      });

      // Set audio speakerphone defaults
      isSpeakerOn = type == CallType.video;
      Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (e) {
      debugPrint('[WebRtcCallService] Error getting user media: $e');
      _updateStatus(CallStatus.failed);
      return;
    }

    try {
      // 2. Create peer connection
      final config = await _getIceConfiguration();
      _peerConnection = await createPeerConnection(config);

      _localStream?.getTracks().forEach((track) {
        track.enabled = true;
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        debugPrint('[WebRtcCallService] onTrack kind=${event.track.kind}, streams=${event.streams.length}');
        event.track.enabled = true;
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          remoteRenderer.srcObject = _remoteStream;
        }
      };

      _peerConnection?.onAddStream = (MediaStream stream) {
        debugPrint('[WebRtcCallService] onAddStream received with ${stream.getTracks().length} tracks');
        stream.getAudioTracks().forEach((t) => t.enabled = true);
        _remoteStream = stream;
        remoteRenderer.srcObject = stream;
      };

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;
        _rtdb.ref('calls/$callId/caller_candidates').push().set({
          'serverCandidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMlineIndex': candidate.sdpMLineIndex,
        });
      };

      // 3. Create Offer with mandatory receive constraints
      final sdpConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': type == CallType.video,
        },
        'optional': [],
      };

      final offer = await _peerConnection!.createOffer(sdpConstraints);
      await _peerConnection!.setLocalDescription(offer);

      // Start dialing ringback tone
      CallSoundService.instance.startDialingTone();

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
    } catch (e) {
      debugPrint('[WebRtcCallService] Error during startCall offer: $e');
      CallSoundService.instance.stop();
      _updateStatus(CallStatus.failed);
    }
  }

  /// Answer an incoming call
  Future<void> answerCall({
    required String callId,
    required String myUid,
    required String callerUid,
    required CallType type,
  }) async {
    final hasPerms = await _requestPermissions(type);
    if (!hasPerms) {
      _updateStatus(CallStatus.failed);
      return;
    }

    await initRenderers();
    currentRole = CallRole.receiver;
    currentCallType = type;
    currentCallId = callId;
    currentPartnerUid = callerUid;
    _isRemoteDescriptionSet = false;
    _earlyIceCandidates.clear();

    _updateStatus(CallStatus.ringing);
    CallSoundService.instance.stop();

    // 1. Get media streams
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': type == CallType.video
          ? {
              'mandatory': {
                'minWidth': '640',
                'minHeight': '480',
                'idealWidth': '1280',
                'idealHeight': '720',
                'maxWidth': '1920',
                'maxHeight': '1080',
                'minFrameRate': '30',
                'maxFrameRate': '60',
              },
              'facingMode': 'user',
              'optional': [],
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = _localStream;

      // Enable all audio tracks explicitly
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = true;
      });

      isSpeakerOn = type == CallType.video;
      Helper.setSpeakerphoneOn(isSpeakerOn);
    } catch (e) {
      debugPrint('[WebRtcCallService] Error getting receiver media: $e');
      _updateStatus(CallStatus.failed);
      return;
    }

    try {
      // 2. Create peer connection
      final config = await _getIceConfiguration();
      _peerConnection = await createPeerConnection(config);

      _localStream?.getTracks().forEach((track) {
        track.enabled = true;
        _peerConnection?.addTrack(track, _localStream!);
      });

      _peerConnection?.onTrack = (RTCTrackEvent event) {
        debugPrint('[WebRtcCallService] onTrack kind=${event.track.kind}, streams=${event.streams.length}');
        event.track.enabled = true;
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          remoteRenderer.srcObject = _remoteStream;
        }
      };

      _peerConnection?.onAddStream = (MediaStream stream) {
        debugPrint('[WebRtcCallService] onAddStream received with ${stream.getTracks().length} tracks');
        stream.getAudioTracks().forEach((t) => t.enabled = true);
        _remoteStream = stream;
        remoteRenderer.srcObject = stream;
      };

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;
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
      _isRemoteDescriptionSet = true;
      _drainQueuedIceCandidates();

      // 4. Create Answer
      final sdpConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': type == CallType.video,
        },
        'optional': [],
      };

      final answer = await _peerConnection!.createAnswer(sdpConstraints);
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
    } catch (e) {
      debugPrint('[WebRtcCallService] Error during answerCall: $e');
      _updateStatus(CallStatus.failed);
    }
  }

  /// Decline an incoming call
  Future<void> declineCall({
    required String callId,
    required String myUid,
  }) async {
    CallSoundService.instance.playEndedTone();
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
    CallSoundService.instance.playEndedTone();
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
        // Read Answer with retry loop to avoid race conditions
        Map<dynamic, dynamic>? ansMap;
        for (int i = 0; i < 6; i++) {
          final ansSnap = await _rtdb.ref('calls/$callId/answer').get();
          if (ansSnap.exists && ansSnap.value != null) {
            ansMap = Map<dynamic, dynamic>.from(ansSnap.value as Map);
            break;
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (ansMap != null && _peerConnection != null) {
          final answer = RTCSessionDescription(
            ansMap['sdp'] as String,
            ansMap['type'] as String,
          );
          await _peerConnection?.setRemoteDescription(answer);
          _isRemoteDescriptionSet = true;
          _drainQueuedIceCandidates();
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
    _iceCandidateSub = _rtdb.ref('calls/$callId/$candidateNode').onChildAdded.listen((event) async {
      if (event.snapshot.value != null) {
        try {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final serverCandidate = data['serverCandidate'] as String?;
          if (serverCandidate == null || serverCandidate.isEmpty) return;

          final candidate = RTCIceCandidate(
            serverCandidate,
            data['sdpMid'] as String?,
            (data['sdpMlineIndex'] as num?)?.toInt(),
          );

          if (_isRemoteDescriptionSet && _peerConnection != null) {
            await _peerConnection?.addCandidate(candidate);
          } else {
            _earlyIceCandidates.add(candidate);
          }
        } catch (_) {}
      }
    });
  }

  void _drainQueuedIceCandidates() {
    if (_peerConnection == null || !_isRemoteDescriptionSet) return;
    for (final candidate in _earlyIceCandidates) {
      try {
        _peerConnection?.addCandidate(candidate);
      } catch (_) {}
    }
    _earlyIceCandidates.clear();
  }

  void _onCallConnected() {
    durationSeconds = 0;
    _updateStatus(CallStatus.connected);
    CallSoundService.instance.playConnectedChime();
    Helper.setSpeakerphoneOn(isSpeakerOn);

    _localStream?.getAudioTracks().forEach((t) => t.enabled = !isMuted);
    _remoteStream?.getAudioTracks().forEach((t) => t.enabled = true);

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      durationSeconds++;
      _durationController.add(durationSeconds);
    });

    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        int sent = 0;
        int rec = 0;
        for (final report in stats) {
          if (report.values.containsKey('bytesSent')) {
            sent += int.tryParse(report.values['bytesSent'].toString()) ?? 0;
          }
          if (report.values.containsKey('bytesReceived')) {
            rec += int.tryParse(report.values['bytesReceived'].toString()) ?? 0;
          }
        }
        diagnostics = CallDiagnostics(
          iceConnectionState: _peerConnection?.iceConnectionState.toString().split('.').last ?? 'connected',
          bytesSent: sent,
          bytesReceived: rec,
          isAudioActive: !isMuted,
        );
        _diagController.add(diagnostics);
      } catch (_) {}
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
    Helper.setSpeakerphoneOn(isSpeakerOn);
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

  /// Toggle Live Screen Sharing during P2P Video Call
  Future<bool> toggleScreenShare() async {
    if (_peerConnection == null) return false;
    try {
      if (isScreenSharing) {
        await _screenStream?.dispose();
        _screenStream = null;
        isScreenSharing = false;
        if (_localStream != null) {
          final videoTrack = _localStream!.getVideoTracks().firstOrNull;
          if (videoTrack != null) {
            final senders = await _peerConnection!.getSenders();
            final sender = senders.firstWhere((s) => s.track?.kind == 'video');
            await sender.replaceTrack(videoTrack);
            localRenderer.srcObject = _localStream;
          }
        }
      } else {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': false,
        });
        final screenTrack = _screenStream!.getVideoTracks().first;
        final senders = await _peerConnection!.getSenders();
        final sender = senders.firstWhere((s) => s.track?.kind == 'video');
        await sender.replaceTrack(screenTrack);
        localRenderer.srcObject = _screenStream;
        isScreenSharing = true;
      }
      return true;
    } catch (e) {
      debugPrint('[WebRtcCallService] Error toggling screen share: $e');
      return false;
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
    CallSoundService.instance.stop();
    _statsTimer?.cancel();
    _statsTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _callSub?.cancel();
    _callSub = null;
    _iceCandidateSub?.cancel();
    _iceCandidateSub = null;
    _earlyIceCandidates.clear();
    _isRemoteDescriptionSet = false;

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      _screenStream?.getTracks().forEach((track) => track.stop());
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;
    isScreenSharing = false;

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
    setMinimized(false);
  }
}
