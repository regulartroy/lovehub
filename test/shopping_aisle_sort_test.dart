import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/shopping_aisle_sort.dart';

void main() {
  group('categoriseShoppingItem', () {
    final cases = <String, ShoppingAisle>{
      'Bananas': ShoppingAisle.fruitVeg,
      'cherry tomatoes': ShoppingAisle.fruitVeg,
      'Potatoes': ShoppingAisle.fruitVeg,
      'iceberg lettuce': ShoppingAisle.fruitVeg,
      'Watermelon': ShoppingAisle.fruitVeg,
      'Sourdough loaf': ShoppingAisle.bakery,
      'crumpets': ShoppingAisle.bakery,
      'Chicken thighs': ShoppingAisle.meatFish,
      'beef mince': ShoppingAisle.meatFish,
      'semi skimmed milk': ShoppingAisle.dairyEggs,
      'Eggs x12': ShoppingAisle.dairyEggs,
      'Greek yoghurt': ShoppingAisle.dairyEggs,
      'hummus': ShoppingAisle.snacks,
      'Ham': ShoppingAisle.chilled,
      'Ice cream': ShoppingAisle.frozen,
      'frozen peas': ShoppingAisle.frozen,
      'fish fingers': ShoppingAisle.frozen,
      'Baked beans': ShoppingAisle.tinsDry,
      'Pasta': ShoppingAisle.tinsDry,
      'basmati rice': ShoppingAisle.tinsDry,
      'Weetabix': ShoppingAisle.breakfast,
      'porridge oats': ShoppingAisle.breakfast,
      'Crisps': ShoppingAisle.snacks,
      'chocolate': ShoppingAisle.snacks,
      'Orange juice': ShoppingAisle.drinks,
      'tea bags': ShoppingAisle.drinks,
      'Red wine': ShoppingAisle.alcohol,
      'Gin': ShoppingAisle.alcohol,
      'Kitchen roll': ShoppingAisle.household,
      'Toilet roll': ShoppingAisle.household,
      'washing up liquid': ShoppingAisle.household,
      'tin foil': ShoppingAisle.household,
      'Toothpaste': ShoppingAisle.toiletries,
      'sun cream': ShoppingAisle.toiletries,
      'Paracetamol': ShoppingAisle.toiletries,
      'Dog food': ShoppingAisle.pet,
      'Enzo treats': ShoppingAisle.pet,
      'poo bags': ShoppingAisle.pet,
      'Nappies': ShoppingAisle.baby,
      'birthday card': ShoppingAisle.other,
      '': ShoppingAisle.other,
    };
    cases.forEach((text, aisle) {
      test('"$text" -> ${aisle.label}', () {
        expect(categoriseShoppingItem(text), aisle);
      });
    });

    test('aisle order follows a walk through the shop', () {
      final idx = ShoppingAisle.values.map((a) => a.sortIndex).toList();
      expect(idx, [...idx]..sort());
      expect(ShoppingAisle.other.sortIndex, lessThan(999));
    });
  });

  group('smartSortShoppingIndexes', () {
    final items = [('a', 'Bananas'), ('b', 'Dog food'), ('c', 'Milk')];

    test('falls back to local sort when AI throws (e.g. 403)', () async {
      final r = await smartSortShoppingIndexes(
        items,
        aiSort: () async => throw Exception('403 PERMISSION_DENIED'),
      );
      expect(r.usedFallback, isTrue);
      expect(r.sortIndexes, {'a': 10, 'b': 140, 'c': 40});
    });

    test('falls back when AI times out', () async {
      final r = await smartSortShoppingIndexes(
        items,
        aiSort: () => Completer<Map<String, int>>().future,
        timeout: const Duration(milliseconds: 20),
      );
      expect(r.usedFallback, isTrue);
      expect(r.sortIndexes['b'], 140);
    });

    test('falls back when AI returns nothing usable', () async {
      final r = await smartSortShoppingIndexes(
        items,
        aiSort: () async => {'zzz': 1},
      );
      expect(r.usedFallback, isTrue);
    });

    test('uses AI answer and fills omitted ids locally', () async {
      final r = await smartSortShoppingIndexes(
        items,
        aiSort: () async => {'a': 5, 'c': 6},
      );
      expect(r.usedFallback, isFalse);
      expect(r.sortIndexes, {'a': 5, 'b': 140, 'c': 6});
    });
  });
}
