import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/friend_model.dart';
import '../services/hub_collection.dart';

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

  /// People who share an existing hub with [ownerUid] and are not already friends.
  Future<List<HubFriendSuggestion>> suggestionsFromExistingHubs({
    required String ownerUid,
    required Set<String> alreadyFriendUids,
  }) async {
    final userDoc = await _db.collection('users').doc(ownerUid).get();
    final joined = Map<String, dynamic>.from(
      userDoc.data()?['joinedHubs'] as Map? ?? const {},
    );
    final byUid = <String, HubFriendSuggestion>{};
    for (final hubId in joined.keys) {
      final hub = await _db.collection(kHubsCollection).doc(hubId).get();
      if (!hub.exists) continue;
      final data = hub.data() ?? {};
      var hubName = (data['name'] as String?)?.trim() ?? '';
      if (hubName.isEmpty) {
        final fromJoined = joined[hubId];
        if (fromJoined is Map) {
          hubName = (fromJoined['name'] as String?)?.trim() ?? '';
        }
      }
      if (hubName.isEmpty) hubName = 'Hub';
      // Some older joinedHubs values were stored with extra quotes.
      if (hubName.length >= 2 &&
          hubName.startsWith('"') &&
          hubName.endsWith('"')) {
        hubName = hubName.substring(1, hubName.length - 1);
      }
      final members = ((data['members'] as List?) ?? [])
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty && id != ownerUid)
          .toList();
      final profiles = Map<String, dynamic>.from(
        data['memberProfiles'] as Map? ?? const {},
      );
      for (final memberId in members) {
        if (alreadyFriendUids.contains(memberId)) continue;
        final profile = profiles[memberId] is Map
            ? Map<String, dynamic>.from(profiles[memberId] as Map)
            : <String, dynamic>{};
        final existing = byUid[memberId];
        final names = [...?existing?.sharedHubNames, hubName];
        byUid[memberId] = HubFriendSuggestion(
          uid: memberId,
          displayName: existing?.displayName.isNotEmpty == true
              ? existing!.displayName
              : ((profile['displayName'] as String?)?.trim() ?? ''),
          email: existing?.email ?? (profile['email'] as String?)?.trim(),
          photoURL: existing?.photoURL ?? profile['photoURL'] as String?,
          sharedHubNames: names,
        );
      }
    }

    // Fill in email from the users collection when the hub profile omitted it.
    for (final uid in byUid.keys.toList()) {
      final current = byUid[uid]!;
      if ((current.email != null && current.email!.isNotEmpty) &&
          current.displayName.isNotEmpty) {
        continue;
      }
      final user = await _db.collection('users').doc(uid).get();
      if (!user.exists) continue;
      final data = user.data() ?? {};
      byUid[uid] = HubFriendSuggestion(
        uid: uid,
        displayName: current.displayName.isNotEmpty
            ? current.displayName
            : ((data['displayName'] as String?)?.trim() ?? ''),
        email: (current.email != null && current.email!.isNotEmpty)
            ? current.email
            : (data['email'] as String?)?.trim(),
        photoURL: current.photoURL ?? data['photoURL'] as String?,
        sharedHubNames: current.sharedHubNames,
      );
    }

    final list = byUid.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }
}
