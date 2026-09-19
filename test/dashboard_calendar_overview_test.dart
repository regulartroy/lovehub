import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  final now = DateTime(2026, 9, 19); // Saturday
  final members = [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ];

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
        'category': 'general',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Early shift',
        'start': at(1, 7, 0),
        'end': at(1, 15, 0),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'tom',
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
      {
        'summary': 'Date night',
        'start': at(12, 19, 30),
        'end': at(12, 22, 0),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Parents evening',
        'start': at(21, 18, 0),
        'end': at(21, 19, 0),
        'allDay': false,
        'category': 'general',
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
      dashboardCompactDayRange(DateTime(2026, 9, 19), DateTime(2026, 10, 16)),
      '19 SEP – 16 OCT',
    );
  });

  test('look-ahead weeks roll four 7-day strips from today', () {
    final weeks = dashboardLookAheadWeeks(now);
    expect(weeks, hasLength(4));
    expect(weeks.every((week) => week.length == 7), isTrue);
    expect(weeks.first.first, DateTime(2026, 9, 19));
    expect(weeks.first.last, DateTime(2026, 9, 25));
    expect(weeks.last.first, DateTime(2026, 10, 10));
    expect(weeks.last.last, DateTime(2026, 10, 16));
  });

  testWidgets('look-ahead slide shows four week-strips and no month grid', (
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
            members: members,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 4 WEEKS'), findsOneWidget);
    expect(find.text('NEXT 7 DAYS'), findsNothing);
    expect(find.text('SEP – OCT'), findsNothing);
    expect(find.text('Mo'), findsNothing);
    expect(find.text('Tu'), findsNothing);
    expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-3')), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('SUN'), findsWidgets);
    expect(find.textContaining('Farmers market walk'), findsWidgets);
    expect(find.text("Maria's birthday"), findsWidgets);
    expect(find.text('Weekend away'), findsWidgets);
    expect(find.textContaining('Date night'), findsWidgets);
    expect(find.textContaining('Parents evening'), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Tom'), findsWidgets);
    expect(find.text('Maria'), findsWidgets);
    expect(find.text('Shared'), findsWidgets);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('Leisure'), findsWidgets);
    expect(find.text('Birthdays'), findsWidgets);
    expect(find.text('Quiet stretch — add plans from Calendar'), findsNothing);
    expect(find.text('Quiet month — add plans from Calendar'), findsNothing);
    expect(
      dashboardGlanceColor(
        {'assignedTo': 'tom', 'category': 'work'},
        palette: HubMemberPalette.fromMembers(members),
      ),
      CalendarColors.work,
    );
    expect(
      dashboardGlanceColor(
        {'assignedTo': 'maria', 'category': 'general'},
        palette: HubMemberPalette.fromMembers(members),
      ),
      CalendarColors.personal,
    );
    expect(
      dashboardGlanceColor(
        {'assignedTo': 'shared', 'category': 'birthday'},
        palette: HubMemberPalette.fromMembers(members),
      ),
      CalendarColors.birthday,
    );
  });

  testWidgets('empty look-ahead still draws four week-strips and a quiet hint', (
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
            members: members,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 4 WEEKS'), findsOneWidget);
    expect(find.text('Free'), findsWidgets);
    expect(find.byKey(const ValueKey('look-ahead-week-3')), findsOneWidget);
    expect(find.text('Quiet stretch — add plans from Calendar'), findsOneWidget);
    expect(find.text('Quiet month — add plans from Calendar'), findsNothing);
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
            members: members,
          ),
        ),
      ),
    );

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('NEXT 4 WEEKS'), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-3')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
