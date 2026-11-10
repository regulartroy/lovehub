import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_day_tiles.dart';
import 'package:lovehub/widgets/recipe_picture.dart';

const _style = CalendarEventStyle(
  who: CalendarColors.shared,
  kind: CalendarColors.personal,
  special: CalendarColors.meal,
);

DashboardDayItem _timed(String title, String time) => DashboardDayItem(
  style: _style,
  title: title,
  timeLabel: time,
  start: DateTime(2026, 11, 10, 9),
);

DashboardDayItem _meal({
  String title = 'Persian-Style Saffron Chicken Rice',
  String label = "Tonight's dinner",
  String? imageUrl,
}) => DashboardDayItem(
  style: _style,
  title: title,
  timeLabel: '19:00–20:00',
  meal: true,
  mealLabel: label,
  imageUrl: imageUrl,
);

Future<void> _pump(WidgetTester tester, List<DashboardDayItem> items) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 600, child: DashboardDayTiles(items: items)),
      ),
    ),
  );
}

void main() {
  test('meal labels follow the day being shown', () {
    final today = DateTime(2026, 11, 10, 16, 30);
    expect(
      dashboardMealLabel(DateTime(2026, 11, 10), now: today),
      "Tonight's dinner",
    );
    expect(
      dashboardMealLabel(DateTime(2026, 11, 11), now: today),
      "Tomorrow's dinner",
    );
    expect(dashboardMealLabel(DateTime(2026, 11, 12), now: today), 'Dinner');
  });

  testWidgets('meals get a dinner strip, not a timed tile, and hide the time', (
    tester,
  ) async {
    await _pump(tester, [
      _timed('School run', '08:30–09:00'),
      _meal(),
      _timed('C2', '14:00–18:00'),
    ]);

    expect(find.byKey(DashboardDayTiles.mealKey), findsOneWidget);
    expect(find.byKey(DashboardDayTiles.tileKey), findsNWidgets(2));
    expect(find.text("TONIGHT'S DINNER"), findsOneWidget);
    expect(find.text('Persian-Style Saffron Chicken Rice'), findsOneWidget);
    expect(find.text('19:00–20:00'), findsNothing);
    expect(find.text('08:30–09:00'), findsOneWidget);
    expect(find.text('14:00–18:00'), findsOneWidget);

    // Featured above the timed grid, not packed into time order.
    final mealY = tester.getTopLeft(find.byKey(DashboardDayTiles.mealKey)).dy;
    final firstTileY = tester
        .getTopLeft(find.byKey(DashboardDayTiles.tileKey).first)
        .dy;
    expect(mealY, lessThan(firstTileY));
  });

  testWidgets('a recipe picture is used when the meal has one', (tester) async {
    await _pump(tester, [
      _meal(imageUrl: 'https://example.test/recipes/chicken.jpg'),
    ]);

    final image = tester.widget<RecipeImage>(find.byType(RecipeImage));
    expect(image.imageUrl, 'https://example.test/recipes/chicken.jpg');
    expect(find.byKey(DashboardDayTiles.mealImageKey), findsOneWidget);
  });

  testWidgets('falls back to a food icon when there is no picture', (
    tester,
  ) async {
    await _pump(tester, [_meal()]);

    expect(find.byType(RecipeImage), findsNothing);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(find.byKey(DashboardDayTiles.mealImageKey), findsOneWidget);
  });

  testWidgets("tomorrow's meal uses the tomorrow label", (tester) async {
    await _pump(tester, [_meal(title: 'Pasta', label: "Tomorrow's dinner")]);

    expect(find.text("TOMORROW'S DINNER"), findsOneWidget);
    expect(find.text('Pasta'), findsOneWidget);
    expect(find.text("TONIGHT'S DINNER"), findsNothing);
  });
}
