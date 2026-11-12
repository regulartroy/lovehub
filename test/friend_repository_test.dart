import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/friend_model.dart';
import 'package:lovehub/repositories/friend_repository.dart';

void main() {
  group('FriendModel', () {
    test('defaults all share toggles to off', () {
      final friend = FriendModel.fromMap({}, id: 'abc');
      expect(friend.shareWork, isFalse);
      expect(friend.sharePersonal, isFalse);
      expect(friend.shareBirthdays, isFalse);
      expect(friend.label, 'Friend');
    });

    test('reads each share toggle independently', () {
      final friend = FriendModel.fromMap({
        'displayName': 'Paddy',
        'email': 'paddy@example.com',
        'shareWork': true,
        'sharePersonal': false,
        'shareBirthdays': true,
      }, id: 'paddy');
      expect(friend.shareWork, isTrue);
      expect(friend.sharePersonal, isFalse);
      expect(friend.shareBirthdays, isTrue);
      expect(friend.label, 'Paddy');
    });
  });

  group('FriendRepository', () {
    late FakeFirebaseFirestore db;
    late FriendRepository repo;

    const tom = 'tom-uid';
    const paddy = 'paddy-uid';

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FriendRepository(firestore: db);
      await db.collection('users').doc(tom).set({
        'email': 'tom@example.com',
        'displayName': 'Tom Burch',
      });
      await db.collection('users').doc(paddy).set({
        'email': 'paddy@example.com',
        'displayName': 'Paddy',
        'photoURL': 'https://example.com/p.png',
      });
    });

    test('adds a friend by email with all toggles off', () async {
      final friend = await repo.addFriend(
        ownerUid: tom,
        query: 'paddy@example.com',
        ownerEmail: 'tom@example.com',
      );
      expect(friend.id, paddy);
      expect(friend.displayName, 'Paddy');
      expect(friend.shareWork, isFalse);
      expect(friend.sharePersonal, isFalse);
      expect(friend.shareBirthdays, isFalse);

      final snap = await db
          .collection('users')
          .doc(tom)
          .collection('friends')
          .doc(paddy)
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['shareWork'], isFalse);
      expect(snap.data()!['sharePersonal'], isFalse);
      expect(snap.data()!['shareBirthdays'], isFalse);
    });

    test('adds a friend by user id', () async {
      final friend = await repo.addFriend(ownerUid: tom, query: paddy);
      expect(friend.id, paddy);
      expect(friend.email, 'paddy@example.com');
    });

    test('rejects adding yourself by email or id', () async {
      expect(
        () => repo.addFriend(
          ownerUid: tom,
          query: 'tom@example.com',
          ownerEmail: 'tom@example.com',
        ),
        throwsA(isA<FriendLookupException>()),
      );
      expect(
        () => repo.addFriend(ownerUid: tom, query: tom),
        throwsA(isA<FriendLookupException>()),
      );
    });

    test('rejects a missing user and a duplicate add', () async {
      expect(
        () => repo.addFriend(ownerUid: tom, query: 'nobody@example.com'),
        throwsA(isA<FriendLookupException>()),
      );
      await repo.addFriend(ownerUid: tom, query: 'paddy@example.com');
      expect(
        () => repo.addFriend(ownerUid: tom, query: paddy),
        throwsA(isA<FriendLookupException>()),
      );
    });

    test('updates one share toggle without changing the others', () async {
      await repo.addFriend(ownerUid: tom, query: paddy);
      await repo.setShare(
        ownerUid: tom,
        friendUid: paddy,
        kind: FriendShareKind.work,
        value: true,
      );
      final snap = await db
          .collection('users')
          .doc(tom)
          .collection('friends')
          .doc(paddy)
          .get();
      expect(snap.data()!['shareWork'], isTrue);
      expect(snap.data()!['sharePersonal'], isFalse);
      expect(snap.data()!['shareBirthdays'], isFalse);
    });

    test('removes a friend', () async {
      await repo.addFriend(ownerUid: tom, query: paddy);
      await repo.removeFriend(ownerUid: tom, friendUid: paddy);
      final snap = await db
          .collection('users')
          .doc(tom)
          .collection('friends')
          .doc(paddy)
          .get();
      expect(snap.exists, isFalse);
    });
  });
}
