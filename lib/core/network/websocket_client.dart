import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WsEvent {
  final int v;
  final String type;
  final String? requestId;
  final Map<String, dynamic> payload;

  const WsEvent({
    this.v = 1,
    required this.type,
    this.requestId,
    this.payload = const {},
  });

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    return WsEvent(
      v: json['v'] as int? ?? 1,
      type: json['type'] as String? ?? 'unknown',
      requestId: json['requestId'] as String?,
      payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : {},
    );
  }

  Map<String, dynamic> toJson() => {
        'v': v,
        'type': type,
        if (requestId != null) 'requestId': requestId,
        'payload': payload,
      };
}

class AstraWebSocketClient {
  final String wsUrl;
  final TokenProvider? tokenProvider;

  static const String defaultWsUrl = 'wss://api.croto.in/ws';

  WebSocket? _socket;
  WsConnectionState _state = WsConnectionState.disconnected;
  final StreamController<WsConnectionState> _stateController = StreamController<WsConnectionState>.broadcast();
  final StreamController<WsEvent> _eventsController = StreamController<WsEvent>.broadcast();

  final Map<String, Completer<WsEvent>> _pendingAcks = {};
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;
  bool _manualDisconnect = false;

  AstraWebSocketClient({
    this.wsUrl = defaultWsUrl,
    this.tokenProvider,
  });

  WsConnectionState get state => _state;
  Stream<WsConnectionState> get stateStream => _stateController.stream;
  Stream<WsEvent> get events => _eventsController.stream;
  bool get isConnected => _state == WsConnectionState.connected;

  Stream<WsEvent> on(String eventType) {
    return _eventsController.stream.where((e) => e.type == eventType);
  }

  Future<void> connect() async {
    if (_isDisposed) return;
    if (_state == WsConnectionState.connected || _state == WsConnectionState.connecting) return;

    _manualDisconnect = false;
    _setState(_reconnectAttempts > 0 ? WsConnectionState.reconnecting : WsConnectionState.connecting);

    try {
      String? token;
      if (tokenProvider != null) {
        token = await tokenProvider!();
      }

      final uri = Uri.parse(wsUrl);
      final headers = <String, dynamic>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      _socket = await WebSocket.connect(
        uri.toString(),
        headers: headers.isNotEmpty ? headers : null,
      ).timeout(const Duration(seconds: 10));

      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);
      _startHeartbeat();

      _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('AstraWebSocketClient connect error: $e');
      _cleanupSocket();
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final text = data is String ? data : utf8.decode(data as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;

      final event = WsEvent.fromJson(Map<String, dynamic>.from(decoded));

      // Check for ACK matching
      if (event.requestId != null && _pendingAcks.containsKey(event.requestId)) {
        _pendingAcks.remove(event.requestId)?.complete(event);
      }

      // Handle pong
      if (event.type == 'pong') {
        return;
      }

      _eventsController.add(event);
    } catch (e) {
      debugPrint('AstraWebSocketClient message decode error: $e');
    }
  }

  void _onError(dynamic err) {
    debugPrint('AstraWebSocketClient socket error: $err');
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('AstraWebSocketClient socket closed');
    _cleanupSocket();
    if (!_manualDisconnect) {
      _scheduleReconnect();
    } else {
      _setState(WsConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (isConnected) {
        sendEnvelope('ping', {});
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed || _manualDisconnect) return;

    _setState(WsConnectionState.reconnecting);
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    // Exponential backoff with jitter: 1s, 2s, 4s, 8s, up to max 30s
    final baseDelay = min(30, pow(2, min(_reconnectAttempts, 5)).toInt());
    final jitter = Random().nextInt(1000);
    final delay = Duration(milliseconds: (baseDelay * 1000) + jitter);

    debugPrint('AstraWebSocketClient reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  void _cleanupSocket() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  String _generateRequestId() {
    return 'req_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
  }

  void sendEnvelope(String type, Map<String, dynamic> payload, {String? requestId}) {
    if (!isConnected || _socket == null) {
      debugPrint('AstraWebSocketClient cannot send $type: not connected');
      return;
    }

    final envelope = {
      'v': 1,
      'type': type,
      if (requestId != null) 'requestId': requestId,
      'payload': payload,
    };

    try {
      _socket!.add(jsonEncode(envelope));
    } catch (e) {
      debugPrint('AstraWebSocketClient send error: $e');
    }
  }

  Future<WsEvent> sendWithAck(
    String type,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!isConnected || _socket == null) {
      throw const SocketException('WebSocket is not connected');
    }

    final requestId = _generateRequestId();
    final completer = Completer<WsEvent>();
    _pendingAcks[requestId] = completer;

    sendEnvelope(type, payload, requestId: requestId);

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingAcks.remove(requestId);
          throw TimeoutException('Timed out waiting for response to $type');
        },
      );
    } catch (e) {
      _pendingAcks.remove(requestId);
      rethrow;
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _cleanupSocket();
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _stateController.close();
    _eventsController.close();
  }
}
