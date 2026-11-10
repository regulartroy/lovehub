import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/member_profile.dart';

void main() {
  test('uses Firestore photo for other members', () {
    expect(
      resolveMemberPhotoUrl(
        uid: 'maria',
        firestorePhotoURL: 'https://example.com/maria.jpg',
        currentUid: 'tom',
        currentAuthPhotoURL: 'https://example.com/tom.jpg',
      ),
      'https://example.com/maria.jpg',
    );
  });

  test('falls back to Auth only for the signed-in user', () {
    expect(
      resolveMemberPhotoUrl(
        uid: 'tom',
        firestorePhotoURL: '',
        currentUid: 'tom',
        currentAuthPhotoURL: 'https://example.com/tom.jpg',
      ),
      'https://example.com/tom.jpg',
    );
    expect(
      resolveMemberPhotoUrl(
        uid: 'maria',
        firestorePhotoURL: '',
        currentUid: 'tom',
        currentAuthPhotoURL: 'https://example.com/tom.jpg',
      ),
      '',
    );
  });

  test('uses hub membership photo when Firestore is empty', () {
    expect(
      resolveMemberPhotoUrl(
        uid: 'maria',
        firestorePhotoURL: '',
        hubPhotoURL: 'https://example.com/hub-maria.jpg',
        currentUid: 'tom',
        currentAuthPhotoURL: 'https://example.com/tom.jpg',
      ),
      'https://example.com/hub-maria.jpg',
    );
  });

  test('prefers join-request photo over Firestore and hub', () {
    expect(
      resolveMemberPhotoUrl(
        uid: 'maria',
        requestPhotoURL: 'https://example.com/request-maria.jpg',
        firestorePhotoURL: 'https://example.com/users-maria.jpg',
        hubPhotoURL: 'https://example.com/hub-maria.jpg',
        currentUid: 'tom',
      ),
      'https://example.com/request-maria.jpg',
    );
  });

  test('ignores short or non-http photo values', () {
    expect(isUsablePhotoUrl(null), isFalse);
    expect(isUsablePhotoUrl(''), isFalse);
    expect(isUsablePhotoUrl('null'), isFalse);
    expect(isUsablePhotoUrl('abc'), isFalse);
    expect(isUsablePhotoUrl('https://lh3.googleusercontent.com/photo'), isTrue);
  });

  test('keeps the raw Auth / stored Google URL', () {
    const auth =
        'https://lh3.googleusercontent.com/a/ACg8ocMaria=s96-c';
    expect(
      resolveMemberPhotoUrl(
        uid: 'maria',
        firestorePhotoURL: auth,
        currentUid: 'tom',
      ),
      auth,
    );
  });

  test('memberInitial uses the first letter', () {
    expect(memberInitial('Maria'), 'M');
    expect(memberInitial('  tom'), 'T');
    expect(memberInitial(''), '?');
    expect(memberInitial(null), '?');
  });

  test('only writes a user profile update when Auth photo is new', () {
    expect(
      currentUserProfileUpdates(
        authPhotoURL: 'https://example.com/tom.jpg',
        authDisplayName: 'Tom',
        existing: {'photoURL': 'https://example.com/tom.jpg', 'displayName': 'Tom'},
      ),
      isNull,
    );
    expect(
      currentUserProfileUpdates(
        authPhotoURL: 'https://example.com/tom.jpg',
        authDisplayName: 'Tom',
        existing: {'displayName': 'Tom'},
      ),
      {'photoURL': 'https://example.com/tom.jpg'},
    );
    expect(
      currentUserProfileUpdates(
        authPhotoURL: 'https://example.com/tom.jpg',
        authDisplayName: 'Tom Hughes',
        existing: {},
      ),
      {
        'photoURL': 'https://example.com/tom.jpg',
        'displayName': 'Tom Hughes',
      },
    );
    expect(
      currentUserProfileUpdates(
        authPhotoURL: 'https://lh3.googleusercontent.com/a/ACg8ocTom=s96-c',
        authDisplayName: 'Tom',
        existing: {'displayName': 'Tom'},
      ),
      {'photoURL': 'https://lh3.googleusercontent.com/a/ACg8ocTom=s96-c'},
    );
  });

  test('rewrites a previously mangled durable URL back to Auth on login', () {
    expect(
      currentUserProfileUpdates(
        authPhotoURL: 'https://lh3.googleusercontent.com/a/ACg8ocMaria=s96-c',
        authDisplayName: 'Maria',
        existing: {
          'photoURL': 'https://lh3.googleusercontent.com/a/ACg8ocMaria=s128-c',
          'displayName': 'Maria',
        },
      ),
      {'photoURL': 'https://lh3.googleusercontent.com/a/ACg8ocMaria=s96-c'},
    );
  });

  test('hub member profile payload skips empty photos', () {
    expect(
      hubMemberProfilePayload(uid: 'maria', photoURL: '', displayName: ''),
      isEmpty,
    );
    expect(
      hubMemberProfilePayload(
        uid: 'maria',
        photoURL: 'https://lh3.googleusercontent.com/a/maria=s96-c',
        displayName: 'Maria',
      ),
      {
        'memberProfiles': {
          'maria': {
            'photoURL': 'https://lh3.googleusercontent.com/a/maria=s96-c',
            'displayName': 'Maria',
          },
        },
      },
    );
  });

  test('hubMemberProfilesPatch only writes missing or stale photos', () {
    expect(
      hubMemberProfilesPatch(
        photosByUid: {'maria': 'https://example.com/maria.jpg'},
        namesByUid: {'maria': 'Maria'},
        existingHubProfiles: {
          'maria': {
            'photoURL': 'https://example.com/maria.jpg',
            'displayName': 'Maria',
          },
        },
      ),
      isNull,
    );
    expect(
      hubMemberProfilesPatch(
        photosByUid: {'maria': 'https://example.com/maria.jpg'},
        namesByUid: {'maria': 'Maria'},
        existingHubProfiles: const {},
      ),
      {
        'memberProfiles': {
          'maria': {
            'photoURL': 'https://example.com/maria.jpg',
            'displayName': 'Maria',
          },
        },
      },
    );
    expect(
      hubMemberProfilesPatch(
        photosByUid: {'maria': ''},
        existingHubProfiles: {
          'maria': {'photoURL': 'https://example.com/old.jpg'},
        },
      ),
      isNull,
    );
    expect(
      hubMemberProfilesPatch(
        photosByUid: {
          'maria': 'https://lh3.googleusercontent.com/a/maria=s96-c',
        },
        existingHubProfiles: {
          'maria': {
            'photoURL': 'https://lh3.googleusercontent.com/a/maria=s128-c',
          },
        },
      ),
      {
        'memberProfiles': {
          'maria': {
            'photoURL': 'https://lh3.googleusercontent.com/a/maria=s96-c',
          },
        },
      },
    );
  });
}
