import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'recipe_url.dart';

/// A recipe read from a page, ready to edit and save.
class ParsedRecipe {
  const ParsedRecipe({
    required this.title,
    required this.ingredients,
    required this.method,
    this.sourceUrl,
    this.source = 'json-ld',
    this.notes = const [],
  });

  final String title;
  final List<String> ingredients;
  final String method;

  /// Page the recipe was read from, when the import started from a link.
  final String? sourceUrl;

  /// `json-ld` or `microdata`.
  final String source;

  /// Gaps the cook should fill in before saving. Saving is still allowed.
  final List<String> notes;
}

class RecipePageParse {
  const RecipePageParse._({this.recipe, this.error});

  final ParsedRecipe? recipe;
  final String? error;

  bool get ok => recipe != null;
}

const _noRecipeMessage =
    "This page doesn't publish a recipe we can read. Try another link, or add it by hand.";
const _emptyRecipeMessage =
    "This page didn't include a title, ingredients, or method.";

/// Reads a schema.org Recipe from [html].
///
/// JSON-LD is used when it includes ingredients or method steps. Otherwise
/// the parser falls back to schema.org microdata (the markup Nigella publishes).
RecipePageParse parseRecipePage(String html, {String? pageUrl}) {
  final document = html_parser.parse(html);
  final fromJsonLd = _best(_recipesFromJsonLd(document, html));
  final jsonLdUsable = fromJsonLd != null && _hasBody(fromJsonLd);
  final chosen = jsonLdUsable
      ? fromJsonLd
      : _best(_recipesFromMicrodata(document)) ?? fromJsonLd;

  if (chosen == null) {
    return const RecipePageParse._(error: _noRecipeMessage);
  }
  if (!_hasAnything(chosen)) {
    return const RecipePageParse._(error: _emptyRecipeMessage);
  }

  final notes = <String>[
    if (chosen.title.isEmpty) 'Add a name before saving.',
    if (chosen.ingredients.isEmpty)
      'No ingredients were found. Add them before saving.',
    if (chosen.method.trim().isEmpty) 'No method was found.',
  ];
  return RecipePageParse._(
    recipe: ParsedRecipe(
      title: chosen.title,
      ingredients: chosen.ingredients,
      method: chosen.method,
      sourceUrl: pageUrl,
      source: chosen.marker,
      notes: notes,
    ),
  );
}

class _Draft {
  _Draft({
    required this.title,
    required this.ingredients,
    required this.method,
    required this.marker,
  });

  final String title;
  final List<String> ingredients;
  final String method;

  /// Temporary carrier so the caller knows which parser produced the draft.
  final String marker;
}

bool _hasBody(_Draft draft) =>
    draft.ingredients.isNotEmpty || draft.method.trim().isNotEmpty;

bool _hasAnything(_Draft draft) => draft.title.isNotEmpty || _hasBody(draft);

_Draft? _best(List<_Draft> drafts) {
  _Draft? winner;
  var winnerScore = -1;
  for (final draft in drafts) {
    final score = _score(draft);
    if (winner == null || score > winnerScore) {
      winner = draft;
      winnerScore = score;
    }
  }
  return winner;
}

int _score(_Draft draft) {
  return (draft.ingredients.isNotEmpty ? 1000 + draft.ingredients.length : 0) +
      (draft.method.trim().isNotEmpty ? 100 : 0) +
      (draft.title.isNotEmpty ? 1 : 0);
}

List<_Draft> _recipesFromJsonLd(Document document, String html) {
  final drafts = <_Draft>[];
  for (final block in _jsonLdBlocks(document, html)) {
    dynamic decoded;
    try {
      decoded = jsonDecode(_stripJsonLdComments(block));
    } catch (_) {
      continue;
    }
    final recipes = <Map<String, dynamic>>[];
    _collectRecipes(decoded, recipes, 0);
    for (final recipe in recipes) {
      drafts.add(_draftFromRecipeMap(recipe));
    }
  }
  return drafts;
}

List<String> _jsonLdBlocks(Document document, String html) {
  final pattern = RegExp(
    r'''<script\b[^>]*type\s*=\s*["']application/ld\+json[^"']*["'][^>]*>(.*?)</script>''',
    caseSensitive: false,
    dotAll: true,
  );
  final fromRaw = [
    for (final match in pattern.allMatches(html))
      if (match.group(1)!.trim().isNotEmpty) match.group(1)!.trim(),
  ];
  if (fromRaw.isNotEmpty) return fromRaw;

  final blocks = <String>[];
  for (final script in document.querySelectorAll('script')) {
    final type = (script.attributes['type'] ?? '')
        .toLowerCase()
        .replaceAll(' ', '');
    if (!type.contains('application/ld+json')) continue;
    final text = script.text.trim();
    if (text.isNotEmpty) blocks.add(text);
  }
  return blocks;
}

String _stripJsonLdComments(String raw) {
  var text = raw.trim();
  if (text.startsWith('<!--')) {
    text = text.replaceFirst(RegExp(r'^<!--'), '');
    text = text.replaceFirst(RegExp(r'-->\s*$'), '');
  }
  return text.trim();
}

void _collectRecipes(dynamic node, List<Map<String, dynamic>> out, int depth) {
  if (node == null || depth > 8) return;
  if (node is List) {
    for (final item in node) {
      _collectRecipes(item, out, depth + 1);
    }
    return;
  }
  if (node is! Map) return;
  final map = Map<String, dynamic>.from(node);
  if (_isType(map['@type'], 'Recipe')) out.add(map);
  _collectRecipes(map['@graph'], out, depth + 1);
  _collectRecipes(map['mainEntity'], out, depth + 1);
}

_Draft _draftFromRecipeMap(Map<String, dynamic> recipe) {
  final ingredients = _cleanList(
    _ingredientsFrom(recipe['recipeIngredient'] ?? recipe['ingredients']),
  );
  final steps = _stepsFromInstructions(recipe['recipeInstructions']);
  return _Draft(
    title: _cleanTitle(recipe['name'] ?? recipe['headline'] ?? ''),
    ingredients: ingredients,
    method: _formatMethod(steps),
    marker: 'json-ld',
  );
}

List<String> _ingredientsFrom(dynamic node) {
  if (node == null) return const [];
  if (node is String) {
    return node
        .split(RegExp(r'\r?\n+'))
        .map(_cleanIngredient)
        .where((line) => line.isNotEmpty)
        .toList();
  }
  if (node is List) {
    return [for (final item in node) ..._ingredientsFrom(item)];
  }
  if (node is Map) {
    final text = node['text'];
    if (text is String && text.trim().isNotEmpty) {
      return [_cleanIngredient(text)];
    }
    final value = node['value']?.toString().trim() ?? '';
    final name = node['name']?.toString().trim() ?? '';
    if (value.isNotEmpty && name.isNotEmpty && value != name) {
      return [_cleanIngredient('$value $name')];
    }
    final only = name.isNotEmpty ? name : value;
    if (only.isNotEmpty) return [_cleanIngredient(only)];
  }
  return const [];
}

class _Step {
  const _Step(this.text, {this.section});
  final String text;
  final String? section;
}

List<_Step> _stepsFromInstructions(dynamic node, {String? section}) {
  if (node == null) return const [];
  if (node is List) {
    return [
      for (final item in node) ..._stepsFromInstructions(item, section: section),
    ];
  }
  if (node is String) {
    return [
      for (final line in _stepsFromHtmlOrText(node)) _Step(line, section: section),
    ];
  }
  if (node is! Map) return const [];

  if (_isType(node['@type'], 'HowToSection')) {
    final name = _cleanTitle(node['name'] ?? '');
    final inner = node['itemListElement'] ?? node['recipeInstructions'];
    return _stepsFromInstructions(
      inner,
      section: name.isEmpty ? section : name,
    );
  }

  final steps = <_Step>[];
  final text = _stepText(node);
  if (text.isNotEmpty) steps.add(_Step(text, section: section));
  final nested = node['itemListElement'];
  if (nested != null) {
    steps.addAll(_stepsFromInstructions(nested, section: section));
  }
  return steps;
}

String _stepText(Map<dynamic, dynamic> node) {
  final text = node['text'];
  if (text is String && _cleanStep(text).isNotEmpty) return _cleanStep(text);
  final name = node['name'];
  if (name is String) return _cleanStep(name);
  return '';
}

List<String> _stepsFromHtmlOrText(String raw) {
  final fragment = html_parser.parseFragment(raw);
  final items = fragment.querySelectorAll('li');
  final leaves = items.where((item) => item.querySelector('li') == null);
  if (leaves.isNotEmpty) {
    return _cleanList([for (final item in leaves) _cleanStep(item.text)]);
  }
  final paragraphs = fragment.querySelectorAll('p');
  if (paragraphs.length > 1) {
    return _cleanList([
      for (final paragraph in paragraphs) _cleanStep(paragraph.text),
    ]);
  }
  final plain = _plain(raw);
  final lines = plain
      .split(RegExp(r'\r?\n+'))
      .map(_cleanStep)
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length > 1) return _dedupeConsecutive(lines);
  final single = _cleanStep(plain);
  return single.isEmpty ? const [] : [single];
}

String _formatMethod(List<_Step> steps) {
  final buffer = StringBuffer();
  String? currentHeading;
  var started = false;
  var number = 1;
  for (final step in _dedupeSteps(steps)) {
    final heading = _visibleHeading(step.section);
    if (started && heading != currentHeading) buffer.writeln();
    if (heading != currentHeading) {
      if (heading != null) buffer.writeln(heading);
      currentHeading = heading;
    }
    buffer.writeln('$number. ${step.text}');
    number++;
    started = true;
    if (number > 60) break;
  }
  return buffer.toString().trimRight();
}

List<_Step> _dedupeSteps(List<_Step> steps) {
  final kept = <_Step>[];
  for (final step in steps) {
    if (step.text.isEmpty) continue;
    if (kept.isNotEmpty &&
        kept.last.text == step.text &&
        kept.last.section == step.section) {
      continue;
    }
    kept.add(step);
  }
  return kept;
}

String? _visibleHeading(String? section) {
  if (section == null) return null;
  final text = section.trim();
  if (text.isEmpty) return null;
  final key = text.toLowerCase().replaceAll(RegExp(r'[:.\s]+$'), '');
  const generic = {
    'method',
    'instructions',
    'instruction',
    'directions',
    'direction',
    'steps',
    'preparation',
    'procedure',
    'how to',
    'howto',
  };
  if (generic.contains(key)) return null;
  return text;
}

List<_Draft> _recipesFromMicrodata(Document document) {
  final drafts = <_Draft>[];
  for (final root in document.querySelectorAll('[itemtype]')) {
    final type = root.attributes['itemtype'] ?? '';
    if (!type.toLowerCase().contains('schema.org/recipe')) continue;
    final ingredients = _cleanList([
      for (final element in _props(root, 'recipeingredient'))
        _cleanIngredient(_elementValue(element)),
    ]);
    final fallbackIngredients = ingredients.isNotEmpty
        ? ingredients
        : _cleanList([
            for (final element in _props(root, 'ingredients'))
              _cleanIngredient(_elementValue(element)),
          ]);
    final steps = <_Step>[];
    for (final element in _props(root, 'recipeinstructions')) {
      for (final line in _stepsFromElement(element)) {
        steps.add(_Step(line));
      }
    }
    drafts.add(
      _Draft(
        title: _microdataTitle(root),
        ingredients: fallbackIngredients,
        method: _formatMethod(steps),
        marker: 'microdata',
      ),
    );
  }
  return drafts;
}

String _microdataTitle(Element root) {
  Element? fallback;
  for (final element in _props(root, 'name')) {
    if (_underItemprop(element, root, const {
      'author',
      'publisher',
      'brand',
      'creator',
    })) {
      continue;
    }
    if (element.localName == 'h1') return _cleanTitle(_elementValue(element));
    fallback ??= element;
  }
  if (fallback == null) return '';
  return _cleanTitle(_elementValue(fallback));
}

Iterable<Element> _props(Element root, String name) sync* {
  for (final element in root.querySelectorAll('[itemprop]')) {
    final tokens = (element.attributes['itemprop'] ?? '')
        .toLowerCase()
        .split(RegExp(r'\s+'));
    if (!tokens.contains(name)) continue;
    if (_inNestedScope(element, root)) continue;
    yield element;
  }
}

bool _inNestedScope(Element element, Element root) {
  var parent = element.parent;
  while (parent != null && !identical(parent, root)) {
    if (parent.attributes.containsKey('itemscope')) return true;
    parent = parent.parent;
  }
  return false;
}

bool _underItemprop(Element element, Element root, Set<String> names) {
  var parent = element.parent;
  while (parent != null && !identical(parent, root)) {
    final prop = parent.attributes['itemprop'];
    if (prop != null) {
      final tokens = prop.toLowerCase().split(RegExp(r'\s+'));
      if (tokens.any(names.contains)) return true;
    }
    parent = parent.parent;
  }
  return false;
}

String _elementValue(Element element) {
  if (element.localName == 'meta' || element.localName == 'link') {
    final content = element.attributes['content'];
    if (content != null && content.trim().isNotEmpty) return content;
  }
  return element.text;
}

List<String> _stepsFromElement(Element element) {
  if (element.localName == 'meta') {
    final content = _cleanStep(element.attributes['content'] ?? '');
    return content.isEmpty ? const [] : [content];
  }
  final leaves = element
      .querySelectorAll('li')
      .where((item) => item.querySelector('li') == null);
  if (leaves.isNotEmpty) {
    return _cleanList([for (final item in leaves) _cleanStep(item.text)]);
  }
  final paragraphs = element.children.where((child) => child.localName == 'p');
  if (paragraphs.length > 1) {
    return _cleanList([
      for (final paragraph in paragraphs) _cleanStep(paragraph.text),
    ]);
  }
  return _stepsFromHtmlOrText(element.text);
}

List<String> _cleanList(Iterable<String> lines) {
  final capped = _dedupeConsecutive(
    lines.map((line) => line.trim()).where((line) => line.isNotEmpty),
  );
  if (capped.length <= 80) return capped;
  return capped.take(80).toList();
}

List<String> _dedupeConsecutive(Iterable<String> lines) {
  final kept = <String>[];
  for (final line in lines) {
    if (kept.isNotEmpty && kept.last == line) continue;
    kept.add(line);
  }
  return kept;
}

String _cleanTitle(Object? raw) => _collapse(_plain(raw?.toString() ?? ''), 180);

String _cleanIngredient(String raw) {
  var text = _collapse(_plain(raw), 300);
  text = text.replaceFirst(RegExp(r'^[\-\*\u2022\u00b7\u2013\u2014\u2219]+\s*'), '');
  return text.trim();
}

String _cleanStep(String raw) {
  var text = _collapse(_plain(raw), 4000);
  text = text.replaceFirst(
    RegExp(r'^step\s+\d+\s*[:.\-–)]?\s*', caseSensitive: false),
    '',
  );
  text = text.replaceFirst(RegExp(r'^\d+\s*[:.)\-–]\s*'), '');
  text = text.replaceFirst(RegExp(r'^[\-\*\u2022\u00b7]+\s*'), '');
  return text.trim();
}

String _plain(String raw) {
  if (!raw.contains('<') && !raw.contains('&')) return raw;
  return html_parser.parseFragment(raw).text ?? '';
}

String _collapse(String raw, int max) {
  var text = raw
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\u200b\u200c\u200d\ufeff]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return shortenAtBoundary(text, max);
}

/// Returns [text] unchanged when it fits in [max] characters. Otherwise cuts
/// it at the last sentence end that fits, or failing that the last whole
/// word (with an ellipsis). Never cuts inside a word.
String shortenAtBoundary(String text, int max) {
  if (text.length <= max) return text;
  final window = text.substring(0, max + 1);
  final sentenceEnd = RegExp(r'[.!?][)"\u201d\u2019]?(?=\s)');
  var cut = -1;
  for (final match in sentenceEnd.allMatches(window)) {
    if (match.end <= max) cut = match.end;
  }
  if (cut >= max ~/ 2) return text.substring(0, cut).trim();
  final space = window.lastIndexOf(RegExp(r'\s'));
  if (space > 0) return '${text.substring(0, space).trimRight()}\u2026';
  // A single word longer than [max]: keep it whole rather than split it.
  final next = text.indexOf(RegExp(r'\s'), max);
  return next < 0 ? text : '${text.substring(0, next)}\u2026';
}

bool _isType(dynamic type, String want) {
  final types = type is List ? type : [type];
  for (final item in types) {
    if (item is! String) continue;
    final tail = item.split('/').last.split('#').last.toLowerCase();
    if (tail == want.toLowerCase()) return true;
  }
  return false;
}

/// Host shown next to an imported recipe. Safe for a missing or odd URL.
String importedRecipeHost(String? url) {
  if (url == null || url.trim().isEmpty) return '';
  return recipeSourceLabel(url);
}
