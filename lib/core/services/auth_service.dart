import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import '../network/api_client.dart';
import '../repositories/auth_repository.dart';
import '../repositories/friend_repository.dart';
import 'r2_storage_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final AstraApiClient _apiClient = AstraApiClient(
    tokenProvider: () async => _auth.currentUser?.getIdToken(),
  );
  static final AuthRepository _authRepo = AuthRepository(auth: _auth, apiClient: _apiClient);
  static final FriendRepository _friendRepo = FriendRepository(apiClient: _apiClient);

  static User? get currentUser => _auth.currentUser;

  /// Check if user has already completed registration on VPS
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final user = await _apiClient.getCurrentUser();
      if (user.isNotEmpty) {
        final dName = user['display_name'] ?? user['name'];
        final pUrl = user['avatar_url'] ?? user['photo_url'];
        final pNum = user['phone_number'] ?? user['phoneNumber'];
        return {
          ...user,
          'name': dName,
          'display_name': dName,
          'photo_url': pUrl,
          'avatar_url': pUrl,
          'phoneNumber': pNum,
          'phone_number': pNum,
        };
      }
    } catch (_) {}
    return null;
  }

  /// Uploads or updates profile picture via Cloudflare R2 or direct storage
  static Future<String?> uploadProfilePicture({
    required String uid,
    required File file,
  }) async {
    try {
      if (R2StorageService.isConfigured) {
        return await R2StorageService.uploadFile(
          file: file,
          remotePath: 'profile_pictures/$uid.jpg',
          contentType: 'image/jpeg',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Saves or updates the user profile on the VPS backend
  static Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String phoneNumber,
    String? photoUrl,
  }) async {
    await _authRepo.syncUser(
      phoneNumber: phoneNumber,
      displayName: name,
      avatarUrl: photoUrl,
    );
  }

  /// Updates current user's live coordinates on the VPS
  static Future<void> updateUserLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _apiClient.updateLocation(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {}
  }

  /// Adds a mutual connection / sends friend request
  static Future<void> addConnection({
    required String currentUid,
    required Map<String, dynamic> targetUser,
  }) async {
    final targetUid = (targetUser['id'] ?? targetUser['uid']) as String?;
    if (targetUid == null || targetUid == currentUid) return;

    try {
      await _friendRepo.sendFriendRequest(targetUid);
    } catch (_) {}
  }

  /// Stream current user info periodically from VPS
  static Stream<Map<String, dynamic>> streamUser(String uid) async* {
    while (true) {
      try {
        final profile = await _apiClient.getCurrentUser();
        yield profile;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 15));
    }
  }

  /// Removes connection between current user and target user
  static Future<void> removeConnection({
    required String currentUid,
    required String targetUid,
  }) async {
    try {
      await _friendRepo.removeFriend(targetUid);
    } catch (_) {}
  }

  /// Fetch all friends
  static Future<List<Map<String, dynamic>>> fetchFriends() async {
    try {
      return await _friendRepo.listFriends();
    } catch (_) {
      return [];
    }
  }

  /// Look up registered users by phone numbers
  static Future<List<Map<String, dynamic>>> lookupUsers(List<String> phoneNumbers) async {
    try {
      final list = await _apiClient.lookupUsers(phoneNumbers);
      return list.map((u) {
        final dName = u['display_name'] ?? u['name'] ?? 'Astra User';
        final pUrl = u['avatar_url'] ?? u['photo_url'];
        final pNum = u['phone_number'] ?? u['phoneNumber'] ?? '';
        return {
          ...u,
          'uid': u['id'] ?? u['uid'],
          'id': u['id'] ?? u['uid'],
          'name': dName,
          'display_name': dName,
          'phoneNumber': pNum,
          'phone_number': pNum,
          'photoUrl': pUrl,
          'avatar_url': pUrl,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Search registered users by name or phone
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      final list = await _apiClient.searchUsers(query);
      return list.map((u) {
        final dName = u['display_name'] ?? u['name'] ?? 'Astra User';
        final pUrl = u['avatar_url'] ?? u['photo_url'];
        final pNum = u['phone_number'] ?? u['phoneNumber'] ?? '';
        return {
          ...u,
          'uid': u['id'] ?? u['uid'],
          'id': u['id'] ?? u['uid'],
          'name': dName,
          'display_name': dName,
          'phoneNumber': pNum,
          'phone_number': pNum,
          'photoUrl': pUrl,
          'avatar_url': pUrl,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch all registered users / friends fallback
  static Future<List<Map<String, dynamic>>> fetchAllRegisteredUsers() async {
    try {
      return await _friendRepo.listFriends();
    } catch (_) {
      return [];
    }
  }

  /// Sign out and clean up
  static Future<void> signOut() async {
    await _authRepo.signOut();
  }
}
