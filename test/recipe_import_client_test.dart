import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/recipe_import/recipe_import_client.dart';

void main() {
  test('parses html returned for a signed-in member', () async {
    final html = File(
      'test/fixtures/nigella_persian_saffron_chicken.html',
    ).readAsStringSync();
    final client = RecipeImportClient(
      currentUserId: () => 'tom',
      fetchPage: (url, hubId) async {
        expect(hubId, 'home');
        expect(url, contains('nigella.com'));
        return FetchedRecipePage(
          finalUrl: 'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
          html: html,
        );
      },
    );

    final recipe = await client.importUrl(
      hubId: 'home',
      url: ' https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice ',
    );

    expect(recipe.title, 'Persian-Style Saffron Chicken Rice');
    expect(recipe.ingredients, hasLength(18));
    expect(recipe.source, 'microdata');
  });

  test('does not fetch when the link or the sign-in is refused', () async {
    var fetched = false;
    final client = RecipeImportClient(
      currentUserId: () => null,
      fetchPage: (url, hubId) async {
        fetched = true;
        return FetchedRecipePage(finalUrl: url, html: '<html></html>');
      },
    );

    expect(
      () => client.importUrl(hubId: 'home', url: 'http://127.0.0.1/'),
      throwsA(
        predicate<RecipeImportException>(
          (error) => error.message == "That link can't be fetched.",
        ),
      ),
    );
    expect(
      () => client.importUrl(
        hubId: 'home',
        url: 'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
      ),
      throwsA(
        predicate<RecipeImportException>(
          (error) => error.message == 'Sign in to import a recipe.',
        ),
      ),
    );
    expect(fetched, isFalse);
  });

  test('maps a missing function to a deploy hint', () {
    expect(
      messageForRecipeImportCode('not-found', 'NOT FOUND'),
      contains('importRecipePage'),
    );
    expect(
      messageForRecipeImportCode('not-found', "Couldn't find that website."),
      "Couldn't find that website.",
    );
    expect(
      messageForRecipeImportCode('permission-denied', 'nope'),
      contains('member of this hub'),
    );
    expect(
      messageForRecipeImportCode('unavailable', "The recipe site couldn't be reached."),
      "The recipe site couldn't be reached.",
    );
    expect(
      messageForRecipeImportCode('internal', 'INTERNAL'),
      contains('may not be deployed'),
    );
  });

  test('reads the callable payload', () {
    final page = fetchedPageFromCallable(
      {'finalUrl': 'https://www.nigella.com/recipes/x', 'html': '<html></html>'},
      fallbackUrl: 'https://example.com',
    );
    expect(page.finalUrl, 'https://www.nigella.com/recipes/x');
    expect(
      () => fetchedPageFromCallable({'html': ''}, fallbackUrl: 'https://example.com'),
      throwsA(isA<RecipeImportException>()),
    );
  });
}
