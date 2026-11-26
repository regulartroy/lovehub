import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/models/friend_model.dart';
import 'package:lovehub/services/event_store.dart';

EventModel event({
  required String id,
  String category = 'general',
  String assignedTo = 'shared',
  String? ownerId,
  String? source,
  String? externalId,
  bool previewDeleted = false,
  String summary = 'Event',
}) {
  final start = DateTime.utc(2026, 12, 6, 15);
  return EventModel(
    id: id,
    summary: summary,
    start: start,
    end: start.add(const Duration(hours: 5)),
    category: category,
    assignedTo: assignedTo,
    ownerId: ownerId,
    source: source,
    externalId: externalId,
    previewDeleted: previewDeleted,
  );
}

Friendship friendship({
  required String a,
  required String b,
  FriendSharing? shareA,
  FriendSharing? shareB,
}) {
  return Friendship(
    id: friendshipIdFor(a, b),
    members: [a, b]..sort(),
    sharing: {
      a: shareA ?? const FriendSharing(),
      b: shareB ?? const FriendSharing(),
    },
  );
}

void main() {
  const tom = 'tom-uid';
  const maria = 'maria-uid';
  const paddy = 'paddy-uid';
  const dan = 'dan-uid';

  group('category to share toggle', () {
    test('maps work, personal aliases, and birthdays', () {
      expect(shareFieldForCategory('work'), 'shareWork');
      expect(shareFieldForCategory('general'), 'sharePersonal');
      expect(shareFieldForCategory('personal'), 'sharePersonal');
      expect(shareFieldForCategory('meal'), 'sharePersonal');
      expect(shareFieldForCategory('birthday'), 'shareBirthdays');
    });

    test('categoriesSharedBy follows the three toggles', () {
      expect(categoriesSharedBy(const FriendSharing()), isEmpty);
      expect(categoriesSharedBy(const FriendSharing(shareWork: true)), {
        'work',
      });
      expect(
        categoriesSharedBy(const FriendSharing(sharePersonal: true)),
        unorderedEquals(['general', 'personal', 'meal']),
      );
      expect(categoriesSharedBy(const FriendSharing(shareBirthdays: true)), {
        'birthday',
      });
    });
  });

  group('hub visibility categories', () {
    test(
      'Tom in Burroni sees all his categories when he shares everything with Maria',
      () {
        final friends = {
          maria: friendship(
            a: tom,
            b: maria,
            shareA: const FriendSharing(
              shareWork: true,
              sharePersonal: true,
              shareBirthdays: true,
            ),
            shareB: const FriendSharing(
              shareWork: true,
              sharePersonal: true,
              shareBirthdays: true,
            ),
          ),
        };
        expect(
          categoriesSharedWithAnyMember(
            viewerUid: tom,
            memberUids: [tom, maria],
            friendshipsByOtherUid: friends,
          ),
          unorderedEquals(['work', 'general', 'personal', 'meal', 'birthday']),
        );
        expect(
          categoriesTheyShareWithMe(
            viewerUid: tom,
            otherUid: maria,
            friendship: friends[maria],
          ),
          unorderedEquals(['work', 'general', 'personal', 'meal', 'birthday']),
        );
      },
    );

    test('Tom and Paddy only share work', () {
      final friends = {
        paddy: friendship(
          a: tom,
          b: paddy,
          shareA: const FriendSharing(shareWork: true),
          shareB: const FriendSharing(shareWork: true),
        ),
      };
      expect(
        categoriesSharedWithAnyMember(
          viewerUid: tom,
          memberUids: [tom, paddy],
          friendshipsByOtherUid: friends,
        ),
        {'work'},
      );
      expect(
        categoriesTheyShareWithMe(
          viewerUid: tom,
          otherUid: paddy,
          friendship: friends[paddy],
        ),
        {'work'},
      );
    });

    test('missing friendship shares nothing', () {
      expect(
        categoriesSharedWithAnyMember(
          viewerUid: tom,
          memberUids: [tom, dan],
          friendshipsByOtherUid: const {},
        ),
        isEmpty,
      );
      expect(
        categoriesTheyShareWithMe(
          viewerUid: tom,
          otherUid: dan,
          friendship: null,
        ),
        isEmpty,
      );
    });
  });

  group('write routing', () {
    test('hub mode always writes to live hub events', () {
      expect(
        eventWriteTarget(
          mode: EventStoreMode.hub,
          category: 'work',
          assignedTo: tom,
        ),
        EventWriteTarget.hubEvents,
      );
      expect(
        eventWriteTarget(
          mode: EventStoreMode.hub,
          category: 'meal',
          assignedTo: 'shared',
        ),
        EventWriteTarget.hubEvents,
      );
    });

    test('person mode routes owned events to the person store', () {
      expect(
        eventWriteTarget(
          mode: EventStoreMode.person,
          category: 'work',
          assignedTo: tom,
        ),
        EventWriteTarget.personEvents,
      );
      expect(
        eventWriteTarget(
          mode: EventStoreMode.person,
          category: 'general',
          assignedTo: maria,
        ),
        EventWriteTarget.personEvents,
      );
    });

    test(
      'person mode routes joint events to the preview shadow, never the live hub',
      () {
        expect(
          eventWriteTarget(
            mode: EventStoreMode.person,
            category: 'personal',
            assignedTo: 'shared',
          ),
          EventWriteTarget.previewSharedEvents,
        );
        expect(
          eventWriteTarget(
            mode: EventStoreMode.person,
            category: 'meal',
            assignedTo: 'shared',
          ),
          EventWriteTarget.previewSharedEvents,
        );
        expect(
          eventWriteTarget(
            mode: EventStoreMode.person,
            category: 'meal',
            assignedTo: tom,
          ),
          EventWriteTarget.previewSharedEvents,
        );
      },
    );

    test('person event owner falls back to the viewer', () {
      expect(personEventOwnerUid(ownerId: tom, viewerUid: maria), tom);
      expect(personEventOwnerUid(ownerId: null, viewerUid: tom), tom);
    });
  });

  group('merge and dedupe', () {
    test(
      'person events win over leftover hub copies of the same c2-rota id',
      () {
        final live = event(
          id: 'c2-rota:2026-12-06',
          category: 'work',
          assignedTo: 'shared',
          source: 'c2-rota',
          externalId: '2026-12-06',
          summary: 'C2 — Electric Six (stale hub copy)',
        );
        final person = event(
          id: 'c2-rota:2026-12-06',
          category: 'work',
          assignedTo: tom,
          ownerId: tom,
          source: 'c2-rota',
          externalId: '2026-12-06',
          summary: 'C2 — Electric Six',
        );
        final merged = mergeVisibleEvents(
          liveShared: [live],
          previewShared: const [],
          personEvents: [person],
        );
        expect(merged, hasLength(1));
        expect(merged.single.summary, 'C2 — Electric Six');
        expect(merged.single.assignedTo, tom);
      },
    );

    test(
      'preview shadow overrides a live shared event and tombstones hide it',
      () {
        final live = event(
          id: 'renoir:2026-11-28-date-day',
          category: 'personal',
          assignedTo: 'shared',
          source: 'renoir',
          externalId: '2026-11-28-date-day',
          summary: 'Date day',
        );
        final edited = event(
          id: 'renoir:2026-11-28-date-day',
          category: 'personal',
          assignedTo: 'shared',
          source: 'renoir',
          externalId: '2026-11-28-date-day',
          summary: 'Date day (preview edit)',
        );
        expect(
          mergeVisibleEvents(
            liveShared: [live],
            previewShared: [edited],
            personEvents: const [],
          ).single.summary,
          'Date day (preview edit)',
        );
        final hidden = mergeVisibleEvents(
          liveShared: [live],
          previewShared: [
            event(
              id: live.id,
              category: live.category,
              assignedTo: live.assignedTo,
              source: live.source,
              externalId: live.externalId,
              previewDeleted: true,
            ),
          ],
          personEvents: const [],
        );
        expect(hidden, isEmpty);
      },
    );

    test('ignores non-joint leftover hub events in the live shared list', () {
      final workOnHub = event(
        id: 'work-1',
        category: 'work',
        assignedTo: tom,
        ownerId: tom,
        summary: 'Should not appear from live hub',
      );
      final person = event(
        id: 'work-1',
        category: 'work',
        assignedTo: tom,
        ownerId: tom,
        summary: 'Person store copy',
      );
      final merged = mergeVisibleEvents(
        liveShared: [workOnHub],
        previewShared: const [],
        personEvents: [person],
      );
      expect(merged, hasLength(1));
      expect(merged.single.summary, 'Person store copy');
    });

    test('two owners with the same raw id stay distinct', () {
      final toms = event(
        id: 'same',
        category: 'general',
        assignedTo: tom,
        ownerId: tom,
        summary: "Tom's",
      );
      final paddys = event(
        id: 'same',
        category: 'general',
        assignedTo: paddy,
        ownerId: paddy,
        summary: "Paddy's",
      );
      final merged = mergeVisibleEvents(
        liveShared: const [],
        previewShared: const [],
        personEvents: [toms, paddys],
      );
      expect(
        merged.map((e) => e.summary),
        unorderedEquals(["Tom's", "Paddy's"]),
      );
    });
  });

  group('compile-time default', () {
    test('live builds without the dart-define stay on the hub store', () {
      expect(compileTimeEventStoreMode, EventStoreMode.hub);
      expect(usePersonEventStore, isFalse);
      expect(eventStoreModeFromName('person'), EventStoreMode.person);
      expect(eventStoreModeFromName('hub'), EventStoreMode.hub);
      expect(eventStoreModeFromName(''), EventStoreMode.hub);
    });
  });

  test('whereInCategories sorts and does not invent an unfiltered query', () {
    expect(whereInCategories({}), isEmpty);
    expect(whereInCategories({'work', 'general'}), ['general', 'work']);
  });
}
