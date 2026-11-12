import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/friend_model.dart';
import 'package:lovehub/repositories/friend_repository.dart';

void main() {
  group('Friendship', () {
    test('defaults sharing to off and names the other person', () {
      final friendship = Friendship.fromMap({
        'members': ['tom-uid', 'paddy-uid'],
        'memberProfiles': {
          'tom-uid': {'displayName': 'Tom Burch', 'email': 'tom@example.com'},
          'paddy-uid': {'displayName': 'Paddy', 'email': 'paddy@example.com'},
        },
      }, id: 'paddy-uid_tom-uid');
      expect(friendship.otherUid('tom-uid'), 'paddy-uid');
      expect(friendship.otherProfile('tom-uid').label, 'Paddy');
      expect(friendship.mySharing('tom-uid').shareWork, isFalse);
      expect(friendship.mySharing('tom-uid').sharePersonal, isFalse);
      expect(friendship.mySharing('tom-uid').shareBirthdays, isFalse);
    });

    test('reads each person\'s share toggles independently', () {
      final friendship = Friendship.fromMap({
        'members': ['tom-uid', 'maria-uid'],
        'sharing': {
          'tom-uid': {
            'shareWork': true,
            'sharePersonal': true,
            'shareBirthdays': false,
          },
          'maria-uid': {
            'shareWork': true,
            'sharePersonal': false,
            'shareBirthdays': true,
          },
        },
      }, id: 'maria-uid_tom-uid');
      expect(friendship.mySharing('tom-uid').shareWork, isTrue);
      expect(friendship.mySharing('tom-uid').sharePersonal, isTrue);
      expect(friendship.mySharing('tom-uid').shareBirthdays, isFalse);
      expect(friendship.mySharing('maria-uid').sharePersonal, isFalse);
      expect(friendship.mySharing('maria-uid').shareBirthdays, isTrue);
    });

    test('builds a stable mutual friendship id', () {
      expect(friendshipIdFor('s5vu', '5ok7'), friendshipIdFor('5ok7', 's5vu'));
      expect(friendshipIdFor('s5vu', '5ok7'), '5ok7_s5vu');
    });
  });

  group('FriendRepository', () {
    late FakeFirebaseFirestore db;
    late FriendRepository repo;

    const tom = 'tom-uid';
    const paddy = 'paddy-uid';
    const maria = 'maria-uid';

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
      await db.collection('users').doc(maria).set({
        'email': 'maria@example.com',
        'displayName': 'Maria',
      });
    });

    test('adds a mutual friendship by email with both shares off', () async {
      final friendship = await repo.addFriend(
        ownerUid: tom,
        query: 'paddy@example.com',
        ownerEmail: 'tom@example.com',
        ownerDisplayName: 'Tom Burch',
      );
      expect(friendship.id, friendshipIdFor(tom, paddy));
      expect(friendship.members, [paddy, tom]..sort());
      expect(friendship.otherProfile(tom).label, 'Paddy');

      final snap = await db.collection('friends').doc(friendship.id).get();
      expect(snap.exists, isTrue);
      final sharing = snap.data()!['sharing'] as Map;
      expect(sharing[tom]['shareWork'], isFalse);
      expect(sharing[tom]['sharePersonal'], isFalse);
      expect(sharing[tom]['shareBirthdays'], isFalse);
      expect(sharing[paddy]['shareWork'], isFalse);
    });

    test('adds a friend by user id', () async {
      final friendship = await repo.addFriend(ownerUid: tom, query: paddy);
      expect(friendship.otherUid(tom), paddy);
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

    test(
      'updates one person\'s toggle without changing the other\'s',
      () async {
        final friendship = await repo.addFriend(ownerUid: tom, query: paddy);
        await repo.setShare(
          friendshipId: friendship.id,
          ownerUid: tom,
          kind: FriendShareKind.work,
          value: true,
        );
        final snap = await db.collection('friends').doc(friendship.id).get();
        final sharing = snap.data()!['sharing'] as Map;
        expect(sharing[tom]['shareWork'], isTrue);
        expect(sharing[tom]['sharePersonal'], isFalse);
        expect(sharing[paddy]['shareWork'], isFalse);
      },
    );

    test('watch lists only friendships that include the user', () async {
      await repo.addFriend(ownerUid: tom, query: paddy);
      await repo.addFriend(ownerUid: tom, query: maria);
      await repo.addFriend(ownerUid: paddy, query: maria);

      final toms = await repo.watch(tom).first;
      expect(toms.map((f) => f.otherUid(tom)), containsAll([paddy, maria]));
      expect(toms, hasLength(2));

      final paddys = await repo.watch(paddy).first;
      expect(paddys, hasLength(2));
    });

    test('removes a mutual friendship', () async {
      final friendship = await repo.addFriend(ownerUid: tom, query: paddy);
      await repo.removeFriend(friendship.id);
      final snap = await db.collection('friends').doc(friendship.id).get();
      expect(snap.exists, isFalse);
    });
    test('suggests hub co-members who are not already friends', () async {
      await db.collection('users').doc(tom).set({
        'email': 'tom@example.com',
        'displayName': 'Tom Burch',
        'joinedHubs': {
          'burroni': {'name': 'Burroni Hub', 'role': 'admin'},
          'concorde': {'name': 'Concorde 2', 'role': 'admin'},
        },
      }, SetOptions(merge: true));
      await db.collection('hubs').doc('burroni').set({
        'name': 'Burroni Hub',
        'members': [tom, maria],
        'memberProfiles': {
          tom: {'displayName': 'Tom Burch'},
          maria: {'displayName': 'Maria', 'email': 'maria@example.com'},
        },
      });
      await db.collection('hubs').doc('concorde').set({
        'name': 'Concorde 2',
        'members': [tom, 'dan-uid'],
        'memberProfiles': {
          tom: {'displayName': 'Tom Burch'},
          'dan-uid': {'displayName': 'Dan Brown'},
        },
      });
      await db.collection('users').doc('dan-uid').set({
        'email': 'dan@example.com',
        'displayName': 'Dan Brown',
      });
      await repo.addFriend(ownerUid: tom, query: maria);

      final suggestions = await repo.suggestionsFromExistingHubs(
        ownerUid: tom,
        alreadyFriendUids: {maria},
      );
      expect(suggestions, hasLength(1));
      expect(suggestions.first.uid, 'dan-uid');
      expect(suggestions.first.label, 'Dan Brown');
      expect(suggestions.first.sharedHubNames, ['Concorde 2']);
    });
  });
}
