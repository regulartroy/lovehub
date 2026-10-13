/// Local, offline shopping-list categoriser used when the AI Smart Sort
/// is unavailable. Maps item text to a UK supermarket aisle and a
/// `sortIndex` following a typical walk through the shop.
library;

enum ShoppingAisle {
  fruitVeg(10, 'Fruit & veg'),
  bakery(20, 'Bakery'),
  meatFish(30, 'Meat & fish'),
  dairyEggs(40, 'Dairy & eggs'),
  chilled(50, 'Chilled'),
  frozen(60, 'Frozen'),
  tinsDry(70, 'Tins & dry goods'),
  breakfast(80, 'Breakfast & cereal'),
  snacks(90, 'Snacks & sweets'),
  drinks(100, 'Drinks'),
  alcohol(110, 'Alcohol'),
  household(120, 'Household & cleaning'),
  toiletries(130, 'Toiletries & health'),
  pet(140, 'Pet'),
  baby(150, 'Baby'),
  other(160, 'Other');

  const ShoppingAisle(this.sortIndex, this.label);
  final int sortIndex;
  final String label;
}

// Multi-word phrases are checked before single words, so "ice cream"
// beats "cream" and "dog food" beats "food".
const Map<ShoppingAisle, List<String>> _keywords = {
  ShoppingAisle.pet: [
    'dog food',
    'cat food',
    'dog treat',
    'dog biscuit',
    'poo bag',
    'enzo',
    'dog',
    'puppy',
    'cat litter',
    'kibble',
    'pet',
    'chew',
    'dentastix',
    'bonio',
    'pedigree',
    'whiskas',
  ],
  ShoppingAisle.baby: [
    'baby wipe',
    'nappy',
    'nappies',
    'baby',
    'formula',
    'calpol',
  ],
  ShoppingAisle.frozen: [
    'ice cream',
    'frozen',
    'fish finger',
    'oven chip',
    'ice lolly',
    'ice cube',
    'ice',
    'garden peas',
    'yorkshire pudding',
  ],
  ShoppingAisle.breakfast: [
    'cereal',
    'porridge',
    'oat',
    'granola',
    'muesli',
    'weetabix',
    'cornflake',
    'shreddies',
    'jam',
    'marmalade',
    'honey',
    'peanut butter',
    'nutella',
    'marmite',
    'syrup',
  ],
  ShoppingAisle.alcohol: [
    'wine',
    'beer',
    'lager',
    'cider',
    'gin',
    'vodka',
    'whisky',
    'whiskey',
    'rum',
    'prosecco',
    'champagne',
    'ale',
    'tequila',
    'bourbon',
  ],
  ShoppingAisle.drinks: [
    'orange juice',
    'apple juice',
    'juice',
    'squash',
    'water',
    'coke',
    'cola',
    'lemonade',
    'pepsi',
    'tea bag',
    'tea',
    'coffee',
    'pop',
    'fizzy',
    'tonic',
    'smoothie',
    'hot chocolate',
    'drink',
  ],
  ShoppingAisle.household: [
    'washing up liquid',
    'washing up',
    'kitchen roll',
    'toilet roll',
    'loo roll',
    'toilet paper',
    'bin bag',
    'bin liner',
    'tin foil',
    'foil',
    'cling film',
    'clingfilm',
    'sponge',
    'bleach',
    'detergent',
    'fabric softener',
    'softener',
    'laundry',
    'dishwasher',
    'fairy',
    'cleaner',
    'spray',
    'battery',
    'batteries',
    'bulb',
    'candle',
    'tissue',
    'napkin',
    'cloth',
    'zoflora',
    'flash',
    'antibac',
  ],
  ShoppingAisle.toiletries: [
    'toothpaste',
    'toothbrush',
    'shampoo',
    'conditioner',
    'shower gel',
    'body wash',
    'soap',
    'deodorant',
    'razor',
    'mouthwash',
    'floss',
    'paracetamol',
    'ibuprofen',
    'plaster',
    'tampon',
    'sanitary',
    'moisturiser',
    'sun cream',
    'suncream',
    'lotion',
    'vitamin',
    'cotton',
    'lip balm',
    'hand wash',
  ],
  ShoppingAisle.snacks: [
    'crisp',
    'chocolate',
    'sweet',
    'biscuit',
    'cookie',
    'popcorn',
    'nut',
    'haribo',
    'cake',
    'flapjack',
    'cereal bar',
    'snack',
    'pringles',
    'dip',
    'hummus',
    'houmous',
  ],
  ShoppingAisle.dairyEggs: [
    'milk',
    'butter',
    'cheese',
    'cheddar',
    'mozzarella',
    'yoghurt',
    'yogurt',
    'egg',
    'cream',
    'creme fraiche',
    'margarine',
    'flora',
    'halloumi',
    'feta',
    'parmesan',
  ],
  ShoppingAisle.chilled: [
    'ham',
    'salami',
    'chorizo',
    'pizza',
    'fresh pasta',
    'coleslaw',
    'quiche',
    'pastry',
    'ready meal',
    'soup',
    'sandwich',
    'tofu',
    'pesto',
    'pate',
  ],
  ShoppingAisle.meatFish: [
    'chicken',
    'beef',
    'mince',
    'pork',
    'lamb',
    'bacon',
    'sausage',
    'steak',
    'turkey',
    'fish',
    'salmon',
    'cod',
    'tuna steak',
    'prawn',
    'haddock',
    'gammon',
    'meat',
    'burger',
    'duck',
  ],
  ShoppingAisle.bakery: [
    'bread',
    'loaf',
    'roll',
    'bagel',
    'baguette',
    'croissant',
    'crumpet',
    'muffin',
    'wrap',
    'tortilla',
    'pitta',
    'naan',
    'bun',
    'scone',
    'teacake',
    'brioche',
    'sourdough',
  ],
  ShoppingAisle.fruitVeg: [
    'apple',
    'banana',
    'orange',
    'lemon',
    'lime',
    'grape',
    'strawberr',
    'raspberr',
    'blueberr',
    'berry',
    'berries',
    'melon',
    'pear',
    'peach',
    'plum',
    'mango',
    'pineapple',
    'kiwi',
    'avocado',
    'tomato',
    'potato',
    'spud',
    'onion',
    'garlic',
    'carrot',
    'broccoli',
    'cauliflower',
    'cabbage',
    'lettuce',
    'salad',
    'cucumber',
    'pepper',
    'mushroom',
    'courgette',
    'aubergine',
    'spinach',
    'kale',
    'leek',
    'celery',
    'parsnip',
    'swede',
    'sweet potato',
    'sweetcorn',
    'corn',
    'bean sprout',
    'spring onion',
    'ginger',
    'chilli',
    'herb',
    'coriander',
    'basil',
    'parsley',
    'rocket',
    'beetroot',
    'sprout',
    'fruit',
    'veg',
    'clementine',
    'satsuma',
    'cherr',
    'butternut',
    'iceberg',
    'watermelon',
  ],
  ShoppingAisle.tinsDry: [
    'baked bean',
    'chopped tomato',
    'tinned',
    'tin',
    'can',
    'pasta',
    'spaghetti',
    'penne',
    'fusilli',
    'noodle',
    'rice',
    'flour',
    'sugar',
    'salt',
    'stock',
    'gravy',
    'oil',
    'vinegar',
    'ketchup',
    'mayo',
    'mustard',
    'sauce',
    'spice',
    'cumin',
    'paprika',
    'lentil',
    'chickpea',
    'bean',
    'cous cous',
    'couscous',
    'quinoa',
    'oxo',
    'bisto',
    'tuna',
    'sweetener',
    'baking',
    'yeast',
    'curry paste',
    'passata',
    'puree',
  ],
};

final List<(String, ShoppingAisle)> _orderedPhrases = () {
  final list = <(String, ShoppingAisle)>[];
  _keywords.forEach((aisle, words) {
    for (final w in words) {
      list.add((w, aisle));
    }
  });
  // Longer phrases first so specific matches win; ties keep map order.
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final byLen = b.value.$1.length.compareTo(a.value.$1.length);
      return byLen != 0 ? byLen : a.key.compareTo(b.key);
    });
  return indexed.map((e) => e.value).toList();
}();

String _normalise(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll(RegExp(r"[^a-z\s]"), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return ' $t ';
}

bool _matches(String haystack, String phrase) {
  // Match at a word start; allow plural/suffix endings (s, es, ies...).
  final p = RegExp.escape(phrase);
  return RegExp(' $p').hasMatch(haystack);
}

/// Returns the best-guess aisle for a shopping item's text.
ShoppingAisle categoriseShoppingItem(String text) {
  final hay = _normalise(text);
  if (hay.trim().isEmpty) return ShoppingAisle.other;
  for (final (phrase, aisle) in _orderedPhrases) {
    if (_matches(hay, phrase)) return aisle;
  }
  return ShoppingAisle.other;
}

/// Local fallback for Smart Sort: `id -> sortIndex`, same shape the AI
/// path writes to Firestore.
Map<String, int> localAisleSortIndexes(
  Iterable<(String id, String text)> items,
) {
  return {
    for (final (id, text) in items) id: categoriseShoppingItem(text).sortIndex,
  };
}

/// Result of a Smart Sort attempt.
class SmartSortResult {
  const SmartSortResult(this.sortIndexes, {required this.usedFallback});
  final Map<String, int> sortIndexes;
  final bool usedFallback;
}

/// Tries [aiSort] (returns `id -> sortIndex`) within [timeout]; on any
/// error, timeout, or empty/invalid answer, falls back to the local
/// aisle categoriser. Items the AI omitted are filled in locally.
Future<SmartSortResult> smartSortShoppingIndexes(
  List<(String id, String text)> items, {
  required Future<Map<String, int>> Function() aiSort,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final local = localAisleSortIndexes(items);
  try {
    final ai = await aiSort().timeout(timeout);
    final ids = local.keys.toSet();
    final known = {
      for (final e in ai.entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    if (known.isEmpty) {
      return SmartSortResult(local, usedFallback: true);
    }
    return SmartSortResult({
      for (final id in local.keys) id: known[id] ?? local[id]!,
    }, usedFallback: false);
  } catch (_) {
    return SmartSortResult(local, usedFallback: true);
  }
}
