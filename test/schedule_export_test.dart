import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/event_import/london_date.dart';
import 'package:lovehub/event_import/schedule_export.dart';
import 'package:lovehub/services/hub_collection.dart';

void main() {
  const window = LondonWindow(
    start: LondonDate(2026, 11, 11),
    end: LondonDate(2026, 11, 17),
  );

  ExportEvent event({
    String id = 'e1',
    String title = 'Show',
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    ExportPerson person = ExportPerson.tom,
    ExportCategory category = ExportCategory.work,
    bool tentative = false,
    String source = 'c2-rota',
  }) {
    return ExportEvent(
      id: id,
      title: title,
      start: start,
      end: end ?? start.add(const Duration(hours: 1)),
      allDay: allDay,
      person: person,
      category: category,
      tentative: tentative,
      source: source,
    );
  }

  StoredExportEvent stored({
    String id = 'doc-1',
    String summary = 'Rehearsal',
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String category = 'work',
    String assignedTo = 'tom',
    String? status,
    String? source,
  }) {
    return StoredExportEvent(
      id: id,
      summary: summary,
      start: start,
      end: end ?? start.add(const Duration(hours: 2)),
      allDay: allDay,
      category: category,
      assignedTo: assignedTo,
      status: status,
      source: source,
    );
  }

  group('args and window', () {
    test('reads hub, out-dir, days, and HUB_ID', () {
      final command = parseScheduleExportArgs(
        ['--out-dir', '/tmp/sched', '--days', '25'],
        environment: {'HUB_ID': 'pobIb3qupVJudoQGMJjl'},
      );
      expect(command.hubId, 'pobIb3qupVJudoQGMJjl');
      expect(command.outDir, '/tmp/sched');
      expect(command.days, 25);
      expect(command.help, isFalse);
    });

    test('requires a hub when help is not asked', () {
      expect(
        () => parseScheduleExportArgs(const []),
        throwsA(
          isA<ScheduleExportArgsException>().having(
            (error) => error.message,
            'message',
            contains('--hub'),
          ),
        ),
      );
    });

    test('rejects a days value outside 1..366', () {
      expect(
        () => parseScheduleExportArgs(['--hub', 'h1', '--days', '0']),
        throwsA(isA<ScheduleExportArgsException>()),
      );
      expect(
        () => parseScheduleExportArgs(['--hub', 'h1', '--days', '400']),
        throwsA(isA<ScheduleExportArgsException>()),
      );
    });

    test('today through today+days is inclusive on the London calendar', () {
      final winter = scheduleExportWindow(
        DateTime.utc(2026, 11, 11, 16, 42),
        days: 56,
      );
      expect(winter.start.ymd, '2026-11-11');
      expect(winter.end.ymd, '2027-01-06');

      // 23:30 UTC on 15 July is already the 16th in BST.
      final summer = scheduleExportWindow(
        DateTime.utc(2026, 7, 15, 23, 30),
        days: 2,
      );
      expect(summer.start.ymd, '2026-07-16');
      expect(summer.end.ymd, '2026-07-18');
    });
  });

  group('mapping', () {
    test('maps categories, people, sources, and tentative status', () {
      expect(exportCategoryFor('general'), ExportCategory.personal);
      expect(exportCategoryFor('Personal'), ExportCategory.personal);
      expect(exportCategoryFor('work'), ExportCategory.work);
      expect(exportCategoryFor('meal'), ExportCategory.meal);
      expect(exportCategoryFor('birthday'), ExportCategory.birthday);
      expect(exportCategoryFor('other-stuff'), ExportCategory.other);

      expect(exportSourceFor(null), 'manual');
      expect(exportSourceFor('  '), 'manual');
      expect(exportSourceFor('c2-rota'), 'c2-rota');

      expect(isTentativeStatus('tentative'), isTrue);
      expect(isTentativeStatus('confirmed'), isFalse);
      expect(isTentativeStatus(null), isFalse);

      const people = {
        'uid-tom': ExportPerson.tom,
        'uid-maria': ExportPerson.maria,
      };
      expect(exportPersonFor('tom', people), ExportPerson.tom);
      expect(exportPersonFor('maria', people), ExportPerson.maria);
      expect(exportPersonFor('shared', people), ExportPerson.shared);
      expect(exportPersonFor('uid-tom', people), ExportPerson.tom);
      expect(exportPersonFor('uid-unknown', people), ExportPerson.shared);
    });

    test('names containing tom or maria become the person tokens', () {
      final mapped = peopleByUidFromProfiles({
        'aaa': 'Tom Regular',
        'bbb': 'Maria Example',
        'ccc': 'Sam',
        'shared': 'ignored',
      });
      expect(mapped['aaa'], ExportPerson.tom);
      expect(mapped['bbb'], ExportPerson.maria);
      expect(mapped.containsKey('ccc'), isFalse);
      expect(mapped.containsKey('shared'), isFalse);
    });

    test('redacts email addresses from titles', () {
      expect(
        redactSecrets('Dinner with tom@example.com tonight'),
        'Dinner with [redacted] tonight',
      );
    });

    test('formats instants with a Europe/London offset', () {
      expect(
        formatLondonIso(DateTime.utc(2026, 11, 11, 19)),
        '2026-11-11T19:00:00+00:00',
      );
      expect(
        formatLondonIso(DateTime.utc(2026, 7, 15, 18)),
        '2026-07-15T19:00:00+01:00',
      );
    });

    test('builds export events and drops ones outside the window', () {
      final snapshot = buildScheduleSnapshot(
        generatedAt: DateTime.utc(2026, 11, 11, 16, 40),
        window: window,
        hubId: 'hub-1',
        namesByUid: {'uid-tom': 'Tom Regular'},
        events: [
          stored(
            id: 'c2-rota:mnek',
            summary: 'MNEK',
            start: DateTime.utc(2026, 11, 12, 19),
            end: DateTime.utc(2026, 11, 12, 23),
            source: 'c2-rota',
            status: 'tentative',
          ),
          stored(
            id: 'meal-1',
            summary: 'Saffron rice',
            start: DateTime.utc(2026, 11, 11, 19),
            end: DateTime.utc(2026, 11, 11, 20),
            category: 'meal',
            assignedTo: 'shared',
          ),
          stored(
            id: 'uid-work',
            summary: 'Tech rehearsal',
            start: DateTime.utc(2026, 11, 13, 10),
            end: DateTime.utc(2026, 11, 13, 16),
            assignedTo: 'uid-tom',
            source: 'manual',
          ),
          stored(
            id: 'outside',
            summary: 'Too far ahead',
            start: DateTime.utc(2026, 12, 1, 19),
            end: DateTime.utc(2026, 12, 1, 22),
          ),
        ],
        birthdays: const [
          StoredBirthday(
            id: 'b1',
            name: 'Maria',
            month: 11,
            day: 15,
            year: 1990,
          ),
        ],
      );

      expect(snapshot.events.map((e) => e.id), [
        'meal-1',
        'c2-rota:mnek',
        'uid-work',
        'bday_b1_2026',
      ]);
      expect(snapshot.events[0].category, ExportCategory.meal);
      expect(snapshot.events[0].person, ExportPerson.shared);
      expect(snapshot.events[0].source, 'manual');
      expect(snapshot.events[1].tentative, isTrue);
      expect(snapshot.events[1].source, 'c2-rota');
      expect(snapshot.events[2].person, ExportPerson.tom);
      expect(snapshot.events[3].title, 'Maria (36)');
      expect(snapshot.events[3].allDay, isTrue);
      expect(snapshot.events[3].source, 'birthday');
      expect(
        exportEventBelongsOnDay(
          snapshot.events[3],
          const LondonDate(2026, 11, 15),
        ),
        isTrue,
      );
      expect(
        exportEventBelongsOnDay(
          snapshot.events[3],
          const LondonDate(2026, 11, 16),
        ),
        isFalse,
      );
      expect(snapshot.days.length, 7);
      expect(
        snapshot.days
            .singleWhere((day) => day.date.ymd == '2026-11-15')
            .eventCount,
        1,
      );
      expect(snapshot.toJson()['windowStart'], '2026-11-11');
      expect(snapshot.toJson()['windowEnd'], '2026-11-17');
      expect(snapshot.toJson()['timezone'], 'Europe/London');
    });

    test('parses Firestore REST documents without leaking a uid', () {
      final events = storedEventsFromRestList({
        'documents': [
          {
            'name':
                'projects/lovehub-26107/databases/(default)/documents/$kHubsCollection/h/events/c2-rota%3Ashow',
            'fields': {
              'summary': {'stringValue': 'Show'},
              'start': {'timestampValue': '2026-11-12T19:00:00Z'},
              'end': {'timestampValue': '2026-11-12T23:00:00Z'},
              'allDay': {'booleanValue': false},
              'category': {'stringValue': 'work'},
              'assignedTo': {'stringValue': 'uid-tom'},
              'status': {'stringValue': 'confirmed'},
              'source': {'stringValue': 'c2-rota'},
            },
          },
        ],
      });
      expect(events.single.id, 'c2-rota:show');
      final names = namesByUidFromHubDocument({
        'name':
            'projects/lovehub-26107/databases/(default)/documents/$kHubsCollection/h',
        'fields': {
          'memberProfiles': {
            'mapValue': {
              'fields': {
                'uid-tom': {
                  'mapValue': {
                    'fields': {
                      'displayName': {'stringValue': 'Tom Regular'},
                    },
                  },
                },
              },
            },
          },
        },
      });
      final mapped = mapStoredEvent(
        events.single,
        peopleByUid: peopleByUidFromProfiles(names),
      )!;
      expect(mapped.person, ExportPerson.tom);
      expect(mapped.toJson()['person'], 'tom');
      expect(mapped.toJson().values.join(' '), isNot(contains('uid-tom')));
    });
  });

  group('busy days', () {
    test('classifies none, daytime, evening, and all-day', () {
      final daytime = event(
        id: 'day',
        start: londonWallTime(const LondonDate(2026, 11, 12), 10),
        end: londonWallTime(const LondonDate(2026, 11, 12), 16),
      );
      final evening = event(
        id: 'eve',
        start: londonWallTime(const LondonDate(2026, 11, 13), 19),
        end: londonWallTime(const LondonDate(2026, 11, 13), 23),
      );
      final both = event(
        id: 'long',
        start: londonWallTime(const LondonDate(2026, 11, 14), 10),
        end: londonWallTime(const LondonDate(2026, 11, 14), 18),
      );
      final allDay = event(
        id: 'travel',
        title: 'Travel',
        start: londonStartOfDay(const LondonDate(2026, 11, 15)),
        end: londonStartOfDay(const LondonDate(2026, 11, 16)),
        allDay: true,
      );
      final meal = event(
        id: 'meal',
        title: 'Dinner',
        start: londonWallTime(const LondonDate(2026, 11, 12), 19),
        end: londonWallTime(const LondonDate(2026, 11, 12), 20),
        person: ExportPerson.shared,
        category: ExportCategory.meal,
        source: 'manual',
      );

      expect(
        tomBusyForDay([daytime], const LondonDate(2026, 11, 12)),
        TomBusy.daytime,
      );
      expect(
        tomBusyForDay([evening], const LondonDate(2026, 11, 13)),
        TomBusy.evening,
      );
      expect(
        tomBusyForDay([both], const LondonDate(2026, 11, 14)),
        TomBusy.allDay,
      );
      expect(
        tomBusyForDay([allDay], const LondonDate(2026, 11, 15)),
        TomBusy.allDay,
      );
      expect(
        tomBusyForDay([daytime, evening], const LondonDate(2026, 11, 12)),
        TomBusy.daytime,
      );
      expect(
        tomBusyForDay([meal], const LondonDate(2026, 11, 12)),
        TomBusy.none,
      );
      expect(
        tomBusyForDay([daytime, evening], const LondonDate(2026, 11, 16)),
        TomBusy.none,
      );
    });

    test('overnight work ending before 06:00 stays on the start day', () {
      final show = event(
        id: 'late',
        start: londonWallTime(const LondonDate(2026, 11, 12), 22),
        end: londonWallTime(const LondonDate(2026, 11, 13), 1),
      );
      expect(
        exportEventBelongsOnDay(show, const LondonDate(2026, 11, 12)),
        isTrue,
      );
      expect(
        exportEventBelongsOnDay(show, const LondonDate(2026, 11, 13)),
        isFalse,
      );
      expect(
        tomBusyForDay([show], const LondonDate(2026, 11, 12)),
        TomBusy.evening,
      );
      expect(
        tomBusyForDay([show], const LondonDate(2026, 11, 13)),
        TomBusy.none,
      );
    });

    test('work still going at 06:00 counts on the following morning', () {
      final long = event(
        id: 'call',
        start: londonWallTime(const LondonDate(2026, 11, 12), 22),
        end: londonWallTime(const LondonDate(2026, 11, 13), 8),
      );
      expect(
        exportEventBelongsOnDay(long, const LondonDate(2026, 11, 13)),
        isTrue,
      );
      expect(
        tomBusyForDay([long], const LondonDate(2026, 11, 12)),
        TomBusy.evening,
      );
      expect(
        tomBusyForDay([long], const LondonDate(2026, 11, 13)),
        TomBusy.daytime,
      );
    });

    test('summaries include quiet days and event counts', () {
      final days = summarizeExportDays([
        event(
          id: 'meal',
          title: 'Dinner',
          start: londonWallTime(const LondonDate(2026, 11, 11), 19),
          end: londonWallTime(const LondonDate(2026, 11, 11), 20),
          person: ExportPerson.shared,
          category: ExportCategory.meal,
          source: 'manual',
        ),
        event(
          start: londonWallTime(const LondonDate(2026, 11, 11), 19),
          end: londonWallTime(const LondonDate(2026, 11, 11), 23),
        ),
      ], window);
      expect(days.first.date.ymd, '2026-11-11');
      expect(days.first.eventCount, 2);
      expect(days.first.tomBusy, TomBusy.evening);
      expect(days[1].eventCount, 0);
      expect(days[1].tomBusy, TomBusy.none);
      expect(days.last.date.ymd, '2026-11-17');
      expect(days.length, 7);
    });
  });

  group('ics', () {
    test('writes VEVENTs with UTC times and exclusive all-day ends', () {
      final snapshot = buildScheduleSnapshot(
        generatedAt: DateTime.utc(2026, 11, 11, 16, 40, 12),
        window: window,
        events: [
          stored(
            id: 'c2-rota:mnek',
            summary: 'MNEK, late show; doors',
            start: DateTime.utc(2026, 11, 12, 19),
            end: DateTime.utc(2026, 11, 12, 23),
            source: 'c2-rota',
            status: 'tentative',
          ),
        ],
        birthdays: const [
          StoredBirthday(id: 'b1', name: 'Maria', month: 11, day: 15),
        ],
      );
      final ics = renderScheduleIcs(snapshot);
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('METHOD:PUBLISH'));
      expect(ics, contains('DTSTART:20261112T190000Z'));
      expect(ics, contains('DTEND:20261112T230000Z'));
      expect(ics, contains('STATUS:TENTATIVE'));
      expect(ics, contains(r'SUMMARY:MNEK\, late show\; doors'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261115'));
      expect(ics, contains('DTEND;VALUE=DATE:20261116'));
      expect(ics, contains('CATEGORIES:BIRTHDAY'));
      expect(ics, isNot(contains('tom@')));
    });
  });

  group('readme', () {
    test('explains the fields and that the copy is read-only', () {
      final text = scheduleExportReadme(
        outDir: '/home/box/shared/lovehub',
        commandHint: 'tool/export_schedule.sh --hub pobIb3qupVJudoQGMJjl',
      );
      expect(text, contains('Read-only'));
      expect(text, contains('generatedAt'));
      expect(text, contains('tomBusy'));
      expect(text, contains('/home/box/shared/lovehub/schedule.json'));
      expect(
        text,
        contains('tool/export_schedule.sh --hub pobIb3qupVJudoQGMJjl'),
      );
    });
  });
}
