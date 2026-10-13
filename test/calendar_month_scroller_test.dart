import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_month_scroller.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  final now = DateTime(2026, 9, 19);
  final palette = HubMemberPalette.fromMembers(const [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ]);

  final events = [
    {
      'id': 'walk',
      'summary': 'Farmers market walk',
      'start': DateTime(2026, 9, 19, 9, 30),
      'end': DateTime(2026, 9, 19, 11),
      'assignedTo': 'shared',
      'category': 'general',
    },
  ];

  Future<void> pumpBoard(WidgetTester tester, {int? initialWeekCount}) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF6F3EE),
          body: CalendarMonthScroller(
            now: now,
            palette: palette,
            events: events,
            initialWeekCount: initialWeekCount ?? 30,
          ),
        ),
      ),
    );
  }

  test('calendar weeks stay continuous across the month, like look ahead', () {
    final weeks = dashboardLookAheadWeeks(now, weekCount: 20);
    final sections = dashboardLookAheadMonthSections(weeks, now: now);
    expect(sections.first.month, DateTime(2026, 9));
    expect(sections.first.label, 'SEPTEMBER');
    expect(sections.first.weeks.last.last, DateTime(2026, 9, 27));
    expect(sections[1].month, DateTime(2026, 10));
    expect(sections[1].weeks.first, [
      DateTime(2026, 9, 28),
      DateTime(2026, 9, 29),
      DateTime(2026, 9, 30),
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 4),
    ]);
  });

  testWidgets('calendar tab clones look-ahead day cells and month headers', (
    tester,
  ) async {
    await pumpBoard(tester);

    expect(find.text('LOOK AHEAD'), findsOneWidget);
    expect(find.text('WEEK BY WEEK'), findsOneWidget);
    expect(find.text('ONWARD'), findsNothing);
    expect(find.text('NEXT 6 MONTHS'), findsNothing);
    expect(find.text('SEPTEMBER'), findsOneWidget);
    expect(find.text('MON'), findsWidgets);
    expect(find.text('SUN'), findsWidgets);
    expect(
      find.byKey(const ValueKey('look-ahead-month-2026-09')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-19')),
      findsOneWidget,
    );
    expect(find.textContaining('Farmers market walk'), findsWidgets);
    expect(find.byType(CalendarSplitPill), findsWidgets);

    final october = find.text('OCTOBER');
    await tester.scrollUntilVisible(
      october,
      250,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('look-ahead-week-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(october, findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-month-2026-10')),
      findsOneWidget,
    );
    final gap = tester.getSize(
      find.byKey(const ValueKey('look-ahead-month-gap-2026-10')),
    );
    expect(gap.height, 22);
    final spanningWeek = find.byKey(const ValueKey('look-ahead-week-2'));
    expect(
      find.descendant(
        of: spanningWeek,
        matching: find.byKey(const ValueKey('look-ahead-day-2026-09-30')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: spanningWeek,
        matching: find.byKey(const ValueKey('look-ahead-day-2026-10-01')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a calendar day notifies the host and opens detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarMonthScroller(
            now: now,
            palette: palette,
            events: events,
            onDayTap: (day) => tapped = day,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-09-19')));
    await tester.pumpAndSettle();
    expect(tapped, DateTime(2026, 9, 19));
    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsOneWidget);
    expect(find.textContaining('Farmers market walk'), findsWidgets);
  });

  testWidgets('calendar board grows far into the future while scrolling', (
    tester,
  ) async {
    await pumpBoard(tester, initialWeekCount: 16);

    final farHeader = find.byKey(const ValueKey('look-ahead-month-2028-01'));
    expect(farHeader, findsNothing);

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('look-ahead-week-list')),
      matching: find.byType(Scrollable),
    );
    var found = false;
    for (var i = 0; i < 80; i++) {
      await tester.drag(scrollable, const Offset(0, -700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      if (farHeader.evaluate().isNotEmpty) {
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'lazy month list should grow into 2028');
    await tester.pumpAndSettle();

    expect(farHeader, findsOneWidget);
    expect(find.text('JANUARY 2028'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('look-ahead-month-gap-2028-01')),
      findsOneWidget,
    );
  });

  group('past weeks', () {
    test('reach back to the week holding the 1st, oldest first', () {
      final weeks = dashboardLookAheadPastWeeks(now, months: 2);
      expect(weeks.first.first, DateTime(2026, 6, 29));
      expect(weeks.first.contains(DateTime(2026, 7, 1)), isTrue);
      expect(weeks.last.first, DateTime(2026, 9, 7));
      expect(weeks.last.last, DateTime(2026, 9, 13));
      for (final week in weeks) {
        expect(week.length, 7);
        expect(week.first.weekday, DateTime.monday);
      }
      expect(dashboardLookAheadPastWeeks(now, months: 0), isEmpty);
    });

    test('sections follow the spanning-week rule and do not repeat '
        'the current month', () {
      final sections = dashboardLookAheadPastMonthSections(
        dashboardLookAheadPastWeeks(now, months: 2),
        now: now,
      );
      expect(sections.map((s) => s.label), [
        'JULY',
        'AUGUST',
        'EARLIER IN SEPTEMBER',
      ]);
      // Mon 27 Jul – Sun 2 Aug opens August, like the forward board.
      expect(sections[1].weeks.first.first, DateTime(2026, 7, 27));
      expect(sections[2].weeks.first.first, DateTime(2026, 8, 31));
    });

    test('loading further back leaves newer sections unchanged', () {
      List<String> describe(int months) => [
        for (final s in dashboardLookAheadPastMonthSections(
          dashboardLookAheadPastWeeks(now, months: months),
          now: now,
        ))
          '${s.label}:${s.weeks.first.first}:${s.weeks.length}',
      ];
      final shorter = describe(6);
      final longer = describe(18);
      expect(longer.sublist(longer.length - shorter.length), shorter);
    });

    test('a past year is labeled with the year', () {
      final sections = dashboardLookAheadPastMonthSections(
        dashboardLookAheadPastWeeks(now, months: 12),
        now: now,
      );
      expect(sections.first.label, 'SEPTEMBER 2025');
      expect(sections.any((s) => s.label == 'DECEMBER 2025'), isTrue);
    });
  });

  Finder weekScrollable() => find.descendant(
    of: find.byKey(const ValueKey('look-ahead-week-list')),
    matching: find.byType(Scrollable),
  );

  testWidgets('opens on the current week with past weeks above it', (
    tester,
  ) async {
    await pumpBoard(tester);
    await tester.pumpAndSettle();

    final list = tester.getRect(
      find.byKey(const ValueKey('look-ahead-week-list')),
    );
    final todayCell = tester.getRect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-19')),
    );
    // Current month header, then the current week at the top of the board.
    expect(find.text('SEPTEMBER'), findsOneWidget);
    expect(todayCell.top - list.top, lessThan(80));
    // Last week is not on screen yet.
    final lastWeek = find.byKey(const ValueKey('look-ahead-day-2026-09-12'));
    if (lastWeek.evaluate().isNotEmpty) {
      expect(tester.getRect(lastWeek).bottom, lessThanOrEqualTo(list.top));
    }
    final jump = find.byKey(DashboardCalendarOverviewSlide.jumpToTodayKey);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: jump, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
  });

  testWidgets('scrolling up shows past weeks and events, Today jumps back', (
    tester,
  ) async {
    final withPast = [
      ...events,
      {
        'id': 'gig',
        'summary': 'Old gig',
        'start': DateTime(2026, 8, 20, 19),
        'end': DateTime(2026, 8, 20, 23),
        'assignedTo': 'tom',
        'category': 'work',
        'status': 'tentative',
      },
    ];
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarMonthScroller(
            now: now,
            palette: palette,
            events: withPast,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('look-ahead-day-2026-08-20')),
      -250,
      scrollable: weekScrollable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('EARLIER IN SEPTEMBER'), findsOneWidget);
    expect(find.textContaining('Old gig'), findsWidgets);

    final jump = find.byKey(DashboardCalendarOverviewSlide.jumpToTodayKey);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: jump, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      1,
    );

    // A past day still opens the detail card.
    await tester.tap(find.byKey(const ValueKey('look-ahead-day-2026-08-20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('look-ahead-day-detail-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('look-ahead-day-detail')), findsNothing);

    await tester.tap(jump);
    await tester.pumpAndSettle();
    final list = tester.getRect(
      find.byKey(const ValueKey('look-ahead-week-list')),
    );
    final todayCell = tester.getRect(
      find.byKey(const ValueKey('look-ahead-day-2026-09-19')),
    );
    expect(todayCell.top - list.top, lessThan(80));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: jump, matching: find.byType(AnimatedOpacity)),
          )
          .opacity,
      0,
    );
  });

  testWidgets('keeps loading further back than the first year', (tester) async {
    await pumpBoard(tester);
    await tester.pumpAndSettle();
    final farBack = find.byKey(const ValueKey('look-ahead-past-month-2025-01'));
    var found = false;
    for (var i = 0; i < 120; i++) {
      await tester.drag(weekScrollable(), const Offset(0, 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      if (farBack.evaluate().isNotEmpty) {
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'past weeks should load past 12 months');
    await tester.pumpAndSettle();
    expect(find.text('JANUARY 2025'), findsOneWidget);
  });

  testWidgets('the dashboard LOOK AHEAD stays forward-only', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1280, 800)),
            events: events,
            now: now,
            palette: palette,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('look-ahead-week-list')),
        matching: find.byType(CustomScrollView),
      ),
      findsNothing,
    );
    expect(
      find.byKey(DashboardCalendarOverviewSlide.jumpToTodayKey),
      findsNothing,
    );
    expect(find.textContaining('EARLIER IN'), findsNothing);
  });
}
