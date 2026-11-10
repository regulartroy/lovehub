import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/recipe_import/recipe_import_client.dart';
import 'package:lovehub/recipe_import/recipe_page_parser.dart';
import 'package:lovehub/widgets/recipe_link_import_sheet.dart';
import 'package:lovehub/widgets/recipe_picture.dart';

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
    required Future<void> Function(ParsedRecipe recipe, Uint8List? image)
    onSave,
    Size size = const Size(800, 2400),
    Duration saveTimeout = const Duration(seconds: 20),
    Future<Uint8List?> Function(String url)? loadSuggestedImage,
    RecipePicturePicker? pickPicture,
  }) async {
    tester.view.physicalSize = size;
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
                    saveTimeout: saveTimeout,
                    loadSuggestedImage: loadSuggestedImage,
                    pickPicture: pickPicture ?? (source) async => null,
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
      onSave: (recipe, image) async {
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
    expect(saved!.ingredients, [
      'a pinch of saffron',
      '250 grams basmati rice',
    ]);
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
      onSave: (recipe, image) async {
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

  const fullMethod =
      '1. Preheat the oven to 200ºC/180ºC fan/gas 6. Put the saffron into a mixing bowl and add the just-boiled water. Stir and leave to infuse for a few minutes.\n'
      '2. Add the garlic, tomato puree, olive oil, orange juice, coriander, turmeric, cinnamon and a very generous pinch of salt and pepper to the bowl with the saffron and mix it all into a paste.\n'
      '3. Transfer half the saffron paste to the stock and whisk together. Tip the remaining saffron paste into a large mixing bowl, add the chicken and toss together.\n'
      '4. Tip the rice into a 30x40cm roasting tin and pour over the stock. Add the cardamom pods and arrange the chicken over the top. Cover the tray with foil and bake for 30 minutes. Remove the foil and return to the oven for 20 to 25 minutes or until the chicken is golden and cooked through and the rice crispy on the top.\n'
      '5. Garnish with the barberries or pomegranate seeds, pistachios and coriander leaves and serve immediately with yoghurt.';
  final fullRecipe = ParsedRecipe(
    title: 'Persian-Style Saffron Chicken Rice',
    ingredients: [for (var i = 0; i < 18; i++) 'ingredient line $i'],
    method: fullMethod,
    sourceUrl: imported.sourceUrl,
    source: 'microdata',
  );

  Future<void> importOnPhone(
    WidgetTester tester, {
    required Future<void> Function(ParsedRecipe recipe, Uint8List? image)
    onSave,
    Duration saveTimeout = const Duration(seconds: 20),
  }) async {
    await pumpSheet(
      tester,
      size: const Size(390, 844),
      saveTimeout: saveTimeout,
      importPage: (url) async => fullRecipe,
      onSave: onSave,
    );
    await tester.enterText(
      find.byKey(RecipeLinkImportSheet.urlFieldKey),
      imported.sourceUrl!,
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.importButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone, Save is on screen after import and saves', (
    tester,
  ) async {
    ParsedRecipe? saved;
    await importOnPhone(
      tester,
      onSave: (recipe, image) async => saved = recipe,
    );

    // The top button no longer reads "Import" once the preview is showing.
    expect(find.text('Import'), findsNothing);
    expect(find.text('Fetch link again'), findsOneWidget);

    final save = find.byKey(RecipeLinkImportSheet.saveButtonKey);
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.method, fullMethod);
    expect(saved!.ingredients.length, 18);
    expect(find.byType(RecipeLinkImportSheet), findsNothing);
    expect(
      find.text('Saved "Persian-Style Saffron Chicken Rice" to your Cookbook.'),
      findsOneWidget,
    );
  });

  testWidgets('the method field shows the whole method', (tester) async {
    await importOnPhone(tester, onSave: (recipe, image) async {});
    final field = tester.widget<TextField>(
      find.byKey(RecipeLinkImportSheet.methodFieldKey),
    );
    expect(field.controller!.text, fullMethod);
    expect(field.maxLines, isNull);
  });

  testWidgets('a failed save shows an error and keeps the sheet open', (
    tester,
  ) async {
    await importOnPhone(
      tester,
      onSave: (recipe, image) async => throw Exception('permission-denied'),
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RecipeLinkImportSheet), findsOneWidget);
    expect(
      find.byKey(RecipeLinkImportSheet.saveErrorKey).hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsWidgets);
    // The button is usable again for a retry.
    final button = tester.widget<FilledButton>(
      find.byKey(RecipeLinkImportSheet.saveButtonKey),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a save that never finishes times out with an error', (
    tester,
  ) async {
    await importOnPhone(
      tester,
      saveTimeout: const Duration(seconds: 2),
      onSave: (recipe, image) => Completer<void>().future,
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byType(RecipeLinkImportSheet), findsOneWidget);
    expect(find.byKey(RecipeLinkImportSheet.saveErrorKey), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsWidgets);
  });

  final suggested = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 4, height: 3)),
  );
  final mine = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 3, height: 4)),
  );
  final withImage = fullRecipe.withImageUrl(
    'https://www.nigella.com/assets/uploads/recipes/public-thumbnail/p.jpg',
  );

  Future<void> importWithSuggestion(
    WidgetTester tester, {
    required Future<void> Function(ParsedRecipe recipe, Uint8List? image)
    onSave,
    Completer<Uint8List?>? imageLoad,
    RecipePicturePicker? pickPicture,
    List<String>? requested,
  }) async {
    await pumpSheet(
      tester,
      size: const Size(390, 844),
      importPage: (url) async => withImage,
      loadSuggestedImage: (url) {
        requested?.add(url);
        return imageLoad?.future ?? Future.value(suggested);
      },
      pickPicture: pickPicture,
      onSave: onSave,
    );
    await tester.enterText(
      find.byKey(RecipeLinkImportSheet.urlFieldKey),
      imported.sourceUrl!,
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.importButtonKey));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('keeps the suggested picture by default', (tester) async {
    Uint8List? savedImage;
    final requested = <String>[];
    await importWithSuggestion(
      tester,
      requested: requested,
      onSave: (recipe, image) async => savedImage = image,
    );
    expect(requested, [withImage.imageUrl]);
    expect(find.textContaining('Picture from nigella.com'), findsOneWidget);
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pumpAndSettle();
    expect(savedImage, suggested);
  });

  testWidgets(
    'removing the suggestion saves no picture, and it can come back',
    (tester) async {
      var calls = 0;
      Uint8List? savedImage = Uint8List(1);
      await importWithSuggestion(
        tester,
        onSave: (recipe, image) async {
          calls++;
          savedImage = image;
        },
      );
      await tester.ensureVisible(find.byKey(RecipePictureEditor.removeKey));
      await tester.tap(find.byKey(RecipePictureEditor.removeKey));
      await tester.pump();
      expect(find.byKey(RecipePictureEditor.useSuggestionKey), findsOneWidget);
      await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(savedImage, isNull);
    },
  );

  testWidgets('my own picture replaces the suggestion', (tester) async {
    Uint8List? savedImage;
    ImageSource? asked;
    await importWithSuggestion(
      tester,
      pickPicture: (source) async {
        asked = source;
        return mine;
      },
      onSave: (recipe, image) async => savedImage = image,
    );
    await tester.ensureVisible(find.byKey(RecipePictureEditor.galleryKey));
    await tester.tap(find.byKey(RecipePictureEditor.galleryKey));
    await tester.pump();
    await tester.pump();
    expect(asked, ImageSource.gallery);
    expect(find.textContaining('Picture from'), findsNothing);
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pumpAndSettle();
    expect(savedImage, mine);
  });

  testWidgets('Save waits while the suggested picture loads', (tester) async {
    final load = Completer<Uint8List?>();
    var calls = 0;
    await importWithSuggestion(
      tester,
      imageLoad: load,
      onSave: (recipe, image) async => calls++,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(RecipeLinkImportSheet.saveButtonKey),
    );
    expect(button.onPressed, isNull);
    load.complete(suggested);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('a picture that fails to load does not block saving', (
    tester,
  ) async {
    final load = Completer<Uint8List?>();
    Uint8List? savedImage = Uint8List(1);
    await importWithSuggestion(
      tester,
      imageLoad: load,
      onSave: (recipe, image) async => savedImage = image,
    );
    load.completeError(Exception('HTTP 403'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text("Couldn't load the picture from that page."),
      findsOneWidget,
    );
    await tester.tap(find.byKey(RecipeLinkImportSheet.saveButtonKey));
    await tester.pumpAndSettle();
    expect(savedImage, isNull);
  });
}
