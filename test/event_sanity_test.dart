import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/event_sanity.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

void main() {
  group('calendarDayOffset', () {
    test('steps calendar days across the October clock change', () {
      final tue = DateTime(2026, 10, 20);
      final days = [for (var i = 0; i < 7; i++) calendarDayOffset(tue, i)];
      expect(days.map((d) => d.day), [20, 21, 22, 23, 24, 25, 26]);
      expect(days.every((d) => d.hour == 0), isTrue);
      expect(
        days.map((d) => d.day).toSet().length,
        7,
        reason: 'no duplicate Sunday',
      );
    });
    test('and across March', () {
      expect(
        calendarDayOffset(DateTime(2027, 3, 27), 2),
        DateTime(2027, 3, 29),
      );
    });
  });

  group('sanitizeEventMaps', () {
    // Real shape of the doc that blanked the dashboard on 20 Oct 2026:
    // all-day, start 25 Oct 00:00 BST, end 24 Oct 01:00 BST.
    final bad = {
      'id': 'cAKSsVjHNvOHfAwBGiZx',
      'summary': 'Sophie - Covent Garden',
      'allDay': true,
      'start': Timestamp.fromDate(DateTime.utc(2026, 10, 24, 23)),
      'end': Timestamp.fromDate(DateTime.utc(2026, 10, 24)),
    };

    test('clamps end-before-start to start, keeping the event', () {
      final out = sanitizeEventMaps([bad]);
      expect(out, hasLength(1));
      expect(out.single['end'], bad['start']);
      expect(
        dashboardEventOverlapsDay(out.single, DateTime(2026, 10, 25)),
        isTrue,
      );
      expect(
        dashboardEventOverlapsDay(out.single, DateTime(2026, 10, 24)),
        isFalse,
      );
    });

    test('one broken doc never drops the others', () {
      final good = {
        'id': 'ok',
        'summary': 'Dentist',
        'start': Timestamp.fromDate(DateTime(2026, 10, 21, 8, 30)),
        'end': Timestamp.fromDate(DateTime(2026, 10, 21, 9, 30)),
      };
      final out = sanitizeEventMaps([
        {'id': 'nostart', 'summary': 'x'},
        {'id': 'strdate', 'summary': 'y', 'start': '2026-10-21'},
        {'id': 'strend', 'summary': 'z', 'start': good['start'], 'end': 'soon'},
        bad,
        good,
      ]);
      expect(out.map((e) => e['id']), ['strend', 'cAKSsVjHNvOHfAwBGiZx', 'ok']);
      expect(out.first.containsKey('end'), isFalse);
    });
  });

  test('guardedBuild swallows and returns null', () {
    expect(guardedBuild<int>('x', () => throw StateError('boom')), isNull);
    expect(guardedBuild('y', () => 3), 3);
  });
}
