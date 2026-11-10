import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/recipe_import/recipe_url.dart';

void main() {
  test('accepts a recipe link and strips the fragment', () {
    expect(
      validateRecipeImportUrl(
        'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice#method',
      ),
      'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
    );
    expect(
      validateRecipeImportUrl(
        'www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
      ),
      'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
    );
    expect(
      validateRecipeImportUrl('https://example.com/a?x=1#b'),
      'https://example.com/a?x=1',
    );
    expect(
      validateRecipeImportUrl('http://8.8.8.8/recipe'),
      'http://8.8.8.8/recipe',
    );
    expect(
      validateRecipeImportUrl('http://[2606:4700:4700::1111]/recipe'),
      'http://[2606:4700:4700::1111]/recipe',
    );
  });

  test('rejects non-http schemes and blank links', () {
    for (final input in [
      '',
      '   ',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'ftp://example.com/recipe',
    ]) {
      expect(
        () => validateRecipeImportUrl(input),
        throwsA(
          predicate<RecipeUrlException>(
            (error) => error.message.contains('http or https'),
          ),
        ),
        reason: input,
      );
    }
  });

  test('rejects credentials, odd ports, and internal addresses', () {
    const blocked = [
      'https://user:pass@example.com/recipe',
      'https://example.com:22/recipe',
      'http://127.0.0.1/latest',
      'http://169.254.169.254/computeMetadata/v1/',
      'http://10.1.2.3/',
      'http://192.168.0.1/',
      'http://172.16.0.1/',
      'http://100.64.0.1/',
      'http://[::1]/',
      'http://[fc00::1]/',
      'http://[fe80::1]/',
      'http://[2001:db8::1]/',
      'http://localhost/recipe',
      'http://metadata.google.internal/',
      'http://2130706433/',
      'http://0177.0.0.1/',
      'http://printer/recipe',
    ];
    for (final input in blocked) {
      expect(
        () => validateRecipeImportUrl(input),
        throwsA(
          predicate<RecipeUrlException>(
            (error) => error.message == "That link can't be fetched.",
          ),
        ),
        reason: input,
      );
    }
  });

  test('source label drops a leading www', () {
    expect(
      recipeSourceLabel(
        'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
      ),
      'nigella.com',
    );
  });
}
