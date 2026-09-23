import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/repositories/event_repository.dart';

void main() {
  const sample = {
    'source': 'c2-rota',
    'externalId': '2026-09-20',
    'summary': 'C2 Show — Artist',
    'start': '2026-09-20T15:00:00+01:00',
    'end': '2026-09-20T23:30:00+01:00',
    'allDay': false,
    'category': 'work',
    'assignedTo': 'tom',
    'notes': 'call time 14:30',
  };

  test('parses the v1 payload and keeps notes off the summary', () {
    final event = parseEventImport(sample).single;

    expect(event.source, 'c2-rota');
    expect(event.externalId, '2026-09-20');
    expect(event.docId, 'c2-rota:2026-09-20');
    expect(event.summary, 'C2 Show — Artist');
    expect(event.summary.contains('call time'), isFalse);
    expect(event.notes, 'call time 14:30');
    expect(event.category, 'work');
    expect(event.assignedTo, 'tom');
    expect(event.allDay, isFalse);
    expect(event.start, DateTime.utc(2026, 9, 20, 14));
    expect(event.end, DateTime.utc(2026, 9, 20, 22, 30));
    expect(event.start.isUtc, isTrue);
  });

  test('doc id is stable across a second parse', () {
    final first = parseEventImport(sample).single.docId;
    final second = parseEventImport(
      jsonDecode(jsonEncode(sample)),
    ).single.docId;
    expect(first, second);
    expect(eventImportDocId('c2-rota', '2026-09-20'), first);
  });

  test('accepts an array, an envelope, and other sources', () {
    final array = parseEventImport([
      sample,
      {
        'source': 'venue-diary',
        'externalId': 'abc',
        'summary': 'Extra',
        'start': '2026-09-21T18:00:00Z',
      },
    ]);
    expect(array.map((event) => event.source), ['c2-rota', 'venue-diary']);
    expect(array.last.end, array.last.start);

    final envelope = parseEventImport({
      'events': [
        {
          'source': 'seb',
          'externalId': '1',
          'summary': 'SEB',
          'start': '2026-10-03',
        },
        {
          'source': 'rot90s',
          'externalId': '1',
          'summary': 'ROT90s',
          'start': '2026-11-14T20:00:00+00:00',
        },
      ],
    });
    expect(envelope.map((event) => event.source), ['seb', 'rot90s']);
    expect(envelope.first.allDay, isFalse);
    expect(envelope.first.start, DateTime.utc(2026, 10, 3));
    expect(knownEventImportSources, containsAll(['c2-rota', 'seb', 'rot90s']));
  });

  test('example file matches the Roger schema', () {
    final payload = jsonDecode(
      File('tool/event_import_example.json').readAsStringSync(),
    );
    final events = parseEventImport(payload);
    expect(events.map((event) => event.docId), [
      'c2-rota:2026-09-20',
      'seb:2026-10-03-london',
      'rot90s:2026-11-14',
    ]);
    expect(events.first.notes, 'optional');
    expect(events.first.status, 'tentative');
    expect(events[1].notes, isNull);
    expect(events[1].status, isNull);
    expect(events.every((event) => event.category == 'work'), isTrue);
  });

  test('rejects a missing id, a naive time, and an end before start', () {
    expect(
      () => parseEventImport({...sample, 'externalId': '  '}),
      throwsA(
        isA<EventImportException>().having(
          (error) => error.message,
          'message',
          contains('externalId'),
        ),
      ),
    );
    expect(
      () => parseEventImport({...sample, 'start': '2026-09-20T15:00:00'}),
      throwsA(
        isA<EventImportException>().having(
          (error) => error.message,
          'message',
          contains('timezone offset'),
        ),
      ),
    );
    expect(
      () => parseEventImport({...sample, 'end': '2026-09-20T10:00:00+01:00'}),
      throwsA(isA<EventImportException>()),
    );
  });

  test('sanitizes slash characters and stays stable', () {
    const externalId = 'a/b';
    final first = eventImportDocId('seb', externalId);
    final second = eventImportDocId('seb', externalId);
    expect(first, 'seb:a_b');
    expect(second, first);
    expect(first.contains('/'), isFalse);
  });

  test('resolves tom onto the hub member uid', () {
    const members = [
      HubMemberRef(uid: 'uid-maria', displayName: 'Maria Cole'),
      HubMemberRef(uid: 'uid-tom', displayName: 'Tom Workman'),
    ];
    final event = parseEventImport(sample, members: members).single;
    expect(event.assignedTo, 'uid-tom');

    expect(
      parseEventImport({
        ...sample,
        'assignedTo': 'maria',
      }, members: members).single.assignedTo,
      'uid-maria',
    );
    expect(resolveAssignedTo('shared', members), 'shared');
    expect(resolveAssignedTo('uid-tom', members), 'uid-tom');
  });

  test('id token uid must be a hub member', () {
    final token = _jwt({'user_id': 'uid-tom', 'sub': 'uid-tom'});
    expect(uidFromFirebaseIdToken(token), 'uid-tom');
    requireHubMember(uid: 'uid-tom', memberUids: ['uid-tom', 'uid-maria']);
    expect(
      () => requireHubMember(uid: 'uid-roger', memberUids: ['uid-tom']),
      throwsA(
        isA<EventImportException>().having(
          (error) => error.message,
          'message',
          contains('not a member'),
        ),
      ),
    );
  });

  test('hub document yields members and display names', () {
    final directory = parseHubDirectory({
      'fields': {
        'members': {
          'arrayValue': {
            'values': [
              {'stringValue': 'uid-tom'},
              {'stringValue': 'uid-maria'},
            ],
          },
        },
        'memberProfiles': {
          'mapValue': {
            'fields': {
              'uid-tom': {
                'mapValue': {
                  'fields': {
                    'displayName': {'stringValue': 'Tom Workman'},
                  },
                },
              },
            },
          },
        },
      },
    });
    expect(directory.memberUids, ['uid-tom', 'uid-maria']);
    expect(directory.displayNames['uid-tom'], 'Tom Workman');
    expect(
      parseUserDisplayName({
        'fields': {
          'displayName': {'stringValue': 'Maria Cole'},
        },
      }),
      'Maria Cole',
    );
  });

  test('import field map stores notes and omits gcalId', () {
    final event = parseEventImport(sample).single;
    final fields = event.toImportFields(ownerId: 'uid-tom');
    expect(fields['notes'], 'call time 14:30');
    expect(fields['summary'], 'C2 Show — Artist');
    expect(fields.containsKey('gcalId'), isFalse);

    final firestore = firestoreMapFromImport(event, ownerId: 'uid-tom');
    expect(firestore['start'], isA<Timestamp>());
    expect((firestore['start'] as Timestamp).toDate().toUtc(), event.start);
    expect(firestore.containsKey('gcalId'), isFalse);
    expect(firestore['notes'], 'call time 14:30');

    final rest = firestoreRestWrite(
      projectId: lovehubFirebaseProjectId,
      hubId: 'hub-1',
      event: event,
      ownerId: 'uid-tom',
    );
    final mask = (rest['updateMask'] as Map)['fieldPaths'] as List;
    expect(mask, isNot(contains('gcalId')));
    expect(mask, contains('notes'));
    expect(
      (rest['update'] as Map)['name'],
      'projects/lovehub-26107/databases/(default)/documents/hubs/hub-1/events/c2-rota:2026-09-20',
    );
  });

  test('EventModel round-trips import fields without dropping gcalId', () {
    final start = DateTime.utc(2026, 9, 20, 14);
    final end = DateTime.utc(2026, 9, 20, 22, 30);
    final model = EventModel.fromMap({
      'summary': 'C2 Show — Artist',
      'start': start,
      'end': end,
      'allDay': false,
      'category': 'work',
      'assignedTo': 'uid-tom',
      'gcalId': 'gcal-keep',
      'source': 'c2-rota',
      'externalId': '2026-09-20',
      'notes': 'call time 14:30',
    }, id: 'c2-rota:2026-09-20');

    expect(model.gcalId, 'gcal-keep');
    expect(model.notes, 'call time 14:30');
    expect(model.source, 'c2-rota');
    expect(model.toMap()['gcalId'], 'gcal-keep');
    expect(model.toMap()['notes'], 'call time 14:30');

    final manual = EventModel(
      id: 'hand-made',
      summary: 'Dinner',
      start: start,
      end: end,
    );
    expect(manual.toMap().containsKey('source'), isFalse);
    expect(manual.toMap().containsKey('notes'), isFalse);
    expect(manual.toMap().containsKey('gcalId'), isFalse);
  });

  test('upserting twice updates one document and keeps gcalId', () async {
    final store = _MemoryEventWriter();
    store.hubs['hub-1'] = {
      'c2-rota:2026-09-20': {
        'summary': 'old title',
        'gcalId': 'gcal-keep',
        'notes': 'old note',
        'ownerId': 'original-owner',
      },
    };
    final repo = EventRepository(writer: store);

    final first = parseEventImport(sample).single;
    await repo.upsertImportedEvents('hub-1', [first], ownerId: 'uid-tom');
    await repo.upsertImportedEvents('hub-1', [
      parseEventImport({...sample, 'summary': 'C2 Show — Updated'}).single,
    ], ownerId: 'uid-tom');

    final hub = store.hubs['hub-1']!;
    expect(hub.length, 1);
    expect(hub.keys.single, 'c2-rota:2026-09-20');
    expect(hub.values.single['summary'], 'C2 Show — Updated');
    expect(hub.values.single['notes'], 'call time 14:30');
    expect(hub.values.single['gcalId'], 'gcal-keep');
    expect(hub.values.single['source'], 'c2-rota');
    expect(hub.values.single['externalId'], '2026-09-20');
    expect(hub.values.single['category'], 'work');
    expect(hub.values.single['assignedTo'], 'tom');

    await repo.upsertImportedEvents('hub-1', [
      parseEventImport({...sample, 'notes': null}..remove('notes')).single,
      parseEventImport({
        'source': 'seb',
        'externalId': 'london',
        'summary': 'Sophie Ellis-Bextor',
        'start': '2026-10-03T19:00:00+01:00',
        'category': 'work',
        'assignedTo': 'tom',
      }).single,
    ]);

    expect(hub.length, 2);
    expect(hub['c2-rota:2026-09-20']!['notes'], isNull);
    expect(hub['c2-rota:2026-09-20']!['gcalId'], 'gcal-keep');
    expect(hub['c2-rota:2026-09-20']!['summary'], 'C2 Show — Artist');
    expect(hub.containsKey('seb:london'), isTrue);
  });

  test('duplicate ids in one payload collapse to the last copy', () async {
    final store = _MemoryEventWriter();
    final repo = EventRepository(writer: store);
    await repo.upsertImportedEvents('hub-1', [
      parseEventImport(sample).single,
      parseEventImport({...sample, 'summary': 'later copy'}).single,
    ]);
    expect(store.hubs['hub-1']!.length, 1);
    expect(store.hubs['hub-1']!.values.single['summary'], 'later copy');
  });

  test(
    'status is stored, preserved when omitted, and can be confirmed',
    () async {
      final store = _MemoryEventWriter();
      final repo = EventRepository(writer: store);
      final tentative = {...sample, 'status': 'tentative'};
      await repo.upsertImportedEvents('hub-1', [
        parseEventImport(tentative).single,
      ]);
      final doc = store.hubs['hub-1']!['c2-rota:2026-09-20']!;
      expect(doc['status'], 'tentative');
      expect(doc.containsKey('gcalId'), isFalse);

      await repo.upsertImportedEvents('hub-1', [
        parseEventImport(sample).single,
      ]);
      expect(doc['status'], 'tentative');
      expect(doc['summary'], 'C2 Show — Artist');

      await repo.confirmImportedEvent('hub-1', 'c2-rota', '2026-09-20');
      expect(doc['status'], 'confirmed');
      expect(doc['summary'], 'C2 Show — Artist');
      expect(doc['notes'], 'call time 14:30');

      await repo.upsertImportedEvents('hub-1', [
        parseEventImport({
          ...sample,
          'status': 'confirmed',
          'summary': 'Booked',
        }).single,
      ]);
      expect(doc['status'], 'confirmed');
      expect(doc['summary'], 'Booked');

      expect(
        () => repo.confirmImportedEvent('hub-1', 'seb', 'missing'),
        throwsA(isA<EventImportException>()),
      );
    },
  );

  test('in-app confirm sets status on the document id only', () async {
    final store = _MemoryEventWriter();
    final repo = EventRepository(writer: store);
    await repo.upsertImportedEvents('hub-1', [
      parseEventImport({...sample, 'status': 'tentative'}).single,
    ]);
    final doc = store.hubs['hub-1']!['c2-rota:2026-09-20']!;
    doc['gcalId'] = 'keep-me';

    await repo.confirmEvent('hub-1', 'c2-rota:2026-09-20');

    expect(doc['status'], 'confirmed');
    expect(doc['summary'], 'C2 Show — Artist');
    expect(doc['notes'], 'call time 14:30');
    expect(doc['gcalId'], 'keep-me');
    expect(
      () => repo.confirmEvent('hub-1', ' '),
      throwsA(isA<EventImportException>()),
    );
    expect(
      () => repo.confirmEvent('hub-1', 'missing'),
      throwsA(isA<EventImportException>()),
    );
  });

  test('in-app mark tentative sets status on the document id only', () async {
    final store = _MemoryEventWriter();
    final repo = EventRepository(writer: store);
    await repo.upsertImportedEvents('hub-1', [
      parseEventImport({...sample, 'status': 'confirmed'}).single,
    ]);
    final doc = store.hubs['hub-1']!['c2-rota:2026-09-20']!;
    doc['gcalId'] = 'keep-me';
    final before = Map<String, dynamic>.from(doc);

    await repo.markEventTentative('hub-1', 'c2-rota:2026-09-20');

    expect(doc['status'], 'tentative');
    expect(doc['summary'], before['summary']);
    expect(doc['notes'], before['notes']);
    expect(doc['gcalId'], 'keep-me');
    expect(doc.keys, before.keys);

    await repo.confirmEvent('hub-1', 'c2-rota:2026-09-20');
    expect(doc['status'], 'confirmed');
    expect(doc['gcalId'], 'keep-me');
    expect(doc['summary'], before['summary']);

    expect(
      () => repo.markEventTentative('hub-1', ' '),
      throwsA(isA<EventImportException>()),
    );
    expect(
      () => repo.markEventTentative('hub-1', 'a/b'),
      throwsA(isA<EventImportException>()),
    );
    expect(
      () => repo.markEventTentative('hub-1', 'missing'),
      throwsA(isA<EventImportException>()),
    );
  });

  test('asConfirmed clears only the tentative flag', () {
    final event = EventModel(
      id: 'c2-rota:2026-09-20',
      summary: 'C2 Show — Artist',
      start: DateTime.utc(2026, 9, 20, 14),
      end: DateTime.utc(2026, 9, 20, 22, 30),
      category: 'work',
      assignedTo: 'tom',
      source: 'c2-rota',
      externalId: '2026-09-20',
      notes: 'call time 14:30',
      status: 'tentative',
    );

    final confirmed = event.asConfirmed();
    expect(event.isTentative, isTrue);
    expect(confirmed.isTentative, isFalse);
    expect(confirmed.status, 'confirmed');
    expect(confirmed.id, event.id);
    expect(confirmed.summary, event.summary);
    expect(confirmed.notes, event.notes);
    expect(confirmed.source, 'c2-rota');
    expect(confirmed.asConfirmed(), same(confirmed));

    final again = confirmed.asTentative();
    expect(again.isTentative, isTrue);
    expect(again.status, 'tentative');
    expect(again.summary, event.summary);
    expect(again.notes, event.notes);
    expect(again.source, 'c2-rota');
    expect(again.asTentative(), same(again));
    expect(event.asTentative(), same(event));
  });

  test('create/edit status is explicit and survives toMap', () {
    final start = DateTime.utc(2026, 9, 20, 15);
    final end = DateTime.utc(2026, 9, 20, 23);

    EventModel drafted(bool tentative) {
      return EventModel(
        id: 'new',
        summary: 'Dinner',
        start: start,
        end: end,
        status: eventFormStatus(tentative),
      );
    }

    final on = drafted(true);
    final off = drafted(false);
    expect(on.toMap()['status'], 'tentative');
    expect(on.isTentative, isTrue);
    expect(off.toMap()['status'], 'confirmed');
    expect(off.isTentative, isFalse);

    final legacy = EventModel(
      id: 'legacy',
      summary: 'Dinner',
      start: start,
      end: end,
    );
    expect(legacy.toMap().containsKey('status'), isFalse);
    expect(legacy.asTentative().toMap()['status'], 'tentative');
    expect(legacy.asConfirmed(), same(legacy));
  });

  test('a rota envelope or default marks every omitted row tentative', () {
    final row = {
      'source': 'c2-rota',
      'externalId': '2026-09-21',
      'summary': 'C2 Show — Maybe',
      'start': '2026-09-21T15:00:00+01:00',
      'category': 'work',
      'assignedTo': 'tom',
    };
    final envelope = parseEventImport({
      'status': 'tentative',
      'events': [
        row,
        {...row, 'externalId': '2026-09-22', 'status': 'confirmed'},
      ],
    });
    expect(envelope.first.status, 'tentative');
    expect(envelope.last.status, 'confirmed');
    expect(envelope.first.toImportFields()['status'], 'tentative');
    expect(
      parseEventImport(sample).single.toImportFields().containsKey('status'),
      isFalse,
    );

    final dumped = parseEventImport([
      row,
      {...row, 'externalId': '2026-09-23'},
    ], defaultStatus: eventStatusTentative);
    expect(dumped.every((event) => event.status == 'tentative'), isTrue);

    expect(
      () => parseEventImport({...sample, 'status': 'maybe'}),
      throwsA(isA<EventImportException>()),
    );
  });

  test('confirm target and import flags parse source:externalId', () {
    final target = parseConfirmTarget('c2-rota:2026-09-20');
    expect(target.source, 'c2-rota');
    expect(target.externalId, '2026-09-20');
    expect(target.docId, 'c2-rota:2026-09-20');

    final command = parseImportCommand([
      '--tentative',
      '--dry-run',
      '--file',
      'rota.json',
    ], hubFromEnvironment: 'hub-1');
    expect(command.tentative, isTrue);
    expect(command.defaultStatus, 'tentative');
    expect(command.hubId, 'hub-1');
    expect(command.file, 'rota.json');

    final confirm = parseImportCommand(['--confirm', 'seb:london']);
    expect(confirm.confirm.single.docId, 'seb:london');
    expect(
      () => parseImportCommand(['--tentative', '--confirm', 'seb:london']),
      throwsA(isA<EventImportException>()),
    );

    final rest = firestoreRestConfirmWrite(
      projectId: lovehubFirebaseProjectId,
      hubId: 'hub-1',
      target: target,
    );
    expect((rest['updateMask'] as Map)['fieldPaths'], ['status']);
    expect((rest['currentDocument'] as Map)['exists'], isTrue);
    expect(((rest['update'] as Map)['fields'] as Map)['status'], {
      'stringValue': 'confirmed',
    });
  });
}

String _jwt(Map<String, Object?> payload) {
  String encode(Object? value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode({'alg': 'none'})}.${encode(payload)}.sig';
}

class _MemoryEventWriter implements EventBatchWriter {
  final Map<String, Map<String, Map<String, dynamic>>> hubs = {};

  @override
  Future<void> commitMerges(
    String hubId,
    Map<String, Map<String, dynamic>> docs,
  ) async {
    final hub = hubs.putIfAbsent(hubId, () => {});
    docs.forEach((id, data) {
      final current = hub.putIfAbsent(id, () => {});
      data.forEach((key, value) {
        current[key] = value;
      });
    });
  }

  @override
  Future<void> updateFields(
    String hubId,
    String eventId,
    Map<String, dynamic> fields,
  ) async {
    final doc = hubs[hubId]?[eventId];
    if (doc == null) {
      throw EventImportException(
        'No event $eventId in hub $hubId. Import it before confirming.',
      );
    }
    doc.addAll(fields);
  }
}
