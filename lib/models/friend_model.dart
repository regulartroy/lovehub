import 'package:cloud_firestore/cloud_firestore.dart';

/// Mutual friendship stored at `friends/{uidA_uidB}`.
///
/// The document id is the two Firebase Auth uids in lexicographic order,
/// joined with an underscore. [members] is those same two uids, sorted.
/// [sharing] is keyed by uid and holds what that person shares with the other.
class Friendship {
  const Friendship({
    required this.id,
    required this.members,
    this.memberProfiles = const {},
    this.sharing = const {},
    this.createdAt,
  });

  final String id;
  final List<String> members;
  final Map<String, FriendProfile> memberProfiles;
  final Map<String, FriendSharing> sharing;
  final DateTime? createdAt;

  factory Friendship.fromMap(Map<String, dynamic> data, {required String id}) {
    final members = ((data['members'] as List?) ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    return Friendship(
      id: id,
      members: members,
      memberProfiles: _profiles(data['memberProfiles']),
      sharing: _sharing(data['sharing']),
      createdAt: _readDate(data['createdAt']),
    );
  }

  String? otherUid(String myUid) {
    for (final uid in members) {
      if (uid != myUid) return uid;
    }
    return null;
  }

  FriendProfile otherProfile(String myUid) {
    final uid = otherUid(myUid);
    if (uid == null) return const FriendProfile();
    return memberProfiles[uid] ?? FriendProfile(id: uid);
  }

  FriendSharing mySharing(String myUid) {
    return sharing[myUid] ?? const FriendSharing();
  }

  static Map<String, FriendProfile> _profiles(Object? raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) {
      final map = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      return MapEntry(
        key.toString(),
        FriendProfile.fromMap(map, id: key.toString()),
      );
    });
  }

  static Map<String, FriendSharing> _sharing(Object? raw) {
    if (raw is! Map) return {};
    return raw.map((key, value) {
      final map = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      return MapEntry(key.toString(), FriendSharing.fromMap(map));
    });
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class FriendProfile {
  const FriendProfile({
    this.id = '',
    this.displayName = '',
    this.email,
    this.photoURL,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? photoURL;

  factory FriendProfile.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return FriendProfile(
      id: id,
      displayName: (data['displayName'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim(),
      photoURL: data['photoURL'] as String?,
    );
  }

  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (email != null && email!.isNotEmpty) return email!;
    return 'Friend';
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      if (email != null && email!.isNotEmpty) 'email': email,
      if (photoURL != null && photoURL!.isNotEmpty) 'photoURL': photoURL,
    };
  }
}

/// What one person shares with the other in a friendship. All off by default.
class FriendSharing {
  const FriendSharing({
    this.shareWork = false,
    this.sharePersonal = false,
    this.shareBirthdays = false,
  });

  final bool shareWork;
  final bool sharePersonal;
  final bool shareBirthdays;

  factory FriendSharing.fromMap(Map<String, dynamic> data) {
    return FriendSharing(
      shareWork: data['shareWork'] == true,
      sharePersonal: data['sharePersonal'] == true,
      shareBirthdays: data['shareBirthdays'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shareWork': shareWork,
      'sharePersonal': sharePersonal,
      'shareBirthdays': shareBirthdays,
    };
  }
}

enum FriendShareKind { work, personal, birthdays }

String friendShareField(FriendShareKind kind) {
  switch (kind) {
    case FriendShareKind.work:
      return 'shareWork';
    case FriendShareKind.personal:
      return 'sharePersonal';
    case FriendShareKind.birthdays:
      return 'shareBirthdays';
  }
}

/// Deterministic id for a two-person friendship: sorted uids joined by `_`.
String friendshipIdFor(String uidA, String uidB) {
  final sorted = [uidA, uidB]..sort();
  return '${sorted[0]}_${sorted[1]}';
}

/// Someone the user already shares an existing hub with, but is not yet a friend.
class HubFriendSuggestion {
  const HubFriendSuggestion({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoURL,
    this.sharedHubNames = const [],
  });

  final String uid;
  final String displayName;
  final String? email;
  final String? photoURL;
  final List<String> sharedHubNames;

  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (email != null && email!.isNotEmpty) return email!;
    return 'Friend';
  }

  String get hubSummary {
    if (sharedHubNames.isEmpty) return 'Shares a hub with you';
    if (sharedHubNames.length == 1) {
      return 'Shares ${sharedHubNames.first} with you';
    }
    return 'Shares ${sharedHubNames.join(', ')} with you';
  }
}
