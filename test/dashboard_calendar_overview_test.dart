import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
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

  Map<String, dynamic> timedEvent(
    String summary,
    DateTime start,
    DateTime end,
  ) {
    return {
      'summary': summary,
      'start': start,
      'end': end,
      'allDay': false,
      'category': 'general',
      'assignedTo': 'shared',
    };
  }

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

  test('overnight events ending before 06:00 stay on the start day', () {
    final club = timedEvent(
      'Club night',
      DateTime(2026, 9, 23, 23),
      DateTime(2026, 9, 24, 4),
    );

    expect(dashboardEventOverlapsDay(club, DateTime(2026, 9, 23)), isTrue);
    expect(dashboardEventOverlapsDay(club, DateTime(2026, 9, 24)), isFalse);
    expect(
      dashboardEventsOnDay([
        club,
      ], DateTime(2026, 9, 23)).map((event) => event['summary']),
      ['Club night'],
    );
    expect(dashboardEventsOnDay([club], DateTime(2026, 9, 24)), isEmpty);

    final endsAtCutoff = timedEvent(
      'Until six',
      DateTime(2026, 9, 23, 23),
      DateTime(2026, 9, 24, dashboardOverviewOvernightCutoffHour),
    );
    expect(
      dashboardEventOverlapsDay(endsAtCutoff, DateTime(2026, 9, 24)),
      isTrue,
    );

    final endsJustBefore = timedEvent(
      'Just before six',
      DateTime(2026, 9, 23, 22),
      DateTime(2026, 9, 24, 5, 59),
    );
    expect(
      dashboardEventOverlapsDay(endsJustBefore, DateTime(2026, 9, 24)),
      isFalse,
    );

    final earlySameDay = timedEvent(
      'Early set-up',
      DateTime(2026, 9, 24, 1),
      DateTime(2026, 9, 24, 3),
    );
    expect(
      dashboardEventOverlapsDay(earlySameDay, DateTime(2026, 9, 24)),
      isTrue,
    );

    final trip = timedEvent(
      'Long weekend',
      DateTime(2026, 9, 25, 18),
      DateTime(2026, 9, 27, 3),
    );
    expect(dashboardEventOverlapsDay(trip, DateTime(2026, 9, 25)), isTrue);
    expect(dashboardEventOverlapsDay(trip, DateTime(2026, 9, 26)), isTrue);
    expect(dashboardEventOverlapsDay(trip, DateTime(2026, 9, 27)), isFalse);
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

  test('month labels stay short, with a year after New Year', () {
    expect(
      dashboardLookAheadMonthLabel(DateTime(2026, 10), DateTime(2026, 9, 19)),
      'OCTOBER',
    );
    expect(
      dashboardLookAheadMonthLabel(DateTime(2026, 9), DateTime(2026, 9, 19)),
      'SEPTEMBER',
    );
    expect(
      dashboardLookAheadMonthLabel(DateTime(2027, 1), DateTime(2026, 9, 19)),
      'JANUARY 2027',
    );
  });

  test('month sections header a spanning week when any day is a new month', () {
    final weeks = dashboardLookAheadWeeks(now);
    final sections = dashboardLookAheadMonthSections(weeks, now: now);

    expect(sections.first.month, DateTime(2026, 9));
    expect(sections.first.label, 'SEPTEMBER');
    expect(sections.first.weeks, hasLength(2));
    expect(sections.first.weeks.first.first, DateTime(2026, 9, 14));
    expect(sections.first.weeks.last.last, DateTime(2026, 9, 27));

    expect(sections[1].month, DateTime(2026, 10));
    expect(sections[1].label, 'OCTOBER');
    // Mon 28 Sep–Sun 4 Oct belongs to October because 1 Oct lands in the row.
    expect(sections[1].weeks.first.first, DateTime(2026, 9, 28));
    expect(sections[1].weeks.first.last, DateTime(2026, 10, 4));

    final january = sections.firstWhere(
      (section) => section.month.year == 2027,
    );
    expect(january.month, DateTime(2027, 1));
    expect(january.label, 'JANUARY 2027');
    expect(january.weeks.first.first, DateTime(2026, 12, 28));
    expect(january.weeks.first.last, DateTime(2027, 1, 3));
  });

  test('first week is headed with today even when the row spans months', () {
    final lateDecember = DateTime(2026, 12, 30);
    final sections = dashboardLookAheadMonthSections(
      dashboardLookAheadWeeks(lateDecember),
      now: lateDecember,
    );

    expect(sections.first.month, DateTime(2026, 12));
    expect(sections.first.label, 'DECEMBER');
    expect(sections.first.weeks.first.first, DateTime(2026, 12, 28));
    expect(sections.first.weeks.first.last, DateTime(2027, 1, 3));
    expect(sections[1].month, DateTime(2027, 1));
    expect(sections[1].label, 'JANUARY 2027');
    expect(sections[1].weeks.first.first, DateTime(2027, 1, 4));

    final earlyJanuary = DateTime(2027, 1, 2);
    final januarySections = dashboardLookAheadMonthSections(
      dashboardLookAheadWeeks(earlyJanuary),
      now: earlyJanuary,
    );
    expect(januarySections.first.month, DateTime(2027, 1));
    expect(januarySections.first.label, 'JANUARY');
    expect(januarySections.first.weeks.first.first, DateTime(2026, 12, 28));
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
    expect(find.text('SEPTEMBER'), findsOneWidget);
    expect(find.text('OCTOBER'), findsOneWidget);
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

  testWidgets('look-ahead shows month headers and a gap between months', (
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

    expect(
      find.byKey(const ValueKey('look-ahead-month-2026-09')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('look-ahead-month-2026-10')),
      findsOneWidget,
    );
    expect(find.text('SEPTEMBER'), findsOneWidget);
    expect(find.text('OCTOBER'), findsOneWidget);

    final monthGap = tester.getSize(
      find.byKey(const ValueKey('look-ahead-month-gap-2026-10')),
    );
    expect(monthGap.height, 22);

    final septemberWeek = tester.getRect(
      find.byKey(const ValueKey('look-ahead-week-1')),
    );
    final octoberWeek = tester.getRect(
      find.byKey(const ValueKey('look-ahead-week-2')),
    );
    final sameMonthWeek = tester.getRect(
      find.byKey(const ValueKey('look-ahead-week-0')),
    );
    final inMonthGap = septemberWeek.top - sameMonthWeek.bottom;
    final acrossMonthGap = octoberWeek.top - septemberWeek.bottom;
    expect(inMonthGap, 10);
    expect(acrossMonthGap, greaterThan(inMonthGap));
    expect(acrossMonthGap, greaterThanOrEqualTo(22));
  });

  testWidgets('scrolling into a later month keeps the header for orientation', (
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

    final januaryHeader = find.byKey(
      const ValueKey('look-ahead-month-2027-01'),
    );
    expect(januaryHeader, findsNothing);

    await tester.scrollUntilVisible(
      januaryHeader,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('look-ahead-week-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(januaryHeader, findsOneWidget);
    expect(find.text('JANUARY 2027'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-month-gap-2027-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('look-ahead-day-2027-01-01')),
      findsOneWidget,
    );
  });

  List<Map<String, dynamic>> tentativeSunday() {
    return [
      {
        'id': 'c2-rota:2026-09-20',
        'summary': 'C2 Maybe',
        'start': DateTime(2026, 9, 20, 15),
        'end': DateTime(2026, 9, 20, 23, 30),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'tom',
        'status': 'tentative',
      },
      {
        'id': 'dinner',
        'summary': 'Dinner',
        'start': DateTime(2026, 9, 20, 19),
        'end': DateTime(2026, 9, 20, 21),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
        'status': 'confirmed',
      },
    ];
  }

  Future<void> pumpLookAhead(
    WidgetTester tester, {
    required List<Map<String, dynamic>> events,
    Future<void> Function(Map<String, dynamic> event)? onConfirmTentative,
  }) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1024, 768)),
            events: events,
            now: now,
            members: members,
            onConfirmTentative: onConfirmTentative,
          ),
        ),
      ),
    );
  }

  testWidgets('look-ahead day detail can confirm a tentative shift', (
    tester,
  ) async {
    String? confirmedId;
    await pumpLookAhead(
      tester,
      events: tentativeSunday(),
      onConfirmTentative: (event) async {
        confirmedId = event['id'] as String;
      },
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-20')));
    await tester.pumpAndSettle();

    expect(find.text("Confirm I'm working this"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tentative-event-confirm-dinner')),
      findsNothing,
    );
    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsWidgets);

    final muted = tester.widget<ColoredBox>(
      find.descendant(
        of: find.ancestor(
          of: find.text('C2 Maybe'),
          matching: find.byType(CalendarSplitPill),
        ),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    expect(muted.color, isNot(CalendarColors.work));

    await tester.tap(
      find.byKey(const ValueKey('tentative-event-confirm-c2-rota:2026-09-20')),
    );
    await tester.pumpAndSettle();

    expect(confirmedId, 'c2-rota:2026-09-20');
    expect(find.text('C2 Maybe'), findsWidgets);
    expect(find.text("Confirm I'm working this"), findsNothing);
    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsNothing);

    final solid = tester.widget<ColoredBox>(
      find.descendant(
        of: find.ancestor(
          of: find.text('C2 Maybe'),
          matching: find.byType(CalendarSplitPill),
        ),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    expect(solid.color, CalendarColors.work);
  });

  testWidgets('keep tentative dismisses the prompt and leaves the shift', (
    tester,
  ) async {
    var confirmed = 0;
    await pumpLookAhead(
      tester,
      events: tentativeSunday(),
      onConfirmTentative: (_) async {
        confirmed += 1;
      },
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-20')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tentative-event-keep-c2-rota:2026-09-20')),
    );
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(find.text('C2 Maybe'), findsWidgets);
    expect(find.text("Confirm I'm working this"), findsNothing);
    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsWidgets);

    await tester.tap(find.text('C2 Maybe'));
    await tester.pumpAndSettle();

    expect(find.text("Confirm I'm working this"), findsOneWidget);
    expect(confirmed, 0);
  });

  testWidgets('a failed confirm restores the tentative chip', (tester) async {
    await pumpLookAhead(
      tester,
      events: tentativeSunday(),
      onConfirmTentative: (_) async {
        throw StateError('offline');
      },
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-20')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('tentative-event-confirm-c2-rota:2026-09-20')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsWidgets);
    expect(find.text("Confirm I'm working this"), findsOneWidget);
    expect(find.textContaining('still tentative'), findsOneWidget);
  });

  List<Map<String, dynamic>> eventsOn(
    DateTime day,
    List<String> titles, {
    int startHour = 9,
  }) {
    return [
      for (var i = 0; i < titles.length; i++)
        timedEvent(
          titles[i],
          DateTime(day.year, day.month, day.day, startHour + i),
          DateTime(day.year, day.month, day.day, startHour + i, 30),
        ),
    ];
  }

  void expectChipsInsideDay(WidgetTester tester, Finder day, int count) {
    final cell = tester.getRect(day);
    final chips = find.descendant(
      of: day,
      matching: find.byType(CalendarSplitPill),
    );
    expect(chips, findsNWidgets(count));
    expect(
      find.descendant(of: day, matching: find.textContaining('events')),
      findsNothing,
    );
    expect(
      find.descendant(of: day, matching: find.textContaining('plans')),
      findsNothing,
    );
    for (final element in chips.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.top, greaterThanOrEqualTo(cell.top));
      expect(rect.bottom, lessThanOrEqualTo(cell.bottom + 0.5));
      expect(rect.left, greaterThanOrEqualTo(cell.left));
      expect(rect.right, lessThanOrEqualTo(cell.right + 0.5));
    }
  }

  testWidgets('three events render as chips and four collapse to a count', (
    tester,
  ) async {
    final threeDay = DateTime(2026, 9, 15);
    final fourDay = DateTime(2026, 9, 16);
    final events = [
      ...eventsOn(threeDay, ['Alpha', 'Bravo', 'Charlie']),
      ...eventsOn(fourDay, ['Delta', 'Echo', 'Foxtrot', 'Golf']),
    ];

    await pumpLookAhead(tester, events: events);

    final three = find.byKey(ValueKey(dashboardLookAheadDayKey(threeDay)));
    final four = find.byKey(ValueKey(dashboardLookAheadDayKey(fourDay)));
    expectChipsInsideDay(tester, three, 3);
    expect(
      find.descendant(of: three, matching: find.textContaining('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: three, matching: find.textContaining('Bravo')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: three, matching: find.textContaining('Charlie')),
      findsOneWidget,
    );
    expect(find.text('3 events'), findsNothing);
    expect(find.text('3 plans'), findsNothing);

    expect(
      find.descendant(of: four, matching: find.byType(CalendarSplitPill)),
      findsNothing,
    );
    expect(
      find.descendant(of: four, matching: find.text('4 events')),
      findsOneWidget,
    );
    expect(find.textContaining('Delta'), findsNothing);
    expect(find.textContaining('Golf'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone look-ahead still fits three chips in the day cell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final day = DateTime(2026, 9, 15);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(390, 844)),
            events: eventsOn(day, ['Alpha', 'Bravo', 'Charlie']),
            now: now,
            members: members,
          ),
        ),
      ),
    );

    expectChipsInsideDay(
      tester,
      find.byKey(ValueKey(dashboardLookAheadDayKey(day))),
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('overnight club night is only on the start day in look-ahead', (
    tester,
  ) async {
    final startDay = DateTime(2026, 9, 19);
    final nextMorning = DateTime(2026, 9, 20);
    await pumpLookAhead(
      tester,
      events: [
        timedEvent(
          'Club night',
          DateTime(2026, 9, 19, 23),
          DateTime(2026, 9, 20, 4),
        ),
      ],
    );

    final start = find.byKey(ValueKey(dashboardLookAheadDayKey(startDay)));
    final morning = find.byKey(ValueKey(dashboardLookAheadDayKey(nextMorning)));
    expect(
      find.descendant(of: start, matching: find.textContaining('Club night')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: morning, matching: find.textContaining('Club night')),
      findsNothing,
    );
    expect(
      find.descendant(of: morning, matching: find.text('Free')),
      findsOneWidget,
    );

    await tester.tap(start);
    await tester.pumpAndSettle();
    final detail = find.byKey(const ValueKey('look-ahead-day-detail'));
    expect(
      find.descendant(of: detail, matching: find.textContaining('Club night')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('23:00')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-detail-close')));
    await tester.pumpAndSettle();

    await tester.tap(morning);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('look-ahead-day-detail')),
        matching: find.textContaining('Club night'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('look-ahead-day-detail-empty')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
