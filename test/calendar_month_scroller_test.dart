import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_month_scroller.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

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
    expect(find.text('ONWARD'), findsOneWidget);
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
}
