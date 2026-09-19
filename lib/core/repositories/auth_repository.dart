import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../network/api_client.dart';

class AuthRepository {
  final FirebaseAuth _auth;
  final AstraApiClient _apiClient;

  AuthRepository({
    FirebaseAuth? auth,
    AstraApiClient? apiClient,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _apiClient = apiClient ??
            AstraApiClient(
              tokenProvider: () async => (auth ?? FirebaseAuth.instance).currentUser?.getIdToken(),
            );

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Synchronize user identity with VPS PostgreSQL database
  Future<Map<String, dynamic>> syncUser({
    String? phoneNumber,
    String? displayName,
    String? avatarUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be authenticated with Firebase to sync profile.');
    }

    return await _apiClient.syncAuth(
      phoneNumber: phoneNumber ?? user.phoneNumber,
      displayName: displayName ?? (user.displayName != null && user.displayName!.isNotEmpty ? user.displayName : 'Astra User'),
      avatarUrl: avatarUrl ?? user.photoURL,
    );
  }

  /// Fetch user profile from VPS
  Future<Map<String, dynamic>> getProfile() async {
    return await _apiClient.getCurrentUser();
  }

  /// Sign out from Firebase
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
