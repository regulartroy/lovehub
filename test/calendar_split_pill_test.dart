import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  testWidgets('split pill paints person left and category right', (
    tester,
  ) async {
    const style = CalendarEventStyle(
      who: CalendarColors.tom,
      kind: CalendarColors.work,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: CalendarSplitPill(
                style: style,
                title: 'Early shift',
                subtitle: '07:00',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Early shift'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);

    final who = tester.widget<ColoredBox>(find.byKey(CalendarSplitPill.whoKey));
    final kind = tester.widget<ColoredBox>(
      find.byKey(CalendarSplitPill.kindKey),
    );
    expect(who.color, CalendarColors.tom);
    expect(kind.color, CalendarColors.work);

    final whoBox = tester.getRect(find.byKey(CalendarSplitPill.whoKey));
    final kindBox = tester.getRect(find.byKey(CalendarSplitPill.kindKey));
    expect(whoBox.left, lessThan(kindBox.left));
    expect(kindBox.width, greaterThan(whoBox.width));
    expect(kindBox.width / whoBox.width, closeTo(2, 0.35));
  });

  testWidgets('Maria yellow and Shared pink stay different who colours', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CalendarSplitPill(
                key: Key('maria-leisure'),
                style: CalendarEventStyle(
                  who: CalendarColors.maria,
                  kind: CalendarColors.personal,
                ),
                title: 'Dentist',
              ),
              CalendarSplitPill(
                key: Key('shared-leisure'),
                style: CalendarEventStyle(
                  who: CalendarColors.shared,
                  kind: CalendarColors.personal,
                ),
                title: 'Farmers market walk',
              ),
              CalendarSplitPill(
                key: Key('shared-birthday'),
                style: CalendarEventStyle(
                  who: CalendarColors.shared,
                  kind: CalendarColors.birthday,
                  special: CalendarColors.birthday,
                ),
                title: "Maria's birthday",
              ),
            ],
          ),
        ),
      ),
    );

    ColoredBox whoOf(Key pillKey) {
      return tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(pillKey),
          matching: find.byKey(CalendarSplitPill.whoKey),
        ),
      );
    }

    ColoredBox kindOf(Key pillKey) {
      return tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(pillKey),
          matching: find.byKey(CalendarSplitPill.kindKey),
        ),
      );
    }

    expect(whoOf(const Key('maria-leisure')).color, CalendarColors.maria);
    expect(whoOf(const Key('shared-leisure')).color, CalendarColors.shared);
    expect(
      whoOf(const Key('maria-leisure')).color,
      isNot(CalendarColors.shared),
    );
    expect(kindOf(const Key('maria-leisure')).color, CalendarColors.personal);
    expect(kindOf(const Key('shared-leisure')).color, CalendarColors.personal);
    expect(kindOf(const Key('shared-birthday')).color, CalendarColors.birthday);
  });

  testWidgets('look-ahead week chips use the split pill', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime(2026, 9, 19);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardCalendarOverviewSlide(
            metrics: DashboardMetrics(const Size(1024, 768)),
            now: now,
            members: const [
              {'uid': 'tom', 'name': 'Tom'},
              {'uid': 'maria', 'name': 'Maria'},
            ],
            events: [
              {
                'summary': 'Early shift',
                'start': DateTime(2026, 9, 20, 7),
                'end': DateTime(2026, 9, 20, 15),
                'category': 'work',
                'assignedTo': 'tom',
              },
            ],
          ),
        ),
      ),
    );

    expect(find.byType(CalendarSplitPill), findsWidgets);
    expect(find.textContaining('Early shift'), findsWidgets);
    final who = tester.widget<ColoredBox>(
      find.byKey(CalendarSplitPill.whoKey).first,
    );
    final kind = tester.widget<ColoredBox>(
      find.byKey(CalendarSplitPill.kindKey).first,
    );
    expect(who.color, CalendarColors.tom);
    expect(kind.color, CalendarColors.work);
  });

  testWidgets('tentative chip is muted and shows a question mark', (
    tester,
  ) async {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'uid-tom', 'displayName': 'Tom Workman'},
    ]);
    final confirmed = CalendarColors.resolve(
      assignedTo: 'tom',
      category: 'work',
      palette: palette,
    );
    final tentative = CalendarColors.resolve(
      assignedTo: 'tom',
      category: 'work',
      status: 'tentative',
      palette: palette,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CalendarSplitPill(
                key: const Key('confirmed'),
                style: confirmed,
                title: 'C2 Show — Artist',
                subtitle: '15:00',
              ),
              CalendarSplitPill(
                key: const Key('tentative'),
                style: tentative,
                title: 'C2 Show — Artist',
                subtitle: '15:00',
                density: CalendarSplitPillDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    final confirmedKind = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('confirmed')),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    final tentativeKind = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('tentative')),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    expect(confirmedKind.color, CalendarColors.work);
    expect(tentativeKind.color, tentative.kind);
    expect(tentativeKind.color, isNot(CalendarColors.work));
  });
}
