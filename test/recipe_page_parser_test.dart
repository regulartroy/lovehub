import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/recipe_import/recipe_page_parser.dart';

void main() {
  const nigellaIngredients = [
    'a pinch of saffron',
    '2 tablespoons just-boiled water',
    '4 cloves of garlic (peeled and crushed)',
    '3 tablespoons tomato puree',
    '2 tablespoons olive oil',
    'juice of 1 orange',
    '2 teaspoons ground coriander',
    '½ teaspoon turmeric',
    '¼ teaspoon ground cinnamon',
    '500 millilitres hot chicken stock - from 1 stock cube',
    '1 kilogram chicken thighs (skin on and bone in)',
    '250 grams basmati rice',
    '3 cardamom pods (bashed open)',
    'a handful of barberries or pomegranate seeds',
    '10 grams pistachios (roughly chopped)',
    'a handful of coriander leaves',
    '300 grams Greek yoghurt (I use 10% fat)',
    'salt and pepper',
  ];

  final nigellaMicrodata = File(
    'test/fixtures/nigella_persian_saffron_chicken.html',
  ).readAsStringSync();
  final nigellaJsonLd = File(
    'test/fixtures/nigella_persian_saffron_chicken.jsonld.html',
  ).readAsStringSync();

  test('reads the Nigella page microdata into clean lines', () {
    final parsed = parseRecipePage(
      nigellaMicrodata,
      pageUrl:
          'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice',
    );

    final recipe = parsed.recipe;
    expect(recipe, isNotNull);
    expect(recipe!.source, 'microdata');
    expect(recipe.title, 'Persian-Style Saffron Chicken Rice');
    expect(recipe.ingredients, nigellaIngredients);
    expect(recipe.notes, isEmpty);
    expect(recipe.sourceUrl, contains('nigella.com'));
    expect(recipe.method, isNot(contains('not able to answer')));
    expect(recipe.method, isNot(contains('zereshk')));
    expect(recipe.method, startsWith('1. Preheat the oven to 200ºC'));
    expect(
      recipe.method,
      contains('5. Garnish with the barberries or pomegranate seeds'),
    );
    expect(
      RegExp(r'^\d+\. ', multiLine: true).allMatches(recipe.method).length,
      5,
    );
  });

  test('reads the same Nigella recipe from JSON-LD, including HowToSections', () {
    final recipe = parseRecipePage(nigellaJsonLd).recipe!;

    expect(recipe.source, 'json-ld');
    expect(recipe.title, 'Persian-Style Saffron Chicken Rice');
    expect(recipe.ingredients, nigellaIngredients);
    expect(recipe.method, startsWith('For the marinade\n1. Preheat the oven'));
    expect(recipe.method, isNot(contains('Step 1')));
    expect(recipe.method, isNot(contains('Step 2:')));
    expect(recipe.method, isNot(contains('\nInstructions\n')));
    expect(
      recipe.method,
      contains('\n\n3. Transfer half the saffron paste'),
    );
    expect(
      RegExp(r'^\d+\. ', multiLine: true).allMatches(recipe.method).length,
      5,
    );
  });

  test('prefers a useful JSON-LD recipe over microdata', () {
    const html = '''
<script type="application/ld+json">
{"@type":"Recipe","name":"From JSON-LD","recipeIngredient":["1 egg"]}
</script>
<main itemscope itemtype="http://schema.org/Recipe">
  <h1 itemprop="name">From microdata</h1>
  <ul><li itemprop="recipeIngredient">1 kilogram chicken</li></ul>
</main>
''';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.source, 'json-ld');
    expect(recipe.title, 'From JSON-LD');
    expect(recipe.ingredients, ['1 egg']);
  });

  test('falls back to microdata when JSON-LD has no ingredients or steps', () {
    final html =
        '<script type="application/ld+json">{"@type":"Recipe","name":"Wrong"}</script>\n$nigellaMicrodata';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.source, 'microdata');
    expect(recipe.title, 'Persian-Style Saffron Chicken Rice');
    expect(recipe.ingredients, hasLength(18));
  });

  test('HowToSection steps stay short and drop step labels', () {
    const html = '''
<script type="application/ld+json">
{
  "@type": "Recipe",
  "name": "Toast",
  "recipeIngredient": ["1 slice bread", "butter"],
  "recipeInstructions": [
    {
      "@type": "HowToSection",
      "name": "Cook",
      "itemListElement": [
        {"@type": "HowToStep", "name": "Step 1", "text": "Toast the bread."},
        {"@type": "HowToStep", "text": "2. Butter it."}
      ]
    }
  ]
}
</script>
''';
    expect(
      parseRecipePage(html).recipe!.method,
      'Cook\n1. Toast the bread.\n2. Butter it.',
    );
  });

  test('cleans ingredient strings and html method lists', () {
    const html = '''
<script type="application/ld+json">
{
  "@type": "Recipe",
  "name": "Salad",
  "recipeIngredient": [
    "  - 1&nbsp;tsp salt  ",
    "<em>2</em> lemons",
    {"@type": "PropertyValue", "value": "200 g", "name": "flour"},
    "• ",
    "1 tsp salt"
  ],
  "recipeInstructions": "<ol><li>Boil the rice.</li><li>Rest for 5 minutes.</li></ol>"
}
</script>
''';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.ingredients, ['1 tsp salt', '2 lemons', '200 g flour', '1 tsp salt']);
    expect(recipe.method, '1. Boil the rice.\n2. Rest for 5 minutes.');
  });

  test('splits a plain-text method and ignores a breadcrumb graph', () {
    const html = '''
<script type="application/ld+json">
{
  "@graph": [
    {"@type": "BreadcrumbList", "itemListElement": [{"@type": "ListItem", "name": "Recipes"}]},
    {
      "@type": ["Recipe"],
      "name": "Eggs",
      "recipeIngredient": "2 eggs\\nbutter",
      "recipeInstructions": "1. Heat the pan.\\n2. Add the oil."
    }
  ]
}
</script>
''';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.title, 'Eggs');
    expect(recipe.ingredients, ['2 eggs', 'butter']);
    expect(recipe.method, '1. Heat the pan.\n2. Add the oil.');
  });

  test('picks the recipe that actually has ingredients', () {
    const html = '''
<script type="application/ld+json">
[
  {"@type":"Recipe","name":"Thin","recipeIngredient":["salt"]},
  {"@type":"Recipe","name":"Full","recipeIngredient":["salt","pepper","rice"]}
]
</script>
''';
    expect(parseRecipePage(html).recipe!.title, 'Full');
  });

  test('keeps a partial recipe and says what is missing', () {
    const html = '''
<script type="application/ld+json; charset=utf-8">
{"@type":"Recipe","name":"Soup"}
</script>
''';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.title, 'Soup');
    expect(recipe.ingredients, isEmpty);
    expect(recipe.method, isEmpty);
    expect(recipe.notes, [
      'No ingredients were found. Add them before saving.',
      'No method was found.',
    ]);
  });

  test('reports a page with no recipe, and an empty recipe shell', () {
    expect(
      parseRecipePage('<html><body><h1>No recipe here</h1></body></html>').error,
      contains("doesn't publish a recipe"),
    );
    expect(
      parseRecipePage(
        '<script type="application/ld+json">{"@type":"Recipe"}</script>',
      ).error,
      contains("didn't include"),
    );
  });

  test('does not use the author name as the recipe title', () {
    const html = '''
<main itemscope itemtype="https://schema.org/Recipe">
  <span itemprop="author"><span itemprop="name">John Gregory-Smith</span></span>
  <h1 itemprop="name">Real Title</h1>
  <ul><li itemprop="recipeIngredient">1 egg</li></ul>
</main>
''';
    final recipe = parseRecipePage(html).recipe!;
    expect(recipe.title, 'Real Title');
    expect(recipe.ingredients, ['1 egg']);
    expect(recipe.source, 'microdata');
  });
}
