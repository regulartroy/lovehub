import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_model.dart';

class FriendLookupException implements Exception {
  FriendLookupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Friends list for one user: `users/{uid}/friends/{friendUid}`.
class FriendRepository {
  FriendRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _friends(String uid) =>
      _db.collection('users').doc(uid).collection('friends');

  Stream<List<FriendModel>> watch(String uid) {
    return _friends(uid).snapshots().map((snap) {
      final friends = snap.docs
          .map((doc) => FriendModel.fromMap(doc.data(), id: doc.id))
          .toList();
      friends.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      return friends;
    });
  }

  /// Adds [query] (an email or a user uid) to [ownerUid]'s friends list.
  /// Toggles start off. Does not change hubs.
  Future<FriendModel> addFriend({
    required String ownerUid,
    required String query,
    String? ownerEmail,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw FriendLookupException('Enter an email or user id.');
    }

    final profile = await _lookupUser(trimmed);
    final friendUid = profile['uid'] as String;
    final email = (profile['email'] as String?)?.trim();

    if (friendUid == ownerUid) {
      throw FriendLookupException("You can't add yourself.");
    }
    final ownerMail = ownerEmail?.trim().toLowerCase();
    if (ownerMail != null &&
        ownerMail.isNotEmpty &&
        email != null &&
        email.toLowerCase() == ownerMail) {
      throw FriendLookupException("You can't add yourself.");
    }

    final existing = await _friends(ownerUid).doc(friendUid).get();
    if (existing.exists) {
      throw FriendLookupException('Already on your friends list.');
    }

    final friend = FriendModel(
      id: friendUid,
      displayName: (profile['displayName'] as String?)?.trim() ?? '',
      email: email,
      photoURL: profile['photoURL'] as String?,
      shareWork: false,
      sharePersonal: false,
      shareBirthdays: false,
    );
    await _friends(ownerUid).doc(friendUid).set({
      ...friend.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return friend;
  }

  Future<void> setShare({
    required String ownerUid,
    required String friendUid,
    required FriendShareKind kind,
    required bool value,
  }) async {
    await _friends(
      ownerUid,
    ).doc(friendUid).update({friendShareField(kind): value});
  }

  Future<void> removeFriend({
    required String ownerUid,
    required String friendUid,
  }) async {
    await _friends(ownerUid).doc(friendUid).delete();
  }

  Future<Map<String, dynamic>> _lookupUser(String query) async {
    if (query.contains('@')) {
      final matches = await _db
          .collection('users')
          .where('email', isEqualTo: query)
          .limit(1)
          .get();
      var docs = matches.docs;
      if (docs.isEmpty && query != query.toLowerCase()) {
        final lower = await _db
            .collection('users')
            .where('email', isEqualTo: query.toLowerCase())
            .limit(1)
            .get();
        docs = lower.docs;
      }
      if (docs.isEmpty) {
        throw FriendLookupException('No LoveHub user found with that email.');
      }
      final data = docs.first.data();
      return {'uid': docs.first.id, ...data};
    }

    final snap = await _db.collection('users').doc(query).get();
    if (!snap.exists) {
      throw FriendLookupException('No LoveHub user found with that id.');
    }
    return {'uid': snap.id, ...snap.data()!};
  }
}
