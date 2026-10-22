import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/undo_snackbar.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('undo snackbar auto-dismisses after ~4s', (tester) async {
    final ctx = await pump(tester);
    showUndoSnackBar(ctx, message: 'Item checked off', onUndo: () {});
    await tester.pumpAndSettle();
    expect(find.text('Item checked off'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Item checked off'), findsNothing);
  });

  testWidgets('a second check-off replaces instead of queueing', (
    tester,
  ) async {
    final ctx = await pump(tester);
    showUndoSnackBar(ctx, message: 'First', onUndo: () {});
    await tester.pumpAndSettle();
    showUndoSnackBar(ctx, message: 'Second', onUndo: () {});
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('undo fires and tapping elsewhere hides it', (tester) async {
    final ctx = await pump(tester);
    var undone = 0;
    showUndoSnackBar(ctx, message: 'Done', onUndo: () => undone++);
    await tester.pumpAndSettle();
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Done'), findsNothing);

    showUndoSnackBar(ctx, message: 'Again', onUndo: () {});
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(find.text('Again'), findsNothing);
  });

  testWidgets('navigating clears the snackbar', (tester) async {
    final key = GlobalKey<ScaffoldMessengerState>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: key,
        navigatorKey: nav,
        navigatorObservers: [SnackBarClearingObserver(key)],
        home: Scaffold(body: Builder(builder: (c) => const SizedBox())),
      ),
    );
    showUndoSnackBar(nav.currentContext!, message: 'Stale', onUndo: () {});
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsOneWidget);
    nav.currentState!.push(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Next'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsNothing);
  });
}
