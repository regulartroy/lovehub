/// Parses dashboard voice commands that add items to the shopping list,
/// e.g. "add milk and eggs to my shopping list" or "put bread on the list".
library;

/// A recognised "add to shopping" command and the items it named.
class ShoppingVoiceCommand {
  const ShoppingVoiceCommand(this.items, {this.explicit = true});

  /// Tidied item names, in the order they were said, without duplicates.
  /// Empty when the command was recognised but named nothing usable
  /// (e.g. "add to my shopping list").
  final List<String> items;

  /// True when the shopping list was named ("... to my shopping list").
  /// Looser phrasings ("we need milk", "buy eggs") are not explicit, so a
  /// calendar question should win over them.
  final bool explicit;
}

const _verb =
    r'(?:add|put|stick|pop|chuck|throw|include|write|note|jot(?:\s+down)?)';
const _target =
    r'(?:(?:my|the|our|a)\s+)?(?:shopping(?:\s+list)?|shop(?:ping)?\s+list|grocery\s+list|groceries|list|shop)';
const _prep = r'(?:on(?:\s*to)?|onto|to|in(?:\s*to)?|into|for)';
const _lead =
    r'^(?:(?:hey|ok|okay|right|so|um|erm|uh)[\s,]+)*(?:(?:please|can\s+you|could\s+you|would\s+you|will\s+you|i\s+want\s+to|i(?:\x27d|\s+would)\s+like\s+to|let\x27s|lets)[\s,]+)*';

// "add milk and eggs to my shopping list (please)"
final _verbItemsTarget = RegExp(
  '$_lead$_verb\\s+(.+?)\\s+$_prep\\s+$_target(?:\\s+(?:please|thanks|thank\\s+you))?\$',
  caseSensitive: false,
);

// "add to the shopping list milk and eggs"
final _verbTargetItems = RegExp(
  '$_lead$_verb\\s+$_prep\\s+$_target[\\s,:]+(.+)\$',
  caseSensitive: false,
);

// "shopping list: milk and eggs" / "shopping list add milk"
final _targetFirst = RegExp(
  '^(?:(?:my|the|our)\\s+)?(?:shopping(?:\\s+list)?|grocery\\s+list)[\\s,:-]+(?:$_verb\\s+)?(.+)\$',
  caseSensitive: false,
);

// "we need milk" / "we're out of eggs" / "we've run out of bread"
final _needItems = RegExp(
  '$_lead(?:we)\\s*(?:\\x27re|\\s+are|\\x27ve|\\s+have)?\\s*(?:need|run\\s+out\\s+of|ran\\s+out\\s+of|out\\s+of|need\\s+to\\s+buy|need\\s+to\\s+get)\\s+(?:to\\s+(?:buy|get)\\s+)?(?:some\\s+more\\s+)?(.+)\$',
  caseSensitive: false,
);

// "buy milk" / "remember to buy eggs"
final _buyItems = RegExp(
  '$_lead(?:remember\\s+to\\s+|remind\\s+me\\s+to\\s+|don\\x27t\\s+forget\\s+to\\s+)?(?:buy|pick\\s+up)\\s+(.+?)(?:\\s+$_prep\\s+$_target)?\$',
  caseSensitive: false,
);

/// Phrases that contain "and" but are one item.
const _joinedPhrases = [
  'fish and chips',
  'salt and vinegar',
  'cheese and onion',
  'mac and cheese',
  'macaroni and cheese',
  'sweet and sour',
  'bread and butter',
  'oil and vinegar',
  'salt and pepper',
  'ham and cheese',
  'cheese and tomato',
  'prawn and mayo',
  'egg and cress',
  'chicken and mushroom',
  'steak and kidney',
  'lemon and herb',
  'strawberries and cream',
  'peaches and cream',
  'pen and paper',
  'head and shoulders',
  'marks and spencer',
  'ben and jerry',
  'm and m',
];

const _leadingFiller = {
  'some',
  'a',
  'an',
  'the',
  'more',
  'any',
  'also',
  'please',
  'and',
  'plus',
  'then',
  'maybe',
  'another',
  'extra',
  'of',
};

const _trailingFiller = [
  'please',
  'thanks',
  'thank you',
  'as well',
  'too',
  'also',
  'again',
];

/// Returns the shopping command in [raw], or null when it isn't one.
ShoppingVoiceCommand? parseShoppingVoiceCommand(String raw) {
  final text = _normalise(raw);
  if (text.isEmpty) return null;

  // Bare "add to my shopping list" with nothing named.
  if (RegExp(
    '$_lead$_verb\\s+$_prep\\s+$_target\$',
    caseSensitive: false,
  ).hasMatch(text)) {
    return const ShoppingVoiceCommand([]);
  }

  String? itemsText;
  var explicit = true;
  for (final pattern in [_verbTargetItems, _verbItemsTarget, _targetFirst]) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      itemsText = match.group(1);
      break;
    }
  }
  if (itemsText == null) {
    final need = _needItems.firstMatch(text) ?? _buyItems.firstMatch(text);
    if (need != null) {
      itemsText = need.group(1);
      explicit = RegExp(
        '$_prep\\s+$_target\$',
        caseSensitive: false,
      ).hasMatch(text);
    }
  }
  if (itemsText == null) return null;
  return ShoppingVoiceCommand(
    splitShoppingItems(itemsText),
    explicit: explicit,
  );
}

/// Splits spoken item text on commas, "and", "&", "plus" and "+", then
/// tidies each item. Keeps common "X and Y" products together.
List<String> splitShoppingItems(String text) {
  var working = ' ${_normalise(text)} ';
  final protected = <String, String>{};
  for (var i = 0; i < _joinedPhrases.length; i++) {
    final phrase = _joinedPhrases[i];
    final re = RegExp('\\b${RegExp.escape(phrase)}', caseSensitive: false);
    working = working.replaceAllMapped(re, (m) {
      final key = '\u0000$i\u0000';
      protected[key] = m.group(0)!;
      return key;
    });
  }
  final parts = working.split(
    RegExp(
      r'\s*(?:,|;|&|\+|\band\b|\bplus\b|\balong\s+with\b|\bwith\s+some\b)\s*',
      caseSensitive: false,
    ),
  );
  final seen = <String>{};
  final out = <String>[];
  for (var part in parts) {
    protected.forEach((key, value) => part = part.replaceAll(key, value));
    final item = tidyShoppingItem(part);
    if (item.isEmpty) continue;
    if (seen.add(shoppingItemKey(item))) out.add(item);
  }
  return out;
}

/// Strips filler words and capitalises the first letter.
String tidyShoppingItem(String raw) {
  var words = raw
      .replaceAll(RegExp(r'[.!?"“”]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var changed = true;
  while (changed && words.isNotEmpty) {
    changed = false;
    if (words.length > 1 &&
        _leadingFiller.contains(words.first.toLowerCase())) {
      words.removeAt(0);
      changed = true;
      continue;
    }
    if (words.length == 1 &&
        _leadingFiller.contains(words.first.toLowerCase())) {
      return '';
    }
    final joined = words.join(' ').toLowerCase();
    for (final tail in _trailingFiller) {
      if (joined == tail) return '';
      if (joined.endsWith(' $tail')) {
        words = words.sublist(0, words.length - tail.split(' ').length);
        changed = true;
        break;
      }
    }
  }
  if (words.isEmpty) return '';
  final item = words.join(' ');
  // Leave brand-style casing ("iPhone") alone.
  if (item.length > 1 && item[1] != item[1].toLowerCase()) return item;
  return item[0].toUpperCase() + item.substring(1);
}

/// Case- and spacing-insensitive key for duplicate checks.
String shoppingItemKey(String text) {
  var key = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  key = key.replaceAll(RegExp(r'\s+'), ' ');
  // Drop a leading "some"/"a"/"the" so "the milk" matches "milk".
  key = key.replaceFirst(RegExp(r'^(?:some|a|an|the|more)\s+'), '');
  return key;
}

/// Items from [wanted] that are not already on the list as an unticked
/// item in [existingUnticked] (compared with [shoppingItemKey]).
({List<String> toAdd, List<String> alreadyThere}) splitNewShoppingItems(
  List<String> wanted,
  Iterable<String> existingUnticked,
) {
  final existing = {for (final t in existingUnticked) shoppingItemKey(t)};
  final toAdd = <String>[];
  final already = <String>[];
  final seen = <String>{};
  for (final raw in wanted) {
    final item = raw.trim();
    if (item.isEmpty) continue;
    final key = shoppingItemKey(item);
    if (key.isEmpty || !seen.add(key)) continue;
    if (existing.contains(key)) {
      already.add(item);
    } else {
      toAdd.add(item);
    }
  }
  return (toAdd: toAdd, alreadyThere: already);
}

String _normalise(String raw) {
  return raw
      .replaceAll(RegExp('[’‘]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[\s.,!?]+|[\s.,!?]+$'), '');
}

/// Snackbar text after a voice add.
String shoppingAddedMessage(List<String> added, List<String> alreadyThere) {
  String join(List<String> xs) {
    if (xs.length <= 1) return xs.join();
    if (xs.length <= 4) {
      return '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
    }
    return '${xs.take(3).join(', ')} and ${xs.length - 3} more';
  }

  final parts = <String>[];
  if (added.isNotEmpty) parts.add('🛒 Added ${join(added)}');
  if (alreadyThere.isNotEmpty) {
    parts.add(
      '${join(alreadyThere)} ${alreadyThere.length == 1 ? 'was' : 'were'} already on the list',
    );
  }
  if (parts.isEmpty) return 'Nothing to add';
  return parts.join(' · ');
}
