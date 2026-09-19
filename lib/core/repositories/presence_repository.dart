import 'dart:async';
import '../network/websocket_client.dart';

class UserPresence {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;

  const UserPresence({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
  });
}

class PresenceRepository {
  final AstraWebSocketClient _wsClient;
  final Map<String, UserPresence> _presenceMap = {};
  final Map<String, StreamController<UserPresence>> _userStreams = {};
  final Map<String, StreamController<bool>> _typingStreams = {};
  StreamSubscription? _presenceSub;
  StreamSubscription? _typingSub;

  PresenceRepository({required AstraWebSocketClient wsClient}) : _wsClient = wsClient {
    _initListeners();
  }

  void _initListeners() {
    _presenceSub = _wsClient.events.where((e) => e.type == 'presence.changed' || e.type == 'presence.state').listen((event) {
      if (event.type == 'presence.state') {
        final users = event.payload['users'] as Map? ?? event.payload;
        users.forEach((key, val) {
          if (val is Map) {
            final uid = key.toString();
            final isOnline = val['status'] == 'online';
            final lastSeenStr = val['last_seen'] as String?;
            final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;
            _updatePresence(uid, isOnline, lastSeen);
          }
        });
      } else if (event.type == 'presence.changed') {
        final payload = event.payload;
        final uid = payload['user_id'] as String?;
        if (uid != null) {
          final isOnline = payload['status'] == 'online';
          final lastSeenStr = payload['last_seen'] as String?;
          final lastSeen = lastSeenStr != null ? DateTime.tryParse(lastSeenStr) : null;
          _updatePresence(uid, isOnline, lastSeen);
        }
      }
    });

    _typingSub = _wsClient.events.where((e) => e.type == 'typing.start' || e.type == 'typing.stop').listen((event) {
      final payload = event.payload;
      final convId = payload['conversation_id'] as String?;
      if (convId != null) {
        final isTyping = event.type == 'typing.start';
        if (_typingStreams.containsKey(convId) && !_typingStreams[convId]!.isClosed) {
          _typingStreams[convId]!.add(isTyping);
        }
      }
    });
  }

  void _updatePresence(String userId, bool isOnline, DateTime? lastSeen) {
    final presence = UserPresence(userId: userId, isOnline: isOnline, lastSeen: lastSeen);
    _presenceMap[userId] = presence;

    if (_userStreams.containsKey(userId) && !_userStreams[userId]!.isClosed) {
      _userStreams[userId]!.add(presence);
    }
  }

  void subscribe(List<String> friendUserIds) {
    if (_wsClient.isConnected && friendUserIds.isNotEmpty) {
      _wsClient.sendEnvelope('presence.subscribe', {'user_ids': friendUserIds});
    }
  }

  bool isUserOnline(String userId) {
    return _presenceMap[userId]?.isOnline ?? false;
  }

  DateTime? getLastSeen(String userId) {
    return _presenceMap[userId]?.lastSeen;
  }

  Stream<UserPresence> streamUserPresence(String userId) {
    final controller = _userStreams.putIfAbsent(userId, () => StreamController<UserPresence>.broadcast());
    if (_presenceMap.containsKey(userId)) {
      controller.add(_presenceMap[userId]!);
    }
    return controller.stream;
  }

  Stream<bool> streamTyping(String conversationId) {
    final controller = _typingStreams.putIfAbsent(conversationId, () => StreamController<bool>.broadcast());
    return controller.stream;
  }

  void sendTypingStart(String conversationId, String recipientId) {
    if (_wsClient.isConnected) {
      _wsClient.sendEnvelope('typing.start', {
        'conversation_id': conversationId,
        'recipient_id': recipientId,
      });
    }
  }

  void sendTypingStop(String conversationId, String recipientId) {
    if (_wsClient.isConnected) {
      _wsClient.sendEnvelope('typing.stop', {
        'conversation_id': conversationId,
        'recipient_id': recipientId,
      });
    }
  }

  void dispose() {
    _presenceSub?.cancel();
    _typingSub?.cancel();
    for (final c in _userStreams.values) {
      c.close();
    }
    for (final c in _typingStreams.values) {
      c.close();
    }
    _userStreams.clear();
    _typingStreams.clear();
  }
}
