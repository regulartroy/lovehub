import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/event_import/schedule_export.dart';
import 'package:lovehub/models/friend_model.dart';

void main() {
  group('reconcile --person-store', () {
    test('defaults stay off so live routines are unchanged', () {
      final command = parseC2ReconcileArgs(['--hub', 'pobIb3qupVJudoQGMJjl']);
      expect(command.personStore, isFalse);
      expect(command.userId, isNull);
    });

    test('requires --user and routes writes under users/{uid}', () {
      expect(
        () => parseC2ReconcileArgs([
          '--hub',
          'pobIb3qupVJudoQGMJjl',
          '--person-store',
        ]),
        throwsA(isA<C2RotaArgsException>()),
      );
      final command = parseC2ReconcileArgs([
        '--hub',
        'pobIb3qupVJudoQGMJjl',
        '--person-store',
        '--user',
        's5vugp62CDMOuLfzVH1z5Prd7rY2',
      ]);
      expect(command.personStore, isTrue);
      expect(command.userId, 's5vugp62CDMOuLfzVH1z5Prd7rY2');
    });
  });

  group('import --person-store', () {
    test('defaults stay on the hub path', () {
      final command = parseImportCommand(['--hub', 'hub1', '--dry-run']);
      expect(command.personStore, isFalse);
      expect(command.userId, isNull);
      final write = firestoreRestWrite(
        projectId: 'lovehub-26107',
        hubId: 'hub1',
        event: ImportedEvent(
          docId: 'c2-rota:2026-12-06',
          source: 'c2-rota',
          externalId: '2026-12-06',
          summary: 'C2 — Electric Six',
          start: DateTime.utc(2026, 12, 6, 15),
          end: DateTime.utc(2026, 12, 6, 20),
          allDay: false,
          category: 'work',
          assignedTo: 'tom-uid',
        ),
        ownerId: 'tom-uid',
      );
      expect(
        write['update']['name'],
        'projects/lovehub-26107/databases/(default)/documents/sharedHubs/hub1/events/c2-rota:2026-12-06',
      );
    });

    test('writes and confirms under users/{uid}/events', () {
      final command = parseImportCommand([
        '--hub',
        'hub1',
        '--person-store',
        '--user',
        'tom-uid',
        '--dry-run',
      ]);
      expect(command.personStore, isTrue);
      expect(command.userId, 'tom-uid');
      final write = firestoreRestWrite(
        projectId: 'lovehub-26107',
        hubId: 'hub1',
        event: ImportedEvent(
          docId: 'c2-rota:2026-12-06',
          source: 'c2-rota',
          externalId: '2026-12-06',
          summary: 'C2 — Electric Six',
          start: DateTime.utc(2026, 12, 6, 15),
          end: DateTime.utc(2026, 12, 6, 20),
          allDay: false,
          category: 'work',
          assignedTo: 'tom-uid',
        ),
        ownerId: 'tom-uid',
        personStoreUserId: 'tom-uid',
      );
      expect(
        write['update']['name'],
        'projects/lovehub-26107/databases/(default)/documents/users/tom-uid/events/c2-rota:2026-12-06',
      );
      final confirm = firestoreRestConfirmWrite(
        projectId: 'lovehub-26107',
        hubId: 'hub1',
        target: parseConfirmTarget('c2-rota:2026-12-06'),
        personStoreUserId: 'tom-uid',
      );
      expect(
        confirm['update']['name'],
        'projects/lovehub-26107/databases/(default)/documents/users/tom-uid/events/c2-rota:2026-12-06',
      );
    });
  });

  group('export --person-store', () {
    test('defaults stay hub-only', () {
      final command = parseScheduleExportArgs(['--hub', 'hub1']);
      expect(command.personStore, isFalse);
      expect(command.userId, isNull);
    });

    test('requires --user and merges by sharing toggles', () {
      expect(
        () => parseScheduleExportArgs(['--hub', 'hub1', '--person-store']),
        throwsA(isA<ScheduleExportArgsException>()),
      );
      final command = parseScheduleExportArgs([
        '--hub',
        'hub1',
        '--person-store',
        '--user',
        'tom-uid',
      ]);
      expect(command.personStore, isTrue);
      expect(command.userId, 'tom-uid');

      final start = DateTime.utc(2026, 12, 6, 15);
      StoredExportEvent ev({
        required String id,
        required String summary,
        String category = 'work',
        String assignedTo = 'tom-uid',
        String? ownerId,
        String? source,
        String? externalId,
        bool previewDeleted = false,
      }) {
        return StoredExportEvent(
          id: id,
          summary: summary,
          start: start,
          end: start.add(const Duration(hours: 5)),
          allDay: false,
          category: category,
          assignedTo: assignedTo,
          ownerId: ownerId,
          source: source,
          externalId: externalId,
          previewDeleted: previewDeleted,
        );
      }

      const tom = 'tom-uid';
      const paddy = 'paddy-uid';
      final friendship = Friendship(
        id: friendshipIdFor(tom, paddy),
        members: [paddy, tom],
        sharing: const {
          tom: FriendSharing(shareWork: true),
          paddy: FriendSharing(shareWork: true),
        },
      );
      final merged = personStoreExportEvents(
        viewerUid: tom,
        memberUids: [tom, paddy],
        friendshipsByOtherUid: {paddy: friendship},
        liveHubEvents: [
          ev(
            id: 'renoir:2026-11-28-date-day',
            summary: 'Date day',
            category: 'personal',
            assignedTo: 'shared',
            source: 'renoir',
            externalId: '2026-11-28-date-day',
          ),
        ],
        previewSharedEvents: const [],
        eventsByOwner: {
          tom: [
            ev(
              id: 'c2-rota:2026-12-06',
              summary: 'C2 — Electric Six',
              ownerId: tom,
              source: 'c2-rota',
              externalId: '2026-12-06',
            ),
            ev(
              id: 'tennis',
              summary: 'Toby Tennis',
              category: 'general',
              ownerId: tom,
            ),
          ],
          paddy: [
            ev(
              id: 'the-lab:1',
              summary: 'Shift at The Lab',
              assignedTo: paddy,
              ownerId: paddy,
            ),
          ],
        },
      );
      expect(
        merged.map((e) => e.summary),
        unorderedEquals(['C2 — Electric Six', 'Shift at The Lab', 'Date day']),
      );
    });
  });
}
