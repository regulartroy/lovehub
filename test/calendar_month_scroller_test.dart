import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_month_scroller.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

void main() {
  final now = DateTime(2026, 9, 19);
  final palette = HubMemberPalette.fromMembers(const [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ]);

  List<EventModel> eventsForDay(DateTime day) {
    if (DateUtils.isSameDay(day, now)) {
      return [
        EventModel(
          id: 'walk',
          summary: 'Farmers market walk',
          start: DateTime(2026, 9, 19, 9, 30),
          end: DateTime(2026, 9, 19, 11),
          assignedTo: 'shared',
        ),
      ];
    }
    return const [];
  }

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
            eventsForDay: eventsForDay,
            initialWeekCount: initialWeekCount ?? 30,
          ),
        ),
      ),
    );
  }

  test('calendar board starts at the Monday of the current month 1st', () {
    expect(calendarScrollerStartMonday(now), DateTime(2026, 8, 31));
    expect(
      calendarScrollerStartMonday(DateTime(2026, 9, 1)),
      DateTime(2026, 8, 31),
    );
    expect(
      calendarScrollerStartMonday(DateTime(2026, 10, 1)),
      DateTime(2026, 9, 28),
    );
  });

  test('calendar months use the same spanning-week header rule', () {
    final start = calendarScrollerStartMonday(now);
    final weeks = List<List<DateTime>>.generate(
      20,
      (index) => calendarScrollerWeekAt(start, index),
    );
    final sections = dashboardLookAheadMonthSections(weeks, now: now);
    expect(sections.first.month, DateTime(2026, 9));
    expect(sections.first.label, 'SEPTEMBER');
    expect(sections[1].month, DateTime(2026, 10));
    expect(sections[1].weeks.first.first, DateTime(2026, 9, 28));
  });

  testWidgets('calendar board shows month headers, gaps, and weekday strip', (
    tester,
  ) async {
    await pumpBoard(tester);

    expect(find.text('MON'), findsWidgets);
    expect(find.text('SUN'), findsWidgets);
    expect(find.text('SEPTEMBER'), findsOneWidget);
    expect(find.text('OCTOBER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-month-2026-09')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-month-2026-10')),
      findsOneWidget,
    );

    final gap = tester.getSize(
      find.byKey(const ValueKey('calendar-month-gap-2026-10')),
    );
    expect(gap.height, 20);

    expect(
      find.byKey(const ValueKey('calendar-day-2026-09-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-day-2026-09-19')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a calendar day notifies the host', (tester) async {
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
            eventsForDay: eventsForDay,
            onDayTap: (day) => tapped = day,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-09-19')));
    await tester.pumpAndSettle();
    expect(tapped, DateTime(2026, 9, 19));
  });

  testWidgets('calendar board grows far into the future while scrolling', (
    tester,
  ) async {
    await pumpBoard(tester, initialWeekCount: 16);

    final farHeader = find.byKey(const ValueKey('calendar-month-2028-01'));
    expect(farHeader, findsNothing);

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('calendar-month-list')),
      matching: find.byType(Scrollable),
    );
    var found = false;
    for (var i = 0; i < 60; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
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
      find.byKey(const ValueKey('calendar-month-gap-2028-01')),
      findsOneWidget,
    );
  });
}
