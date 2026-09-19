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

  test('ignores short or non-http photo values', () {
    expect(isUsablePhotoUrl(null), isFalse);
    expect(isUsablePhotoUrl(''), isFalse);
    expect(isUsablePhotoUrl('null'), isFalse);
    expect(isUsablePhotoUrl('abc'), isFalse);
    expect(isUsablePhotoUrl('https://lh3.googleusercontent.com/photo'), isTrue);
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
}
