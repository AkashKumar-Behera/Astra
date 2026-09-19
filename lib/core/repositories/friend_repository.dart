import 'dart:async';
import '../network/api_client.dart';

class FriendRepository {
  final AstraApiClient _apiClient;

  FriendRepository({AstraApiClient? apiClient})
      : _apiClient = apiClient ?? AstraApiClient();

  Future<Map<String, dynamic>> sendFriendRequest(String recipientUserId) async {
    return await _apiClient.sendFriendRequest(recipientUserId);
  }

  Future<List<Map<String, dynamic>>> listRequests({String type = 'all'}) async {
    return await _apiClient.listFriendRequests(type: type);
  }

  Future<Map<String, dynamic>> acceptRequest(String requestId) async {
    return await _apiClient.respondFriendRequest(requestId: requestId, action: 'accept');
  }

  Future<Map<String, dynamic>> rejectRequest(String requestId) async {
    return await _apiClient.respondFriendRequest(requestId: requestId, action: 'reject');
  }

  Future<Map<String, dynamic>> cancelRequest(String requestId) async {
    return await _apiClient.respondFriendRequest(requestId: requestId, action: 'cancelled');
  }

  Future<List<Map<String, dynamic>>> listFriends() async {
    return await _apiClient.listFriends();
  }

  Future<void> removeFriend(String friendId) async {
    await _apiClient.removeFriend(friendId);
  }
}
