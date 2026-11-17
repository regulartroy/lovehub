import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/shopping_voice.dart';

List<String>? items(String text) => parseShoppingVoiceCommand(text)?.items;

void main() {
  group('parseShoppingVoiceCommand', () {
    test('add X and Y to my shopping list', () {
      expect(items('add milk and eggs to my shopping list'), ['Milk', 'Eggs']);
      expect(items('Add milk and eggs to my shopping list.'), ['Milk', 'Eggs']);
    });

    test('commas, ampersands and plus', () {
      expect(items('add bread, butter & jam to shopping'), [
        'Bread',
        'Butter',
        'Jam',
      ]);
      expect(items('add apples, pears, and bananas to the list'), [
        'Apples',
        'Pears',
        'Bananas',
      ]);
      expect(items('add cheese plus crackers to the shopping list'), [
        'Cheese',
        'Crackers',
      ]);
    });

    test('put / stick / pop on the list', () {
      expect(items('put bread on the shopping list'), ['Bread']);
      expect(items('stick some loo roll on the list please'), ['Loo roll']);
      expect(items('pop a lemon onto the shopping list'), ['Lemon']);
      expect(items('put teabags in the shopping'), ['Teabags']);
    });

    test('strips filler and politeness', () {
      expect(
        items(
          'can you please add some milk and the eggs to our shopping list please',
        ),
        ['Milk', 'Eggs'],
      );
      expect(items('could you add more coffee to shopping'), ['Coffee']);
      expect(items('add milk as well to the shopping list'), ['Milk']);
    });

    test('target before the items', () {
      expect(items('add to the shopping list milk and eggs'), ['Milk', 'Eggs']);
      expect(items('shopping list: milk, eggs'), ['Milk', 'Eggs']);
      expect(items('shopping list add bin bags'), ['Bin bags']);
    });

    test('keeps quantities and multi-word items', () {
      expect(items('add 2 pints of milk and a dozen eggs to shopping'), [
        '2 pints of milk',
        'Dozen eggs',
      ]);
      expect(items('add washing up liquid to the shopping list'), [
        'Washing up liquid',
      ]);
    });

    test('keeps common "and" products together', () {
      expect(items('add salt and vinegar crisps and milk to shopping'), [
        'Salt and vinegar crisps',
        'Milk',
      ]);
      expect(items('add fish and chips to the list'), ['Fish and chips']);
    });

    test('removes duplicates said twice', () {
      expect(items('add milk, eggs and milk to shopping'), ['Milk', 'Eggs']);
    });

    test('curly apostrophes from speech', () {
      expect(items('we’re out of eggs'), ['Eggs']);
    });

    test('loose phrasings are recognised but not explicit', () {
      final need = parseShoppingVoiceCommand('we need milk and bread')!;
      expect(need.items, ['Milk', 'Bread']);
      expect(need.explicit, isFalse);
      final buy = parseShoppingVoiceCommand('buy dog food')!;
      expect(buy.items, ['Dog food']);
      expect(buy.explicit, isFalse);
      expect(
        parseShoppingVoiceCommand('add milk to shopping')!.explicit,
        isTrue,
      );
    });

    test('names the list but no items', () {
      final cmd = parseShoppingVoiceCommand('add to my shopping list');
      expect(cmd, isNotNull);
      expect(cmd!.items, isEmpty);
    });

    test('calendar questions are not shopping', () {
      expect(parseShoppingVoiceCommand("what's on today"), isNull);
      expect(parseShoppingVoiceCommand('the week of 23 October'), isNull);
      expect(parseShoppingVoiceCommand('20 to 25 October'), isNull);
      expect(parseShoppingVoiceCommand('what am I doing on Friday'), isNull);
      expect(parseShoppingVoiceCommand(''), isNull);
      expect(parseShoppingVoiceCommand('add dentist to the calendar'), isNull);
    });
  });

  group('tidyShoppingItem', () {
    test('capitalises and strips', () {
      expect(tidyShoppingItem('  some milk please '), 'Milk');
      expect(tidyShoppingItem('the'), '');
      expect(tidyShoppingItem('iPhone charger'), 'iPhone charger');
      expect(tidyShoppingItem('Tesco bags'), 'Tesco bags');
    });
  });

  group('splitNewShoppingItems', () {
    test('skips items already on the list unticked, case-insensitively', () {
      final result = splitNewShoppingItems(
        ['Milk', 'Eggs', 'bread', 'Bread'],
        ['milk', 'Butter', 'The bread'],
      );
      expect(result.toAdd, ['Eggs']);
      expect(result.alreadyThere, ['Milk', 'bread']);
    });

    test('ignores blanks', () {
      final result = splitNewShoppingItems(['  ', 'Jam'], const []);
      expect(result.toAdd, ['Jam']);
      expect(result.alreadyThere, isEmpty);
    });
  });

  group('shoppingAddedMessage', () {
    test('lists added and existing items', () {
      expect(
        shoppingAddedMessage(['Milk', 'Eggs'], []),
        '🛒 Added Milk and Eggs',
      );
      expect(
        shoppingAddedMessage(['Eggs'], ['Milk']),
        '🛒 Added Eggs · Milk was already on the list',
      );
      expect(shoppingAddedMessage([], []), 'Nothing to add');
      expect(
        shoppingAddedMessage(['A', 'B', 'C', 'D', 'E'], []),
        '🛒 Added A, B, C and 2 more',
      );
    });
  });
}
