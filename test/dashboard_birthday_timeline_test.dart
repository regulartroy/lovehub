import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/dashboard/dashboard_birthday_timeline.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

final _today = DateTime(2026, 10, 1);
DateTime _in(int d) => DateTime(_today.year, _today.month, _today.day + d);

List<DashboardBirthday> _sample(int n) => [
  for (var i = 0; i < n; i++)
    DashboardBirthday(
      id: 'b$i',
      name: 'Person $i',
      date: _in([2, 9, 12, 23, 37, 51, 64, 83][i % 8]),
      turning: 30 + i,
    ),
];

Map<String, dynamic> _event(String summary, DateTime start, {String? id}) => {
  'id': id ?? summary,
  'summary': summary,
  'start': start,
  'category': 'birthday',
};

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

  group('timeline layout', () {
    for (final compact in [false, true]) {
      final size = compact ? const Size(350, 640) : const Size(1200, 560);
      test('${compact ? 'phone' : 'tablet'}: next birthday is the big front '
          'tile, later ones step up, right, and smaller', () {
        final layout = BirthdayTimelineLayout.compute(
          size: size,
          birthdays: _sample(8),
          today: _today,
          compact: compact,
        );
        final front = layout.tiles.reversed.toList();
        expect(front.first.birthday.id, 'b0');
        for (var i = 1; i < front.length; i++) {
          final prev = front[i - 1];
          final cur = front[i];
          expect(cur.scale, lessThan(prev.scale));
          expect(cur.center.dx, greaterThan(prev.center.dx));
          final prevTop = prev.center.dy - layout.baseTile * prev.scale / 2;
          final curTop = cur.center.dy - layout.baseTile * cur.scale / 2;
          expect(
            curTop,
            lessThan(prevTop),
            reason: 'top edge ${cur.birthday.id}',
          );
        }
        for (final p in layout.tiles) {
          final half = layout.baseTile * p.scale / 2;
          expect(p.center.dx - half, greaterThanOrEqualTo(-1));
          expect(p.center.dx + half, lessThanOrEqualTo(size.width + 1));
          expect(p.center.dy + half, lessThanOrEqualTo(size.height + 1));
          expect(p.center.dy - half, greaterThanOrEqualTo(0));
        }
      });
    }

    test('weekly ticks for a short range, fortnightly for a long one', () {
      final short = BirthdayTimelineLayout.compute(
        size: const Size(1200, 560),
        birthdays: _sample(3),
        today: _today,
        compact: false,
      );
      expect(short.tickDays, 7);
      final long = BirthdayTimelineLayout.compute(
        size: const Size(1200, 560),
        birthdays: _sample(8),
        today: _today,
        compact: false,
      );
      expect(long.tickDays, 14);
      expect(long.ticks.first.label, 'TODAY');
      expect(long.ticks.where((t) => t.label == 'NOV'), hasLength(1));
    });
  });

  group('timeline widget', () {
    Future<void> pump(WidgetTester tester, Size size, int count) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardBirthdaysSlide(
              metrics: DashboardMetrics(size),
              birthdays: _sample(count),
              today: _today,
            ),
          ),
        ),
      );
    }

    testWidgets('tablet shows glass tiles with name, countdown and age', (
      tester,
    ) async {
      await pump(tester, const Size(1280, 800), 8);
      expect(find.byKey(const ValueKey('birthday-timeline')), findsOneWidget);
      expect(find.text('BIRTHDAYS'), findsOneWidget);
      expect(find.text('Person 0'), findsOneWidget);
      expect(find.text('IN 2 DAYS'), findsOneWidget);
      expect(find.text('Sat 3 Oct  ·  Turns 30'), findsOneWidget);
      expect(find.byType(BirthdayGlassTile), findsNWidgets(8));
      // Only the nearest tiles pay for a backdrop blur.
      expect(find.byType(BackdropFilter), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone with one birthday, and an empty state', (tester) async {
      await pump(tester, const Size(390, 844), 1);
      expect(find.byType(BirthdayGlassTile), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pump(tester, const Size(390, 844), 0);
      expect(
        find.byKey(const ValueKey('birthday-timeline-empty')),
        findsOneWidget,
      );
    });

    test('tile countdown labels', () {
      expect(BirthdayGlassTile.daysLabel(0), 'TODAY');
      expect(BirthdayGlassTile.daysLabel(1), 'TOMORROW');
      expect(BirthdayGlassTile.daysLabel(12), 'IN 12 DAYS');
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
