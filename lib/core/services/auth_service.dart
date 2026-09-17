import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static User? get currentUser => _auth.currentUser;

  /// Check if user has already completed registration and exists in Firestore
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
    } catch (e) {
      // In case of error or new user
    }
    return null;
  }

  /// Uploads or updates profile picture under profile_pictures/{uid}.jpg
  /// Always uses the user's UID to prevent storage clutter and duplicates.
  static Future<String?> uploadProfilePicture({
    required String uid,
    required File file,
  }) async {
    try {
      final ref = _storage.ref().child('profile_pictures').child('$uid.jpg');
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      final uploadTask = await ref.putFile(file, metadata);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  /// Saves or updates the user profile document in Firestore
  static Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String phoneNumber,
    String? photoUrl,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);
    final snapshot = await userRef.get();

    final Map<String, dynamic> data = {
      'uid': uid,
      'name': name,
      'phoneNumber': phoneNumber,
      ...?photoUrl != null ? {'photoUrl': photoUrl} : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!snapshot.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['pairedWith'] = null;
      await userRef.set(data);
    } else {
      await userRef.update(data);
    }
  }

  /// Sign out
  static Future<void> signOut() async {
    await _auth.signOut();
  }
}
