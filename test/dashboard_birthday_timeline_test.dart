import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/dashboard/dashboard_birthday_timeline.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

final _today = DateTime(2026, 10, 1); // Thursday
DateTime _in(int d) => DateTime(_today.year, _today.month, _today.day + d);

List<DashboardBirthday> _sample() => [
  DashboardBirthday(id: 'tom', name: 'Tom', date: _in(-2), turning: 48),
  DashboardBirthday(id: 'maria', name: 'Maria', date: _in(2), turning: 34),
  DashboardBirthday(id: 'nan', name: 'Nan', date: _in(9), turning: 81),
  DashboardBirthday(id: 'jake', name: 'Jake', date: _in(12)),
  DashboardBirthday(
    id: 'sophie',
    name: 'Sophie Carter',
    date: _in(23),
    turning: 30,
  ),
];

Map<String, dynamic> _event(String summary, DateTime start, {String? id}) => {
  'id': id ?? summary,
  'summary': summary,
  'start': start,
  'category': 'birthday',
};

void _expectInside(WidgetTester tester, Finder inner, Finder outer) {
  final innerRect = tester.getRect(inner);
  final outerRect = tester.getRect(outer);
  expect(
    innerRect.top,
    greaterThanOrEqualTo(outerRect.top - 0.5),
    reason: '$inner top ${innerRect.top} is above $outer ${outerRect.top}',
  );
  expect(
    innerRect.bottom,
    lessThanOrEqualTo(outerRect.bottom + 0.5),
    reason:
        '$inner bottom ${innerRect.bottom} overflows $outer ${outerRect.bottom}',
  );
  expect(
    innerRect.left,
    greaterThanOrEqualTo(outerRect.left - 0.5),
    reason: '$inner left ${innerRect.left} is left of $outer ${outerRect.left}',
  );
  expect(
    innerRect.right,
    lessThanOrEqualTo(outerRect.right + 0.5),
    reason:
        '$inner right ${innerRect.right} overflows $outer ${outerRect.right}',
  );
  expect(innerRect.height, greaterThan(6), reason: '$inner is too short');
}

void main() {
  group('birthday data', () {
    test('splits the projected "Name (age)" title', () {
      final a = dashboardSplitBirthdayTitle('Maria (34)');
      expect(a.name, 'Maria');
      expect(a.turning, 34);
      final b = dashboardSplitBirthdayTitle('Jake');
      expect(b.name, 'Jake');
      expect(b.turning, isNull);
    });

    test('upcoming list: birthdays only, soonest first, no duplicates', () {
      final list = dashboardUpcomingBirthdays(
        [
          _event('Nan (81)', _in(9)),
          _event('Maria (34)', _in(2)),
          _event('Maria (34)', _in(2), id: 'google-copy'),
          _event('Yesterday', _in(-1)),
          {..._event('Dentist', _in(3)), 'category': 'general'},
          {
            ..._event('Dad (66)', _in(20)),
            'birthdayName': 'Dad',
            'turning': 66,
          },
        ],
        now: _today.add(const Duration(hours: 9)),
        members: const [
          {'uid': 'm', 'name': 'Maria Lopez', 'photoURL': 'https://x/m.jpg'},
        ],
      );
      expect(list.map((b) => b.name), ['Maria', 'Nan', 'Dad']);
      expect(list.first.turning, 34);
      expect(list.first.photoUrl, 'https://x/m.jpg');
      expect(list.first.daysFrom(_today), 2);
      expect(list[2].turning, 66);
    });

    test('keeps ~3 months, at least 3, at most maxCount', () {
      final events = [
        for (final d in [5, 40, 150, 200, 300]) _event('P$d', _in(d)),
      ];
      final few = dashboardUpcomingBirthdays(events, now: _today);
      expect(few.map((b) => b.name), ['P5', 'P40', 'P150']);

      final many = [for (var d = 1; d <= 20; d++) _event('Q$d', _in(d))];
      expect(
        dashboardUpcomingBirthdays(many, now: _today, maxCount: 8).length,
        8,
      );
      expect(dashboardUpcomingBirthdays(const [], now: _today), isEmpty);
    });

    test('days count is calendar days across the clock change', () {
      final b = DashboardBirthday(
        id: 'x',
        name: 'X',
        date: DateTime(2026, 10, 27),
      );
      expect(b.daysFrom(DateTime(2026, 10, 24)), 3);
    });
  });

  group('four-week look-ahead window', () {
    test('is the current week plus the next three, Monday to Sunday', () {
      final weeks = dashboardLookAheadWeeks(
        _today,
        weekCount: dashboardBirthdayLookAheadWeekCount,
      );
      expect(weeks, hasLength(4));
      expect(weeks.first.first, DateTime(2026, 9, 28));
      expect(weeks.last.last, DateTime(2026, 10, 25));
      expect(weeks.first.every((d) => d.weekday >= DateTime.monday), isTrue);
    });

    test('includes earlier this week and drops dates after the board', () {
      final list = dashboardBirthdaysInLookAhead([
        _event('Tom (48)', _in(-2)), // Tue 29 Sep, still on the board
        _event('Too early', _in(-5)), // Fri 26 Sep, previous week
        _event('Maria (34)', _in(2)),
        _event('Late', _in(30)), // after 25 Oct
        {..._event('Dentist', _in(3)), 'category': 'general'},
        _event('Maria (34)', _in(2), id: 'google-copy'),
      ], now: _today.add(const Duration(hours: 9)));
      expect(list.map((b) => b.name), ['Tom', 'Maria']);
      expect(list.first.daysFrom(_today), -2);
    });

    test('yearly recurrence: January birthdays appear from mid-December', () {
      final now = DateTime(2026, 12, 16); // Wednesday; board ends 10 Jan 2027
      final list = dashboardBirthdaysInLookAhead([
        _event('New Year baby (1)', DateTime(2027, 1, 3)),
        _event('Too late', DateTime(2027, 1, 20)),
      ], now: now);
      expect(list.map((b) => b.name), ['New Year baby']);
      expect(list.single.date, DateTime(2027, 1, 3));
      expect(list.single.turning, 1);
    });

    test('29 Feb is shown on 29 Feb in a leap year, and 1 March otherwise', () {
      // Dart (and the hub projector) overflow 29 Feb in a common year to 1 Mar.
      expect(DateTime(2028, 2, 29), DateTime(2028, 2, 29));
      expect(DateTime(2027, 2, 29), DateTime(2027, 3, 1));

      final leap = dashboardBirthdaysInLookAhead([
        _event('Leap (8)', DateTime(2028, 2, 29)),
      ], now: DateTime(2028, 2, 26));
      expect(leap, hasLength(1));
      expect(leap.single.date, DateTime(2028, 2, 29));

      final common = dashboardBirthdaysInLookAhead([
        _event('Leap (9)', DateTime(2027, 2, 29)),
      ], now: DateTime(2027, 2, 26));
      expect(common, hasLength(1));
      expect(common.single.date, DateTime(2027, 3, 1));
      expect(common.single.turning, 9);
    });

    test(
      'month sections label October when the first week starts in September',
      () {
        final weeks = dashboardLookAheadWeeks(
          _today,
          weekCount: dashboardBirthdayLookAheadWeekCount,
        );
        final sections = dashboardLookAheadMonthSections(weeks, now: _today);
        // Today is 1 Oct, so the first header stays on October even though
        // the row still holds 28–30 Sep.
        expect(sections.first.label, 'OCTOBER');
        expect(sections, hasLength(1));
      },
    );
  });

  group('birthday look-ahead widget', () {
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      List<DashboardBirthday>? birthdays,
      DateTime? today,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardBirthdaysSlide(
              metrics: DashboardMetrics(size),
              birthdays: birthdays ?? _sample(),
              today: today ?? _today,
            ),
          ),
        ),
      );
    }

    testWidgets('tablet shows a four-week grid with cakes, names and ages', (
      tester,
    ) async {
      await pump(tester, const Size(1280, 800));
      expect(find.byKey(const ValueKey('birthday-lookahead')), findsOneWidget);
      expect(find.text('BIRTHDAYS'), findsOneWidget);
      expect(find.text('NEXT 4 WEEKS'), findsNothing);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('OCTOBER'), findsOneWidget);
      expect(find.byType(BirthdayCakeMarker), findsNWidgets(5));
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Turns 34'), findsOneWidget);
      expect(find.text('Sophie'), findsOneWidget);
      expect(find.text('Jake'), findsOneWidget);
      // Age unknown: name only, no Turns label beside Jake.
      expect(find.text('Turns 30'), findsOneWidget);
      expect(
        find.byKey(ValueKey(dashboardBirthdayDayKey(_today))),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('birthday-week-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('birthday-week-3')), findsOneWidget);
      // Earlier this week is still on the board, greyed.
      expect(
        find.byKey(ValueKey(dashboardBirthdayPastDimKey(_in(-2)))),
        findsOneWidget,
      );
      expect(find.text('Tom'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone keeps cakes readable and past days greyed', (
      tester,
    ) async {
      await pump(tester, const Size(390, 844));
      expect(find.byType(BirthdayCakeMarker), findsNWidgets(5));
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('34'), findsOneWidget); // compact age label
      expect(find.text('Turns 34'), findsNothing);
      expect(
        find.byKey(
          ValueKey(dashboardBirthdayPastDimKey(DateTime(2026, 9, 30))),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty window still shows the grid with a quiet hint', (
      tester,
    ) async {
      await pump(tester, const Size(1280, 800), birthdays: const []);
      expect(
        find.byKey(const ValueKey('birthday-lookahead-empty')),
        findsOneWidget,
      );
      expect(find.byType(BirthdayCakeMarker), findsNothing);
      expect(find.byKey(const ValueKey('birthday-week-0')), findsOneWidget);
    });

    testWidgets('greying advances with the calendar day at midnight', (
      tester,
    ) async {
      // 30 Sep 23:00 — 30 Sep is still today, not greyed.
      await pump(
        tester,
        const Size(1280, 800),
        today: DateTime(2026, 9, 30, 23),
        birthdays: [
          DashboardBirthday(id: 'a', name: 'Ann', date: DateTime(2026, 9, 30)),
        ],
      );
      expect(
        find.byKey(
          ValueKey(dashboardBirthdayPastDimKey(DateTime(2026, 9, 30))),
        ),
        findsNothing,
      );
      expect(find.text('TODAY'), findsOneWidget);

      // Midnight rolls the calendar day: 30 Sep is now past.
      await pump(
        tester,
        const Size(1280, 800),
        today: DateTime(2026, 10, 1),
        birthdays: [
          DashboardBirthday(id: 'a', name: 'Ann', date: DateTime(2026, 9, 30)),
        ],
      );
      expect(
        find.byKey(
          ValueKey(dashboardBirthdayPastDimKey(DateTime(2026, 9, 30))),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a month header appears when the board crosses into November', (
      tester,
    ) async {
      // Thursday 15 Oct: board is Mon 12 Oct – Sun 8 Nov.
      await pump(
        tester,
        const Size(1280, 800),
        today: DateTime(2026, 10, 15),
        birthdays: const [],
      );
      expect(find.text('OCTOBER'), findsOneWidget);
      expect(find.text('NOVEMBER'), findsOneWidget);
    });

    test('cake age labels', () {
      expect(BirthdayCakeMarker.ageLabel(34, compact: false), 'Turns 34');
      expect(BirthdayCakeMarker.ageLabel(34, compact: true), '34');
    });

    testWidgets('tablet cells show the cake, name and age without clipping', (
      tester,
    ) async {
      // 23 Nov 2026 is a Monday, so the live four-week board (23 Nov–20 Dec)
      // crosses into December and is the tighter two-header layout Tom
      // photographed on the wall tablet.
      const size = Size(1280, 800);
      final today = DateTime(2026, 11, 23);
      final friday = DateTime(2026, 11, 27);
      await pump(
        tester,
        size,
        today: today,
        birthdays: [
          DashboardBirthday(
            id: 'maria',
            name: 'Maria',
            date: friday,
            turning: 34,
          ),
        ],
      );

      final cell = find.byKey(ValueKey(dashboardBirthdayDayKey(friday)));
      expect(cell, findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('Turns 34'), findsOneWidget);
      final cake = find.descendant(
        of: cell,
        matching: find.byIcon(Icons.cake_rounded),
      );
      expect(cake, findsOneWidget);
      _expectInside(tester, find.text('Maria'), cell);
      _expectInside(tester, find.text('Turns 34'), cell);
      _expectInside(tester, cake, cell);
      expect(tester.takeException(), isNull);

      final slide = tester.getRect(find.byType(DashboardBirthdaysSlide));
      expect(
        tester.getRect(find.text('BIRTHDAYS')).left,
        greaterThanOrEqualTo(slide.left - 0.5),
      );
      final sunday = DateTime(2026, 11, 29);
      _expectInside(
        tester,
        find.byKey(ValueKey(dashboardBirthdayDayKey(sunday))),
        find.byType(DashboardBirthdaysSlide),
      );
    });

    testWidgets('phone also keeps the name visible in the cell', (
      tester,
    ) async {
      const size = Size(390, 844);
      final today = DateTime(2026, 11, 23);
      final friday = DateTime(2026, 11, 27);
      await pump(
        tester,
        size,
        today: today,
        birthdays: [
          DashboardBirthday(
            id: 'maria',
            name: 'Maria',
            date: friday,
            turning: 34,
          ),
        ],
      );
      final cell = find.byKey(ValueKey(dashboardBirthdayDayKey(friday)));
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('34'), findsOneWidget);
      final cake = find.descendant(
        of: cell,
        matching: find.byIcon(Icons.cake_rounded),
      );
      expect(cake, findsOneWidget);
      _expectInside(tester, find.text('Maria'), cell);
      _expectInside(tester, find.text('34'), cell);
      _expectInside(tester, cake, cell);
      expect(tester.takeException(), isNull);
    });

    testWidgets('two birthdays on one day show the second or a +1 cue', (
      tester,
    ) async {
      final day = _in(2);
      await pump(
        tester,
        const Size(1280, 800),
        birthdays: [
          DashboardBirthday(id: 'a', name: 'Maria', date: day, turning: 34),
          DashboardBirthday(id: 'b', name: 'Dad', date: day, turning: 66),
        ],
      );
      expect(find.text('Maria'), findsOneWidget);
      final second = find.text('Dad');
      final more = find.text('+1');
      expect(
        second.evaluate().isNotEmpty || more.evaluate().isNotEmpty,
        isTrue,
        reason: 'the cell should show Dad in full, or +1 if both do not fit',
      );
      final cell = find.byKey(ValueKey(dashboardBirthdayDayKey(day)));
      _expectInside(tester, find.text('Maria'), cell);
      if (second.evaluate().isNotEmpty) {
        _expectInside(tester, second, cell);
      } else {
        _expectInside(tester, more, cell);
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('dashboard LOOK AHEAD can drop its title row', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1024, 768)),
            events: const [],
            now: _today,
            showHeader: false,
          ),
        ),
      ),
    );
    expect(find.text('LOOK AHEAD'), findsNothing);
    expect(find.text('NEXT 6 MONTHS'), findsOneWidget);
  });
}
