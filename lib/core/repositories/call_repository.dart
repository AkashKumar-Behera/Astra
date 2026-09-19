import 'dart:async';
import '../network/websocket_client.dart';

class CallRepository {
  final AstraWebSocketClient _wsClient;

  CallRepository({required AstraWebSocketClient wsClient}) : _wsClient = wsClient;

  Stream<WsEvent> get onIncomingCall => _wsClient.on('call.incoming');
  Stream<WsEvent> get onCallAccepted => _wsClient.on('call.accepted');
  Stream<WsEvent> get onCallRejected => _wsClient.on('call.rejected');
  Stream<WsEvent> get onCallOffer => _wsClient.on('call.offer');
  Stream<WsEvent> get onCallAnswer => _wsClient.on('call.answer');
  Stream<WsEvent> get onIceCandidate => _wsClient.on('call.ice');
  Stream<WsEvent> get onCallEnded => _wsClient.on('call.ended');

  void sendInvite({
    required String recipientId,
    String callType = 'audio',
  }) {
    _wsClient.sendEnvelope('call.invite', {
      'recipient_id': recipientId,
      'call_type': callType,
    });
  }

  void acceptCall(String callId) {
    _wsClient.sendEnvelope('call.accept', {'call_id': callId});
  }

  void rejectCall(String callId, {String reason = 'declined'}) {
    _wsClient.sendEnvelope('call.reject', {
      'call_id': callId,
      'reason': reason,
    });
  }

  void sendOffer({
    required String callId,
    required String recipientId,
    required String sdp,
  }) {
    _wsClient.sendEnvelope('call.offer', {
      'call_id': callId,
      'recipient_id': recipientId,
      'sdp': sdp,
    });
  }

  void sendAnswer({
    required String callId,
    required String recipientId,
    required String sdp,
  }) {
    _wsClient.sendEnvelope('call.answer', {
      'call_id': callId,
      'recipient_id': recipientId,
      'sdp': sdp,
    });
  }

  void sendIceCandidate({
    required String callId,
    required String recipientId,
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) {
    _wsClient.sendEnvelope('call.ice', {
      'call_id': callId,
      'recipient_id': recipientId,
      'candidate': candidate,
      if (sdpMid != null) 'sdp_mid': sdpMid,
      if (sdpMLineIndex != null) 'sdp_m_line_index': sdpMLineIndex,
    });
  }

  void endCall(String callId) {
    _wsClient.sendEnvelope('call.end', {'call_id': callId});
  }

  void leaveCall(String callId) {
    _wsClient.sendEnvelope('call.leave', {'call_id': callId});
  }
}
