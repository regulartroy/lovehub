import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/dashboard/dashboard_chrome.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  testWidgets('empty state shows a calm title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardEmptyState(
            icon: Icons.favorite_outline,
            title: 'No hub selected',
            message: 'Open a shared hub from settings.',
          ),
        ),
      ),
    );

    expect(find.text('No hub selected'), findsOneWidget);
    expect(find.text('Open a shared hub from settings.'), findsOneWidget);
  });

  testWidgets('section header keeps icon and title readable', (tester) async {
    final metrics = DashboardMetrics(const Size(400, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.task_alt_rounded,
            tint: DashboardTheme.tasks,
            title: 'TASKS',
          ),
        ),
      ),
    );

    expect(find.text('TASKS'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
  });

  testWidgets('page dots highlight the current slide', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DashboardPageDots(count: 4, index: 2),
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedContainer), findsNWidgets(4));
  });

  test('compact metrics tighten padding for phones', () {
    final phone = DashboardMetrics(const Size(390, 844));
    final tablet = DashboardMetrics(const Size(1024, 768));

    expect(phone.isCompact, isTrue);
    expect(tablet.isCompact, isFalse);
    expect(phone.slidePadH, lessThan(tablet.slidePadH));
    expect(phone.clockSize, lessThan(tablet.clockSize));
  });
}
