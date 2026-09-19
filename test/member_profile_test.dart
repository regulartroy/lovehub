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

  test('hardens Google profile URLs with size suffix and sz query', () {
    expect(
      hardenPhotoUrl(
        'https://lh3.googleusercontent.com/a/ACg8ocExample=s96-c',
        size: 128,
      ),
      'https://lh3.googleusercontent.com/a/ACg8ocExample=s128-c?sz=128',
    );
    expect(
      hardenPhotoUrl(
        'https://lh3.googleusercontent.com/a/ACg8ocExample',
        size: 96,
      ),
      'https://lh3.googleusercontent.com/a/ACg8ocExample=s96-c?sz=96',
    );
    expect(
      hardenPhotoUrl('https://example.com/maria.jpg', size: 128),
      'https://example.com/maria.jpg',
    );
    expect(hardenPhotoUrl(''), '');
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
  });

  test('refresh message tells Tom when a partner still has no photo', () {
    expect(
      hubPhotoRefreshMessage(
        const HubPhotoRefreshResult(
          updated: 0,
          unchanged: 2,
          missingUids: [],
        ),
      ),
      'Member photos are already up to date.',
    );
    expect(
      hubPhotoRefreshMessage(
        const HubPhotoRefreshResult(
          updated: 1,
          unchanged: 1,
          missingUids: [],
        ),
      ),
      'Updated 1 member photo.',
    );
    expect(
      hubPhotoRefreshMessage(
        const HubPhotoRefreshResult(
          updated: 1,
          unchanged: 0,
          missingUids: ['maria'],
        ),
      ),
      'Updated 1. 1 still missing — they need to open LoveHub once.',
    );
  });
}
