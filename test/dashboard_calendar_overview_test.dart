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
        'summary': 'Bin night',
        'start': DateUtils.dateOnly(at(-5)),
        'end': DateUtils.dateOnly(at(-5)),
        'allDay': true,
        'category': 'general',
        'assignedTo': 'tom',
      },
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
      {
        'summary': 'Half-term walk',
        'start': at(150, 10, 0),
        'end': at(150, 12, 0),
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

    final ordered = dashboardEventsOnDay([
      later,
      earlier,
    ], DateTime(2026, 9, 19));
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

  test('look-ahead weeks are Monday–Sunday rows covering ~6 months ahead', () {
    final saturday = dashboardLookAheadWeeks(now);
    expect(saturday.length, greaterThanOrEqualTo(26));
    expect(saturday.every((week) => week.length == 7), isTrue);
    expect(
      saturday.every((week) => week.first.weekday == DateTime.monday),
      isTrue,
    );
    expect(
      saturday.every((week) => week.last.weekday == DateTime.sunday),
      isTrue,
    );
    expect(saturday.first.first, DateTime(2026, 9, 14));
    expect(saturday.first.last, DateTime(2026, 9, 20));
    expect(saturday[0][5], DateTime(2026, 9, 19));
    expect(saturday.last.first.isAfter(DateTime(2027, 3, 1)), isTrue);
    expect(saturday.last.last.isBefore(DateTime(2027, 4, 1)), isTrue);

    final sixMonthsOut = DateTime(2026, 9 + 6, 19);
    expect(
      saturday.last.last.isAfter(
        sixMonthsOut.subtract(const Duration(days: 7)),
      ),
      isTrue,
    );
    expect(
      saturday.last.first.isBefore(sixMonthsOut.add(const Duration(days: 7))),
      isTrue,
    );

    final monday = dashboardLookAheadWeeks(DateTime(2026, 9, 14));
    expect(monday.length, greaterThanOrEqualTo(26));
    expect(monday.first.first, DateTime(2026, 9, 14));
    expect(monday.last.last.isAfter(DateTime(2027, 3, 1)), isTrue);

    final sunday = dashboardLookAheadWeeks(DateTime(2026, 9, 20));
    expect(sunday.length, greaterThanOrEqualTo(26));
    expect(sunday.first.first, DateTime(2026, 9, 14));
    expect(sunday.last.last.isAfter(DateTime(2027, 3, 1)), isTrue);
  });

  test('look-ahead week count covers six months from today', () {
    expect(dashboardLookAheadWeekCount(DateTime(2026, 9, 14)), 26);
    expect(dashboardLookAheadWeekCount(DateTime(2026, 9, 16)), 27);
    expect(dashboardLookAheadWeekCount(DateTime(2026, 9, 19)), 27);
    expect(dashboardLookAheadWeekCount(DateTime(2026, 9, 20)), 27);
  });

  testWidgets('look-ahead slide shows Mon–Sun week-strips and no month grid', (
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
    expect(find.text('NEXT 6 MONTHS'), findsOneWidget);
    expect(find.text('NEXT 4 WEEKS'), findsNothing);
    expect(find.text('NEXT 7 DAYS'), findsNothing);
    expect(find.text('SEP – OCT'), findsNothing);
    expect(find.text('Mo'), findsNothing);
    expect(find.text('Tu'), findsNothing);
    expect(find.byKey(const ValueKey('look-ahead-week-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-14')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-19')),
      findsOneWidget,
    );
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('MON'), findsWidgets);
    expect(find.text('SUN'), findsWidgets);
    expect(find.textContaining('Bin night'), findsWidgets);
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
      dashboardGlanceColor({
        'assignedTo': 'tom',
        'category': 'work',
      }, palette: HubMemberPalette.fromMembers(members)),
      CalendarColors.work,
    );
    expect(
      dashboardGlanceColor({
        'assignedTo': 'maria',
        'category': 'general',
      }, palette: HubMemberPalette.fromMembers(members)),
      CalendarColors.personal,
    );
    expect(
      dashboardGlanceColor({
        'assignedTo': 'shared',
        'category': 'birthday',
      }, palette: HubMemberPalette.fromMembers(members)),
      CalendarColors.birthday,
    );
  });

  testWidgets(
    'empty look-ahead still draws Mon–Sun week-strips and a quiet hint',
    (tester) async {
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
      expect(find.text('NEXT 6 MONTHS'), findsOneWidget);
      expect(find.text('Free'), findsWidgets);
      expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('look-ahead-day-2026-09-14')),
        findsOneWidget,
      );
      expect(
        find.text('Quiet stretch — add plans from Calendar'),
        findsOneWidget,
      );
      expect(find.text('Quiet month — add plans from Calendar'), findsNothing);
    },
  );

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
    expect(find.text('NEXT 6 MONTHS'), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-14')),
      findsOneWidget,
    );
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Monday today keeps four Mon–Sun rows and highlights today', (
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
            events: const [],
            now: DateTime(2026, 9, 14),
            members: members,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('look-ahead-week-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-ahead-week-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-14')),
      findsOneWidget,
    );
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('look-ahead board scrolls to weeks about six months out', (
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

    final farDay = find.byKey(const ValueKey('look-ahead-day-2027-02-16'));
    expect(farDay, findsNothing);

    await tester.scrollUntilVisible(
      farDay,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('look-ahead-week-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(farDay, findsOneWidget);
    expect(find.textContaining('Half-term walk'), findsWidgets);

    final lastDay = dashboardLookAheadWeeks(now).last.last;
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(dashboardLookAheadDayKey(lastDay))),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('look-ahead-week-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(ValueKey(dashboardLookAheadDayKey(lastDay))),
      findsOneWidget,
    );
  });

  testWidgets('tapping a day opens a detail card and still notifies the host', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DateTime? tappedDay;
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1024, 768)),
            events: sampleEvents(),
            now: now,
            members: members,
            onDayTap: (day) => tappedDay = day,
            onCloseDayDetail: () => closed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-19')));
    await tester.pumpAndSettle();

    expect(tappedDay, DateTime(2026, 9, 19));
    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsOneWidget);
    expect(find.textContaining('Today'), findsWidgets);
    expect(find.text('Farmers market walk'), findsWidgets);
    expect(find.text('09:30'), findsWidgets);
    expect(closed, isFalse);

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-detail-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('tapping a free day shows an empty state; barrier dismisses', (
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

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-17')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-day-detail-empty')),
      findsOneWidget,
    );
    expect(find.text('Free day — nothing on the calendar'), findsOneWidget);
    expect(find.text('Nothing planned'), findsOneWidget);

    final barrier = tester.getRect(
      find.byKey(const ValueKey('look-ahead-day-detail-barrier')),
    );
    await tester.tapAt(Offset(barrier.left + 12, barrier.top + 12));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsNothing);
  });
}
