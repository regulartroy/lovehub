import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Google / Firestore photo URLs are usable when they look like a real http URL.
bool isUsablePhotoUrl(String? url) {
  final value = url?.trim() ?? '';
  return value.startsWith('http') && value.length > 10;
}

/// Resolve a hub member photo without inventing a new auth flow.
///
/// Order: Firestore `users/{uid}.photoURL`, then hub `memberProfiles`,
/// then Firebase Auth — but Auth is only valid for the signed-in user.
String resolveMemberPhotoUrl({
  required String uid,
  String? firestorePhotoURL,
  String? hubPhotoURL,
  String? currentUid,
  String? currentAuthPhotoURL,
}) {
  if (isUsablePhotoUrl(firestorePhotoURL)) return firestorePhotoURL!.trim();
  if (isUsablePhotoUrl(hubPhotoURL)) return hubPhotoURL!.trim();
  if (uid == currentUid && isUsablePhotoUrl(currentAuthPhotoURL)) {
    return currentAuthPhotoURL!.trim();
  }
  return '';
}

/// Fields to merge onto `users/{currentUid}` so a partner can read the photo
/// next time. Returns null when Firestore already matches Auth.
Map<String, dynamic>? currentUserProfileUpdates({
  required String? authPhotoURL,
  required String? authDisplayName,
  Map<String, dynamic>? existing,
}) {
  final updates = <String, dynamic>{};
  if (isUsablePhotoUrl(authPhotoURL) &&
      existing?['photoURL'] != authPhotoURL) {
    updates['photoURL'] = authPhotoURL;
  }
  final name = authDisplayName?.trim() ?? '';
  final existingName = (existing?['displayName'] ?? '').toString().trim();
  if (name.isNotEmpty && existingName.isEmpty) {
    updates['displayName'] = name;
  }
  return updates.isEmpty ? null : updates;
}

Map<String, dynamic> hubMemberProfilePayload({
  required String uid,
  String? photoURL,
  String? displayName,
}) {
  final profile = <String, dynamic>{};
  if (isUsablePhotoUrl(photoURL)) profile['photoURL'] = photoURL!.trim();
  final name = displayName?.trim() ?? '';
  if (name.isNotEmpty) profile['displayName'] = name;
  return {
    'memberProfiles': {uid: profile},
  };
}

/// Persist the signed-in Google photo onto `users/{uid}` when it is missing
/// or stale. Call from login / profile load — not on every widget rebuild.
Future<void> syncCurrentUserProfile({
  User? user,
  FirebaseFirestore? firestore,
}) async {
  final current = user ?? FirebaseAuth.instance.currentUser;
  if (current == null) return;
  final db = firestore ?? FirebaseFirestore.instance;
  final ref = db.collection('users').doc(current.uid);
  final snap = await ref.get();
  final updates = currentUserProfileUpdates(
    authPhotoURL: current.photoURL,
    authDisplayName: current.displayName,
    existing: snap.data(),
  );
  if (updates == null) return;
  await ref.set(updates, SetOptions(merge: true));
}

/// Copy the current user's photo onto hub membership so partner Home avatars
/// do not depend on being able to read `users/{otherUid}` in isolation.
Future<void> syncCurrentUserPhotoToHubs({
  required Iterable<String> hubIds,
  User? user,
  FirebaseFirestore? firestore,
}) async {
  final current = user ?? FirebaseAuth.instance.currentUser;
  if (current == null || !isUsablePhotoUrl(current.photoURL)) return;
  final db = firestore ?? FirebaseFirestore.instance;
  final payload = hubMemberProfilePayload(
    uid: current.uid,
    photoURL: current.photoURL,
    displayName: current.displayName,
  );
  for (final hubId in hubIds) {
    if (hubId.isEmpty) continue;
    await db.collection('hubs').doc(hubId).set(payload, SetOptions(merge: true));
  }
}

/// Live hub members with photos resolved from Firestore, hub membership, and
/// Auth (signed-in user only).
class HubMemberDirectory {
  HubMemberDirectory({
    required this.onChanged,
    this.firestore,
    this.currentUser,
    this.meLabel,
  });

  final void Function(List<Map<String, dynamic>> members) onChanged;
  final FirebaseFirestore? firestore;
  final User? currentUser;
  final String? meLabel;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _hubSub;
  final Map<String, StreamSubscription<DocumentSnapshot>> _userSubs = {};
  final Map<String, Map<String, dynamic>> _users = {};
  List<String> _memberIds = [];
  Map<String, dynamic> _hubProfiles = {};

  void watch(String? hubId) {
    _hubSub?.cancel();
    _cancelUserSubs();
    _memberIds = [];
    _users.clear();
    _hubProfiles = {};
    if (hubId == null || hubId.isEmpty) {
      onChanged(const []);
      return;
    }
    _hubSub = _db.collection('hubs').doc(hubId).snapshots().listen((hubDoc) {
      final ids = List<String>.from(hubDoc.data()?['members'] ?? const []);
      _hubProfiles = Map<String, dynamic>.from(
        hubDoc.data()?['memberProfiles'] ?? const {},
      );
      _syncUserListeners(ids);
      _emit();
    });
  }

  void _syncUserListeners(List<String> ids) {
    _memberIds = ids;
    final wanted = ids.toSet();
    for (final uid in _userSubs.keys.toList()) {
      if (wanted.contains(uid)) continue;
      _userSubs.remove(uid)?.cancel();
      _users.remove(uid);
    }
    for (final uid in ids) {
      if (_userSubs.containsKey(uid)) continue;
      _userSubs[uid] = _db.collection('users').doc(uid).snapshots().listen((
        doc,
      ) {
        _users[uid] = doc.data() ?? const {};
        _emit();
      });
    }
  }

  void _emit() {
    final currentUid = currentUser?.uid;
    final authPhoto = currentUser?.photoURL;
    final members = <Map<String, dynamic>>[];
    for (final uid in _memberIds) {
      final data = _users[uid] ?? const <String, dynamic>{};
      final hubProfile = _hubProfiles[uid];
      final hubMap = hubProfile is Map
          ? Map<String, dynamic>.from(hubProfile)
          : const <String, dynamic>{};
      final displayName =
          (data['displayName'] ?? hubMap['displayName'] ?? 'Unknown')
              .toString();
      final isMe = uid == currentUid && meLabel != null;
      members.add({
        'uid': uid,
        'name': isMe ? meLabel! : displayName.split(' ').first,
        'displayName': displayName,
        'photoURL': resolveMemberPhotoUrl(
          uid: uid,
          firestorePhotoURL: data['photoURL']?.toString(),
          hubPhotoURL: hubMap['photoURL']?.toString(),
          currentUid: currentUid,
          currentAuthPhotoURL: authPhoto,
        ),
      });
    }
    onChanged(members);
  }

  void _cancelUserSubs() {
    for (final sub in _userSubs.values) {
      sub.cancel();
    }
    _userSubs.clear();
  }

  void dispose() {
    _hubSub?.cancel();
    _cancelUserSubs();
  }
}
