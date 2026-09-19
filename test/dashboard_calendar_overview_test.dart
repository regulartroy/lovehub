import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  final now = DateTime(2026, 9, 19); // Saturday

  List<Map<String, dynamic>> sampleEvents() {
    DateTime at(int dayOffset, [int hour = 9, int minute = 0]) {
      return DateTime(now.year, now.month, now.day + dayOffset, hour, minute);
    }

    return [
      {
        'summary': 'Farmers market walk',
        'start': at(0, 9, 30),
        'end': at(0, 11, 0),
        'allDay': false,
        'category': 'shared',
        'assignedTo': 'shared',
      },
      {
        'summary': "Maria's birthday",
        'start': DateUtils.dateOnly(at(3)),
        'end': DateUtils.dateOnly(at(3)),
        'allDay': true,
        'category': 'birthday',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Weekend away',
        'start': DateUtils.dateOnly(at(6)),
        'end': DateUtils.dateOnly(at(8)),
        'allDay': true,
        'category': 'shared',
        'assignedTo': 'shared',
      },
    ];
  }

  test('monday-of helper lands on the UK week start', () {
    expect(dashboardMondayOf(DateTime(2026, 9, 19)), DateTime(2026, 9, 14));
    expect(dashboardMondayOf(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
    expect(dashboardMondayOf(DateTime(2026, 9, 20)), DateTime(2026, 9, 14));
  });

  test('event overlap includes every day of a multi-day span', () {
    final event = {
      'start': DateTime(2026, 9, 25),
      'end': DateTime(2026, 9, 27),
      'allDay': true,
    };

    expect(dashboardEventOverlapsDay(event, DateTime(2026, 9, 24)), isFalse);
    expect(dashboardEventOverlapsDay(event, DateTime(2026, 9, 25)), isTrue);
    expect(dashboardEventOverlapsDay(event, DateTime(2026, 9, 26)), isTrue);
    expect(dashboardEventOverlapsDay(event, DateTime(2026, 9, 27)), isTrue);
    expect(dashboardEventOverlapsDay(event, DateTime(2026, 9, 28)), isFalse);
  });

  test('events on a day sort by start time', () {
    final later = {
      'summary': 'Dinner',
      'start': DateTime(2026, 9, 19, 19),
      'end': DateTime(2026, 9, 19, 21),
    };
    final earlier = {
      'summary': 'Walk',
      'start': DateTime(2026, 9, 19, 9),
      'end': DateTime(2026, 9, 19, 10),
    };

    final ordered = dashboardEventsOnDay([later, earlier], DateTime(2026, 9, 19));
    expect(ordered.map((e) => e['summary']), ['Walk', 'Dinner']);
  });

  test('range labels stay short enough for a tablet chip', () {
    expect(
      dashboardCompactDayRange(DateTime(2026, 9, 19), DateTime(2026, 9, 25)),
      '19–25 SEP',
    );
    expect(
      dashboardMonthRangeLabel(DateTime(2026, 9, 14), DateTime(2026, 10, 18)),
      'SEP – OCT',
    );
  });

  testWidgets('look-ahead slide shows the week strip and month grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1024, 768)),
            events: sampleEvents(),
            now: now,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 7 DAYS'), findsOneWidget);
    expect(find.text('SEP – OCT'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets);
    expect(find.text('SUN'), findsWidgets);
    expect(find.textContaining('Farmers market walk'), findsWidgets);
    expect(find.text("Maria's birthday"), findsWidgets);
    expect(find.text('Weekend away'), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Quiet month — add plans from Calendar'), findsNothing);
  });

  testWidgets('empty look-ahead still draws the calendar and a quiet hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(390, 844)),
            events: const [],
            now: now,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 7 DAYS'), findsOneWidget);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Quiet month — add plans from Calendar'), findsOneWidget);
  });

  testWidgets('compact phone layout keeps the look-ahead title readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(390, 844)),
            events: sampleEvents(),
            now: now,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 7 DAYS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
