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
      data['connections'] = [];
      await userRef.set(data);
    } else {
      await userRef.update(data);
    }
  }

  /// Updates current user's live coordinates in Firestore
  static Future<void> updateUserLocation({
    required String uid,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'latitude': latitude,
        'longitude': longitude,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Search user by phone number (clean exact match, with or without +91)
  static Future<Map<String, dynamic>?> searchUserByPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return null;

    try {
      // 1. Direct query with exact entered phone
      var query = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: cleanPhone)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }

      // 2. Fallback with +91 if user only entered 10 digits
      if (!cleanPhone.startsWith('+')) {
        final withCountry = '+91$cleanPhone';
        query = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: withCountry)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          return query.docs.first.data();
        }
      } else if (cleanPhone.startsWith('+91') && cleanPhone.length == 13) {
        // Fallback without +91
        final raw10 = cleanPhone.substring(3);
        query = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: raw10)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          return query.docs.first.data();
        }
      }
    } catch (_) {}

    return null;
  }

  /// Adds a mutual connection between current user and target user
  static Future<void> addConnection({
    required String currentUid,
    required Map<String, dynamic> targetUser,
  }) async {
    final currentDoc = _firestore.collection('users').doc(currentUid);
    final targetUid = targetUser['uid'] as String?;
    if (targetUid == null || targetUid == currentUid) return;

    // Add to current user's connections array
    await currentDoc.update({
      'connections': FieldValue.arrayUnion([targetUid]),
      'pairedWith': targetUid,
    });

    // Add to target user's connections array
    await _firestore.collection('users').doc(targetUid).update({
      'connections': FieldValue.arrayUnion([currentUid]),
      'pairedWith': currentUid,
    });
  }

  /// Stream user document with details
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamUser(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  /// Stream partner document with live updates
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamPartner(String partnerUid) {
    return _firestore.collection('users').doc(partnerUid).snapshots();
  }

  /// Removes connection between current user and target user
  static Future<void> removeConnection({
    required String currentUid,
    required String targetUid,
  }) async {
    try {
      await _firestore.collection('users').doc(currentUid).update({
        'connections': FieldValue.arrayRemove([targetUid]),
        'pairedWith': null,
      });
      await _firestore.collection('users').doc(targetUid).update({
        'connections': FieldValue.arrayRemove([currentUid]),
        'pairedWith': null,
      });
    } catch (_) {}
  }

  /// Fetch all users to match against local phone contacts
  static Future<List<Map<String, dynamic>>> fetchAllRegisteredUsers() async {
    try {
      final snap = await _firestore.collection('users').limit(300).get();
      return snap.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Sign out and clean up device token
  static Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).collection('devices').get().then((snap) {
          for (final doc in snap.docs) {
            doc.reference.delete();
          }
        });
      } catch (_) {}
    }
    await _auth.signOut();
  }
}

