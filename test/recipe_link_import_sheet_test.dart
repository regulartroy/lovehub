import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/recipe_import/recipe_import_client.dart';
import 'package:lovehub/recipe_import/recipe_page_parser.dart';
import 'package:lovehub/widgets/recipe_link_import_sheet.dart';

void main() {
  const imported = ParsedRecipe(
    title: 'Persian-Style Saffron Chicken Rice',
    ingredients: ['a pinch of saffron', '250 grams basmati rice'],
    method: '1. Preheat the oven.',
    sourceUrl:
        'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
    source: 'microdata',
    notes: ['No method was found.'],
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<ParsedRecipe> Function(String url) importPage,
    required Future<void> Function(ParsedRecipe recipe) onSave,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => RecipeLinkImportSheet(
                    importPage: importPage,
                    onSave: onSave,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the recipe for editing and saves only after Save', (
    tester,
  ) async {
    ParsedRecipe? saved;
    await pumpSheet(
      tester,
      importPage: (url) async {
        expect(url, contains('nigella.com'));
        return imported;
      },
      onSave: (recipe) async {
        saved = recipe;
      },
    );

    await tester.enterText(
      find.byKey(RecipeLinkImportSheet.urlFieldKey),
      'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.importButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('From nigella.com. Check it, then save.'), findsOneWidget);
    expect(find.text('No method was found.'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(
      find.byKey(RecipeLinkImportSheet.titleFieldKey),
      'Saffron chicken rice',
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.title, 'Saffron chicken rice');
    expect(saved!.ingredients, ['a pinch of saffron', '250 grams basmati rice']);
    expect(saved!.method, '1. Preheat the oven.');
    expect(saved!.sourceUrl, imported.sourceUrl);
  });

  testWidgets('shows a fetch error and does not save', (tester) async {
    var saved = false;
    await pumpSheet(
      tester,
      importPage: (url) async {
        throw RecipeImportException(
          "This page doesn't publish a recipe we can read. Try another link, or add it by hand.",
        );
      },
      onSave: (recipe) async {
        saved = true;
      },
    );

    await tester.enterText(
      find.byKey(RecipeLinkImportSheet.urlFieldKey),
      'https://example.com/not-a-recipe',
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.importButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(RecipeLinkImportSheet.errorKey), findsOneWidget);
    expect(find.text('Add by hand instead'), findsOneWidget);
    expect(saved, isFalse);

    await tester.tap(find.byKey(RecipeLinkImportSheet.manualButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeLinkImportSheet.titleFieldKey), findsOneWidget);
    expect(saved, isFalse);
  });
}
