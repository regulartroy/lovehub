import 'package:cloud_firestore/cloud_firestore.dart';

/// A person on the signed-in user's friends list.
///
/// Stored at `users/{uid}/friends/{friendUid}`. The document id is the
/// friend's Firebase Auth uid. Share toggles are what *you* share with them
/// and are independent of hubs.
class FriendModel {
  const FriendModel({
    required this.id,
    this.displayName = '',
    this.email,
    this.photoURL,
    this.shareWork = false,
    this.sharePersonal = false,
    this.shareBirthdays = false,
    this.createdAt,
  });

  /// The friend's user uid (and the Firestore document id).
  final String id;
  final String displayName;
  final String? email;
  final String? photoURL;
  final bool shareWork;
  final bool sharePersonal;
  final bool shareBirthdays;
  final DateTime? createdAt;

  factory FriendModel.fromMap(Map<String, dynamic> data, {required String id}) {
    final created = data['createdAt'];
    return FriendModel(
      id: id,
      displayName: (data['displayName'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim(),
      photoURL: data['photoURL'] as String?,
      shareWork: data['shareWork'] == true,
      sharePersonal: data['sharePersonal'] == true,
      shareBirthdays: data['shareBirthdays'] == true,
      createdAt: created is Timestamp
          ? created.toDate()
          : (created is DateTime ? created : null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      if (email != null && email!.isNotEmpty) 'email': email,
      if (photoURL != null && photoURL!.isNotEmpty) 'photoURL': photoURL,
      'shareWork': shareWork,
      'sharePersonal': sharePersonal,
      'shareBirthdays': shareBirthdays,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  String get label {
    if (displayName.isNotEmpty) return displayName;
    if (email != null && email!.isNotEmpty) return email!;
    return 'Friend';
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
