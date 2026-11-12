import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_model.dart';

class FriendLookupException implements Exception {
  FriendLookupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Mutual friends at `friends/{uidA_uidB}`, with per-person sharing maps.
class FriendRepository {
  FriendRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _friends =>
      _db.collection('friends');

  Stream<List<Friendship>> watch(String uid) {
    return _friends.where('members', arrayContains: uid).snapshots().map((
      snap,
    ) {
      final list = snap.docs
          .map((doc) => Friendship.fromMap(doc.data(), id: doc.id))
          .toList();
      list.sort((a, b) {
        final left = a.otherProfile(uid).label.toLowerCase();
        final right = b.otherProfile(uid).label.toLowerCase();
        return left.compareTo(right);
      });
      return list;
    });
  }

  /// Creates a mutual friendship between [ownerUid] and the user matching
  /// [query] (email or user uid). Both sharing maps start off.
  Future<Friendship> addFriend({
    required String ownerUid,
    required String query,
    String? ownerEmail,
    String? ownerDisplayName,
    String? ownerPhotoURL,
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

    final id = friendshipIdFor(ownerUid, friendUid);
    final existing = await _friends.doc(id).get();
    if (existing.exists) {
      throw FriendLookupException('Already on your friends list.');
    }

    final ownerProfile = FriendProfile(
      id: ownerUid,
      displayName: ownerDisplayName?.trim() ?? '',
      email: ownerEmail?.trim(),
      photoURL: ownerPhotoURL,
    );
    final friendProfile = FriendProfile(
      id: friendUid,
      displayName: (profile['displayName'] as String?)?.trim() ?? '',
      email: email,
      photoURL: profile['photoURL'] as String?,
    );
    final members = [ownerUid, friendUid]..sort();
    const off = FriendSharing();
    final data = {
      'members': members,
      'memberProfiles': {
        ownerUid: ownerProfile.toMap(),
        friendUid: friendProfile.toMap(),
      },
      'sharing': {ownerUid: off.toMap(), friendUid: off.toMap()},
      'createdBy': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _friends.doc(id).set(data);
    return Friendship(
      id: id,
      members: members,
      memberProfiles: {ownerUid: ownerProfile, friendUid: friendProfile},
      sharing: {ownerUid: off, friendUid: off},
    );
  }

  Future<void> setShare({
    required String friendshipId,
    required String ownerUid,
    required FriendShareKind kind,
    required bool value,
  }) async {
    await _friends.doc(friendshipId).update({
      'sharing.$ownerUid.${friendShareField(kind)}': value,
    });
  }

  Future<void> removeFriend(String friendshipId) async {
    await _friends.doc(friendshipId).delete();
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
      return {'uid': docs.first.id, ...docs.first.data()};
    }

    final snap = await _db.collection('users').doc(query).get();
    if (!snap.exists) {
      throw FriendLookupException('No LoveHub user found with that id.');
    }
    return {'uid': snap.id, ...snap.data()!};
  }
}
