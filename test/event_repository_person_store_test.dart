import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/repositories/event_repository.dart';
import 'package:lovehub/services/event_store.dart';
import 'package:lovehub/services/hub_collection.dart';

void main() {
  const tom = 'tom-uid';
  const maria = 'maria-uid';
  const paddy = 'paddy-uid';
  const burroni = 'burroni-hub';
  const paddyHub = 'paddy-hub';

  late FakeFirebaseFirestore db;
  late EventRepository personRepo;
  late EventRepository hubRepo;

  EventModel model({
    required String id,
    required String summary,
    String category = 'work',
    String assignedTo = tom,
    String? ownerId,
    String? source,
    String? externalId,
    DateTime? start,
  }) {
    final when = start ?? DateTime.utc(2026, 12, 6, 15);
    return EventModel(
      id: id,
      summary: summary,
      start: when,
      end: when.add(const Duration(hours: 5)),
      category: category,
      assignedTo: assignedTo,
      ownerId: ownerId ?? tom,
      source: source,
      externalId: externalId,
    );
  }

  Future<void> seedFriendship({
    required String a,
    required String b,
    required Map<String, bool> shareA,
    required Map<String, bool> shareB,
  }) async {
    final members = [a, b]..sort();
    await db.collection('friends').doc('${members[0]}_${members[1]}').set({
      'members': members,
      'sharing': {
        a: {
          'shareWork': shareA['work'] == true,
          'sharePersonal': shareA['personal'] == true,
          'shareBirthdays': shareA['birthdays'] == true,
        },
        b: {
          'shareWork': shareB['work'] == true,
          'sharePersonal': shareB['personal'] == true,
          'shareBirthdays': shareB['birthdays'] == true,
        },
      },
    });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    personRepo = EventRepository(firestore: db, mode: EventStoreMode.person);
    hubRepo = EventRepository(firestore: db, mode: EventStoreMode.hub);

    await db.collection(kHubsCollection).doc(burroni).set({
      'name': 'Burroni Hub',
      'members': [tom, maria],
    });
    await db.collection(kHubsCollection).doc(paddyHub).set({
      'name': 'Tom and Paddy',
      'members': [tom, paddy],
    });
    await seedFriendship(
      a: tom,
      b: maria,
      shareA: {'work': true, 'personal': true, 'birthdays': true},
      shareB: {'work': true, 'personal': true, 'birthdays': true},
    );
    await seedFriendship(
      a: tom,
      b: paddy,
      shareA: {'work': true, 'personal': false, 'birthdays': false},
      shareB: {'work': true, 'personal': false, 'birthdays': false},
    );
  });

  Future<void> putPerson(EventModel e) {
    return db
        .collection('users')
        .doc(e.ownerId ?? tom)
        .collection('events')
        .doc(e.id)
        .set(e.toMap());
  }

  test('hub-mode writes stay on the live hub collection', () async {
    await hubRepo.addEvent(burroni, {
      'summary': 'Live meal',
      'category': 'meal',
      'assignedTo': 'shared',
      'start': Timestamp.fromDate(DateTime.utc(2026, 11, 28, 19)),
      'end': Timestamp.fromDate(DateTime.utc(2026, 11, 28, 20)),
      'allDay': false,
    });
    final live = await db
        .collection(kHubsCollection)
        .doc(burroni)
        .collection('events')
        .get();
    expect(live.docs, hasLength(1));
    expect(live.docs.single.data()['summary'], 'Live meal');
  });

  test(
    'person-mode never writes joint events to live sharedHubs events',
    () async {
      await personRepo.addEvent(
        burroni,
        {
          'summary': 'Preview meal',
          'category': 'meal',
          'assignedTo': 'shared',
          'start': Timestamp.fromDate(DateTime.utc(2026, 11, 28, 19)),
          'end': Timestamp.fromDate(DateTime.utc(2026, 11, 28, 20)),
          'allDay': false,
        },
        hint: const EventWriteHint(
          category: 'meal',
          assignedTo: 'shared',
          viewerUid: tom,
        ),
      );
      final live = await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection('events')
          .get();
      expect(live.docs, isEmpty);
      final preview = await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection(kPreviewSharedEventsCollection)
          .get();
      expect(preview.docs, hasLength(1));
      expect(preview.docs.single.data()['summary'], 'Preview meal');
    },
  );

  test('person-mode owned writes go to users/{uid}/events', () async {
    await personRepo.batchAddEvents(burroni, [
      model(id: '', summary: 'C2 — Electric Six', ownerId: tom),
    ], viewerUid: tom);
    final docs = await db
        .collection('users')
        .doc(tom)
        .collection('events')
        .get();
    expect(docs.docs, hasLength(1));
    expect(docs.docs.single.data()['summary'], 'C2 — Electric Six');
    expect(docs.docs.single.data()['ownerId'], tom);
    final live = await db
        .collection(kHubsCollection)
        .doc(burroni)
        .collection('events')
        .get();
    expect(live.docs, isEmpty);
  });

  test(
    'deleting a live shared event in preview only writes a tombstone',
    () async {
      await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection('events')
          .doc('renoir:2026-11-28-date-day')
          .set({
            'summary': 'Date day',
            'category': 'personal',
            'assignedTo': 'shared',
            'source': 'renoir',
            'externalId': '2026-11-28-date-day',
            'start': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'end': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'allDay': true,
            'ownerId': tom,
          });
      await personRepo.deleteEvent(
        burroni,
        'renoir:2026-11-28-date-day',
        hint: const EventWriteHint(
          category: 'personal',
          assignedTo: 'shared',
          viewerUid: tom,
          ownerId: tom,
        ),
      );
      final live = await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection('events')
          .doc('renoir:2026-11-28-date-day')
          .get();
      expect(live.exists, isTrue);
      expect(live.data()?['summary'], 'Date day');
      final tombstone = await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection(kPreviewSharedEventsCollection)
          .doc('renoir:2026-11-28-date-day')
          .get();
      expect(tombstone.data()?[kPreviewDeletedField], isTrue);
    },
  );

  test(
    'person-mode refuses a write without a hint so live hub events stay put',
    () async {
      expect(
        () => personRepo.updateEvent(burroni, 'x', {'summary': 'nope'}),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'Burroni merge shows Tom and Maria events plus a hub date day',
    () async {
      await putPerson(
        model(
          id: 'c2-rota:2026-12-06',
          summary: 'C2 — Electric Six',
          source: 'c2-rota',
          externalId: '2026-12-06',
        ),
      );
      await putPerson(
        model(
          id: 'tennis',
          summary: 'Toby Tennis',
          category: 'general',
          assignedTo: tom,
        ),
      );
      await putPerson(
        model(
          id: 'maria-thing',
          summary: "Maria's appointment",
          category: 'general',
          assignedTo: maria,
          ownerId: tom,
        ),
      );
      await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection('events')
          .doc('renoir:2026-11-28-date-day')
          .set({
            'summary': 'Date day',
            'category': 'personal',
            'assignedTo': 'shared',
            'source': 'renoir',
            'externalId': '2026-11-28-date-day',
            'start': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'end': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'allDay': true,
            'ownerId': tom,
          });

      final forTom = await personRepo
          .streamEvents(burroni, viewerUid: tom)
          .firstWhere((events) => events.length >= 4);
      final forMaria = await personRepo
          .streamEvents(burroni, viewerUid: maria)
          .firstWhere((events) => events.length >= 4);
      expect(
        forTom.map((e) => e.summary),
        unorderedEquals([
          'C2 — Electric Six',
          'Toby Tennis',
          "Maria's appointment",
          'Date day',
        ]),
      );
      expect(
        forMaria.map((e) => e.summary).toSet(),
        forTom.map((e) => e.summary).toSet(),
      );
    },
  );

  test(
    'Paddy hub shows shared work but not personal events or Burroni date day',
    () async {
      await putPerson(
        model(
          id: 'c2-rota:2026-12-06',
          summary: 'C2 — Electric Six',
          source: 'c2-rota',
          externalId: '2026-12-06',
        ),
      );
      await putPerson(
        model(
          id: 'tennis',
          summary: 'Toby Tennis',
          category: 'general',
          assignedTo: tom,
        ),
      );
      await putPerson(
        model(
          id: 'the-lab:2026-11-22',
          summary: 'Shift at The Lab',
          category: 'work',
          assignedTo: paddy,
          ownerId: paddy,
          source: 'the-lab',
          externalId: '2026-11-22',
        ),
      );
      await putPerson(
        model(
          id: 'gig',
          summary: 'my gig',
          category: 'general',
          assignedTo: paddy,
          ownerId: paddy,
        ),
      );
      await db
          .collection(kHubsCollection)
          .doc(burroni)
          .collection('events')
          .doc('renoir:2026-11-28-date-day')
          .set({
            'summary': 'Date day',
            'category': 'personal',
            'assignedTo': 'shared',
            'source': 'renoir',
            'externalId': '2026-11-28-date-day',
            'start': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'end': Timestamp.fromDate(DateTime.utc(2026, 11, 28)),
            'allDay': true,
          });

      final forTom = await personRepo
          .streamEvents(paddyHub, viewerUid: tom)
          .firstWhere((events) => events.length >= 2);
      expect(
        forTom.map((e) => e.summary),
        unorderedEquals(['C2 — Electric Six', 'Shift at The Lab']),
      );
      expect(forTom.any((e) => e.summary == 'Date day'), isFalse);
      expect(forTom.any((e) => e.summary == 'Toby Tennis'), isFalse);
      expect(forTom.any((e) => e.summary == 'my gig'), isFalse);
    },
  );
}
