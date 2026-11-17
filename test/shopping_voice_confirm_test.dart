import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/widgets/dashboard/shopping_voice_confirm.dart';

void main() {
  Future<List<String>?> Function() pumpDialog(
    WidgetTester tester,
    List<String> items,
  ) {
    List<String>? result;
    var done = false;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ShoppingVoiceConfirmDialog.show(
                      context,
                      items: items,
                      heard: 'add milk and eggs to my shopping list',
                    );
                    done = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return done ? result : null;
    };
  }

  testWidgets('lists items, lets you remove one, and returns the rest', (
    tester,
  ) async {
    await pumpDialog(tester, ['Milk', 'Eggs', 'Bread'])();
    expect(find.text('Add to shopping list?'), findsOneWidget);
    expect(find.text('Add 3 items'), findsOneWidget);

    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.removeKey(1)));
    await tester.pumpAndSettle();
    expect(find.text('Eggs'), findsNothing);
    expect(find.text('Add 2 items'), findsOneWidget);

    await tester.enterText(
      find.byKey(ShoppingVoiceConfirmDialog.fieldKey(1)),
      'sourdough bread',
    );
    await tester.pump();

    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.addKey));
    await tester.pumpAndSettle();
    expect(find.byKey(ShoppingVoiceConfirmDialog.cardKey), findsNothing);
  });

  testWidgets('Add returns the edited list; Cancel returns null', (
    tester,
  ) async {
    List<String>? added;
    var cancelled = false;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    added = await ShoppingVoiceConfirmDialog.show(
                      context,
                      items: ['Milk', 'Eggs'],
                    );
                  },
                  child: const Text('add'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final r = await ShoppingVoiceConfirmDialog.show(
                      context,
                      items: ['Milk'],
                    );
                    cancelled = r == null;
                  },
                  child: const Text('cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ShoppingVoiceConfirmDialog.fieldKey(1)),
      'some free range eggs',
    );
    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.addRowKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ShoppingVoiceConfirmDialog.fieldKey(2)),
      'butter',
    );
    await tester.pump();
    expect(find.text('Add 3 items'), findsOneWidget);
    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.addKey));
    await tester.pumpAndSettle();
    expect(added, ['Milk', 'Free range eggs', 'Butter']);

    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.cancelKey));
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });

  testWidgets('Add is disabled when every item is removed', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ShoppingVoiceConfirmDialog(items: ['Milk'])),
      ),
    );
    await tester.tap(find.byKey(ShoppingVoiceConfirmDialog.removeKey(0)));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(ShoppingVoiceConfirmDialog.addKey),
    );
    expect(button.onPressed, isNull);
  });
}
