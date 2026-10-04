import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

Map<String, dynamic> _event(
  DateTime start, {
  DateTime? end,
  bool allDay = false,
}) => {
  'summary': 'Event',
  'start': Timestamp.fromDate(start),
  if (end != null) 'end': Timestamp.fromDate(end),
  'allDay': allDay,
};

void main() {
  group('dashboardEventTimeRangeLabel', () {
    test('shows start–end with an en dash', () {
      final e = _event(
        DateTime(2026, 10, 3, 19),
        end: DateTime(2026, 10, 3, 23),
      );
      expect(dashboardEventTimeRangeLabel(e), '19:00\u201323:00');
    });

    test('keeps minutes', () {
      final e = _event(
        DateTime(2026, 10, 3, 9, 5),
        end: DateTime(2026, 10, 3, 10, 45),
      );
      expect(dashboardEventTimeRangeLabel(e), '09:05\u201310:45');
    });

    test('no end shows start only', () {
      expect(
        dashboardEventTimeRangeLabel(_event(DateTime(2026, 10, 3, 7))),
        '07:00',
      );
    });

    test('end equal to (or before) start shows start only', () {
      final start = DateTime(2026, 10, 3, 18, 30);
      expect(dashboardEventTimeRangeLabel(_event(start, end: start)), '18:30');
      expect(
        dashboardEventTimeRangeLabel(
          _event(start, end: start.subtract(const Duration(hours: 1))),
        ),
        '18:30',
      );
    });

    test('overnight event keeps the range with a +1 marker', () {
      final e = _event(
        DateTime(2026, 10, 3, 22),
        end: DateTime(2026, 10, 4, 3),
      );
      expect(dashboardEventTimeRangeLabel(e), '22:00\u201303:00 +1');
    });

    test('ending at midnight next day still marks +1', () {
      final e = _event(DateTime(2026, 10, 3, 20), end: DateTime(2026, 10, 4));
      expect(dashboardEventTimeRangeLabel(e), '20:00\u201300:00 +1');
    });

    test('multi-night span counts days across a clock change', () {
      // UK clocks go back on Sun 25 Oct 2026.
      final e = _event(
        DateTime(2026, 10, 24, 18),
        end: DateTime(2026, 10, 26, 16),
      );
      expect(dashboardEventTimeRangeLabel(e), '18:00\u201316:00 +2');
    });

    test('all-day events are unchanged', () {
      final e = _event(
        DateTime(2026, 10, 3),
        end: DateTime(2026, 10, 4),
        allDay: true,
      );
      expect(dashboardEventTimeRangeLabel(e), 'All day');
    });

    test('accepts plain DateTime values', () {
      final e = {
        'start': DateTime(2026, 10, 3, 19),
        'end': DateTime(2026, 10, 3, 23),
      };
      expect(dashboardEventTimeRangeLabel(e), '19:00\u201323:00');
    });

    test('LOOK AHEAD glance label still shows start only', () {
      final e = _event(
        DateTime(2026, 10, 3, 19),
        end: DateTime(2026, 10, 3, 23),
      );
      expect(dashboardGlanceTimeLabel(e), '19:00');
    });
  });

  testWidgets('fitSubtitle shrinks the time instead of truncating it', (
    tester,
  ) async {
    const style = CalendarEventStyle(
      who: CalendarColors.tom,
      kind: CalendarColors.work,
    );
    const range = '22:00\u201303:00 +1';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: CalendarSplitPill(
                style: style,
                title: 'Party',
                subtitle: range,
                fitSubtitle: true,
                density: CalendarSplitPillDensity.comfortable,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(range));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.ancestor(of: find.text(range), matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    // The scaled time stays inside the pill.
    final pill = tester.getRect(find.byType(CalendarSplitPill));
    final time = tester.getRect(find.text(range));
    expect(time.right, lessThanOrEqualTo(pill.right + 0.5));
    expect(find.text('Party'), findsOneWidget);
  });

  testWidgets('default split pill still ellipsises the subtitle', (
    tester,
  ) async {
    const style = CalendarEventStyle(
      who: CalendarColors.tom,
      kind: CalendarColors.work,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CalendarSplitPill(style: style, title: 'A', subtitle: '07:00'),
        ),
      ),
    );
    expect(find.byType(FittedBox), findsNothing);
    expect(
      tester.widget<Text>(find.text('07:00')).overflow,
      TextOverflow.ellipsis,
    );
  });
}
