import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Google / Firestore photo URLs are usable when they look like a real http URL.
bool isUsablePhotoUrl(String? url) {
  final value = url?.trim() ?? '';
  return value.startsWith('http') && value.length > 10;
}

/// First letter for avatar fallbacks.
String memberInitial(String? name) {
  final value = name?.trim() ?? '';
  return value.isEmpty ? '?' : value[0].toUpperCase();
}

/// Normalize Google profile URLs so Flutter web can request a concrete size.
///
/// `lh3.googleusercontent.com` links often omit `=sNN-c` / `sz`. A stable size
/// suffix is more cache-friendly and avoids a few silent 403s.
String hardenPhotoUrl(String? url, {int size = 128}) {
  final value = url?.trim() ?? '';
  if (!isUsablePhotoUrl(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final host = uri.host.toLowerCase();
  if (!host.contains('googleusercontent.com') && !host.contains('ggpht.com')) {
    return value;
  }

  final clamped = size.clamp(32, 512);
  var path = uri.path;
  final sizeSuffix = RegExp(r'=s\d+(-[a-z])?$', caseSensitive: false);
  if (sizeSuffix.hasMatch(path)) {
    path = path.replaceFirst(sizeSuffix, '=s$clamped-c');
  } else {
    path = '$path=s$clamped-c';
  }

  final params = Map<String, String>.from(uri.queryParameters);
  params['sz'] = '$clamped';
  return uri.replace(path: path, queryParameters: params).toString();
}

/// Resolve a hub member photo without inventing a new auth flow.
///
/// Order: request payload, Firestore `users/{uid}.photoURL`, hub
/// `memberProfiles`, then Firebase Auth — Auth is only valid for the
/// signed-in user.
String resolveMemberPhotoUrl({
  required String uid,
  String? requestPhotoURL,
  String? firestorePhotoURL,
  String? hubPhotoURL,
  String? currentUid,
  String? currentAuthPhotoURL,
}) {
  if (isUsablePhotoUrl(requestPhotoURL)) return requestPhotoURL!.trim();
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
  if (profile.isEmpty) return {};
  return {
    'memberProfiles': {uid: profile},
  };
}

/// Nested `memberProfiles` merge for every uid whose hub photo/name is missing
/// or stale. Returns null when the hub document already matches.
Map<String, dynamic>? hubMemberProfilesPatch({
  required Map<String, String> photosByUid,
  Map<String, String> namesByUid = const {},
  Map<String, dynamic> existingHubProfiles = const {},
}) {
  final patch = <String, dynamic>{};
  final uids = {...photosByUid.keys, ...namesByUid.keys};
  for (final uid in uids) {
    final existing = existingHubProfiles[uid];
    final existingMap = existing is Map
        ? Map<String, dynamic>.from(existing)
        : const <String, dynamic>{};
    final photo = photosByUid[uid];
    final name = namesByUid[uid]?.trim() ?? '';
    final existingPhoto = existingMap['photoURL']?.toString();
    final existingName = (existingMap['displayName'] ?? '').toString().trim();

    final needsPhoto = isUsablePhotoUrl(photo) && existingPhoto != photo;
    final needsName = name.isNotEmpty && existingName.isEmpty;
    if (!needsPhoto && !needsName) continue;

    final profile = <String, dynamic>{};
    if (isUsablePhotoUrl(photo)) profile['photoURL'] = photo!.trim();
    if (name.isNotEmpty) profile['displayName'] = name;
    if (profile.isEmpty) continue;
    patch[uid] = profile;
  }
  if (patch.isEmpty) return null;
  return {'memberProfiles': patch};
}

Map<String, dynamic> newHubDocument({
  required String name,
  required String creatorUid,
  String? photoURL,
  String? displayName,
}) {
  return {
    'name': name,
    'members': [creatorUid],
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': creatorUid,
    ...hubMemberProfilePayload(
      uid: creatorUid,
      photoURL: photoURL,
      displayName: displayName,
    ),
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
  if (current == null) return;
  final payload = hubMemberProfilePayload(
    uid: current.uid,
    photoURL: current.photoURL,
    displayName: current.displayName,
  );
  if (payload.isEmpty) return;
  final db = firestore ?? FirebaseFirestore.instance;
  for (final hubId in hubIds) {
    if (hubId.isEmpty) continue;
    await db.collection('hubs').doc(hubId).set(payload, SetOptions(merge: true));
  }
}

class HubPhotoRefreshResult {
  const HubPhotoRefreshResult({
    required this.updated,
    required this.unchanged,
    required this.missingUids,
  });

  final int updated;
  final int unchanged;
  final List<String> missingUids;

  int get missing => missingUids.length;
}

String hubPhotoRefreshMessage(HubPhotoRefreshResult result) {
  if (result.missing == 0 && result.updated == 0) {
    return 'Member photos are already up to date.';
  }
  if (result.missing == 0) {
    return 'Updated ${result.updated} member photo${result.updated == 1 ? '' : 's'}.';
  }
  return 'Updated ${result.updated}. ${result.missing} still missing — they need to open LoveHub once.';
}

Map<String, dynamic> hubProfileMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

/// Re-pull member photos from `users/{uid}` where allowed and write them onto
/// the hub document. Always includes the signed-in Auth photo for self.
Future<HubPhotoRefreshResult> refreshHubMemberPhotos({
  required String hubId,
  FirebaseFirestore? firestore,
  User? currentUser,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  final current = currentUser ?? FirebaseAuth.instance.currentUser;
  final hubSnap = await db.collection('hubs').doc(hubId).get();
  final ids = List<String>.from(hubSnap.data()?['members'] ?? const []);
  final existingProfiles = Map<String, dynamic>.from(
    hubSnap.data()?['memberProfiles'] ?? const {},
  );

  final photos = <String, String>{};
  final names = <String, String>{};
  final missingUids = <String>[];

  for (final uid in ids) {
    String? firestorePhoto;
    String? firestoreName;
    try {
      final userSnap = await db.collection('users').doc(uid).get();
      if (userSnap.exists) {
        firestorePhoto = userSnap.data()?['photoURL']?.toString();
        firestoreName = userSnap.data()?['displayName']?.toString();
      }
    } catch (_) {
      // Partner user docs are often unreadable; hub membership is the fallback.
    }

    final hubMap = hubProfileMap(existingProfiles[uid]);
    final photo = resolveMemberPhotoUrl(
      uid: uid,
      firestorePhotoURL: firestorePhoto,
      hubPhotoURL: hubMap['photoURL']?.toString(),
      currentUid: current?.uid,
      currentAuthPhotoURL: current?.photoURL,
    );
    final name =
        (firestoreName ??
                hubMap['displayName'] ??
                (uid == current?.uid ? current?.displayName : null))
            ?.toString();

    if (isUsablePhotoUrl(photo)) {
      photos[uid] = photo;
    } else {
      missingUids.add(uid);
    }
    if (name != null && name.trim().isNotEmpty) {
      names[uid] = name.trim();
    }
  }

  final patch = hubMemberProfilesPatch(
    photosByUid: photos,
    namesByUid: names,
    existingHubProfiles: existingProfiles,
  );
  if (patch != null) {
    await db.collection('hubs').doc(hubId).set(patch, SetOptions(merge: true));
  }

  return HubPhotoRefreshResult(
    updated: patch == null ? 0 : (patch['memberProfiles'] as Map).length,
    unchanged: ids.length - (patch == null ? 0 : (patch['memberProfiles'] as Map).length),
    missingUids: missingUids,
  );
}

/// Best photo available while approving a join request.
Future<({String? photoURL, String? displayName})> resolveJoinMemberProfile({
  required String uid,
  String? requestPhotoURL,
  String? requestDisplayName,
  FirebaseFirestore? firestore,
  User? currentUser,
}) async {
  final db = firestore ?? FirebaseFirestore.instance;
  String? firestorePhoto;
  String? firestoreName;
  try {
    final userSnap = await db.collection('users').doc(uid).get();
    if (userSnap.exists) {
      firestorePhoto = userSnap.data()?['photoURL']?.toString();
      firestoreName = userSnap.data()?['displayName']?.toString();
    }
  } catch (_) {}

  return (
    photoURL: resolveMemberPhotoUrl(
      uid: uid,
      requestPhotoURL: requestPhotoURL,
      firestorePhotoURL: firestorePhoto,
      currentUid: currentUser?.uid,
      currentAuthPhotoURL: currentUser?.photoURL,
    ),
    displayName:
        (requestDisplayName?.trim().isNotEmpty == true
                ? requestDisplayName
                : firestoreName ?? currentUser?.displayName)
            ?.toString(),
  );
}

/// Live hub members with photos resolved from Firestore, hub membership, and
/// Auth (signed-in user only).
class HubMemberDirectory {
  HubMemberDirectory({
    required this.onChanged,
    this.firestore,
    this.currentUser,
    this.meLabel,
    this.persistDiscoveredPhotos = true,
  });

  final void Function(List<Map<String, dynamic>> members) onChanged;
  final FirebaseFirestore? firestore;
  final User? currentUser;
  final String? meLabel;
  final bool persistDiscoveredPhotos;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _hubSub;
  final Map<String, StreamSubscription<DocumentSnapshot>> _userSubs = {};
  final Map<String, Map<String, dynamic>> _users = {};
  List<String> _memberIds = [];
  Map<String, dynamic> _hubProfiles = {};
  String? _hubId;
  final Map<String, String> _persistedPhotos = {};
  bool _persistScheduled = false;

  void watch(String? hubId) {
    _hubSub?.cancel();
    _cancelUserSubs();
    _memberIds = [];
    _users.clear();
    _hubProfiles = {};
    _hubId = hubId;
    _persistedPhotos.clear();
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
      }, onError: (_) {
        // `users/{other}` is often denied. Keep going on hub membership.
        _users[uid] = const {};
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
      final hubMap = hubProfileMap(_hubProfiles[uid]);
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
    _schedulePersist();
  }

  void _schedulePersist() {
    if (!persistDiscoveredPhotos || _hubId == null || _persistScheduled) {
      return;
    }
    _persistScheduled = true;
    scheduleMicrotask(() async {
      _persistScheduled = false;
      await _persistDiscovered();
    });
  }

  Future<void> _persistDiscovered() async {
    final hubId = _hubId;
    if (hubId == null || hubId.isEmpty) return;

    final photos = <String, String>{};
    final names = <String, String>{};
    final currentUid = currentUser?.uid;
    for (final uid in _memberIds) {
      final data = _users[uid] ?? const <String, dynamic>{};
      final hubMap = hubProfileMap(_hubProfiles[uid]);
      final photo = resolveMemberPhotoUrl(
        uid: uid,
        firestorePhotoURL: data['photoURL']?.toString(),
        hubPhotoURL: hubMap['photoURL']?.toString(),
        currentUid: currentUid,
        currentAuthPhotoURL: currentUser?.photoURL,
      );
      if (!isUsablePhotoUrl(photo)) continue;
      if (_persistedPhotos[uid] == photo && hubMap['photoURL'] == photo) {
        continue;
      }
      photos[uid] = photo;
      final name =
          (data['displayName'] ??
                  hubMap['displayName'] ??
                  (uid == currentUid ? currentUser?.displayName : null))
              ?.toString();
      if (name != null && name.trim().isNotEmpty) {
        names[uid] = name.trim();
      }
    }

    final patch = hubMemberProfilesPatch(
      photosByUid: photos,
      namesByUid: names,
      existingHubProfiles: _hubProfiles,
    );
    if (patch == null) return;
    for (final uid in photos.keys) {
      _persistedPhotos[uid] = photos[uid]!;
    }
    try {
      await _db.collection('hubs').doc(hubId).set(patch, SetOptions(merge: true));
    } catch (_) {
      for (final uid in photos.keys) {
        if (_persistedPhotos[uid] == photos[uid]) {
          _persistedPhotos.remove(uid);
        }
      }
    }
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
