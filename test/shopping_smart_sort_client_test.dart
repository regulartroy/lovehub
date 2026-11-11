import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/shopping_aisle_sort.dart';
import 'package:lovehub/services/shopping_smart_sort_client.dart';

void main() {
  test('sortIndexesFromCallable reads a map and ignores unknown ids', () {
    final allowed = {'a', 'b', 'c'};
    expect(
      sortIndexesFromCallable({
        'sortIndexes': {'a': 10, 'b': 140.9, 'zzz': 1, 'c': 0},
      }, allowed),
      {'a': 10, 'b': 140},
    );
  });

  test('sortIndexesFromCallable also accepts a list of rows', () {
    final allowed = {'a', 'b'};
    expect(
      sortIndexesFromCallable([
        {'id': 'a', 'sortIndex': 12},
        {'id': 'b', 'sortIndex': 140},
      ], allowed),
      {'a': 12, 'b': 140},
    );
  });

  test(
    'callSmartSortShopping sends hub and items and returns indexes',
    () async {
      late Map<String, dynamic> sent;
      final result = await callSmartSortShopping(
        hubId: 'hub1',
        items: [('a', 'Bananas'), ('b', ''), ('c', 'Milk')],
        call: (payload) async {
          sent = payload;
          return {
            'sortIndexes': {'a': 10, 'c': 40},
          };
        },
      );
      expect(sent['hubId'], 'hub1');
      expect(sent['items'], [
        {'id': 'a', 'text': 'Bananas'},
        {'id': 'c', 'text': 'Milk'},
      ]);
      expect(result, {'a': 10, 'c': 40});
    },
  );

  test('callSmartSortShopping rejects an empty hub or empty payload', () async {
    expect(
      () => callSmartSortShopping(hubId: ' ', items: [('a', 'Milk')]),
      throwsA(isA<SmartSortException>()),
    );
    expect(
      () => callSmartSortShopping(hubId: 'hub1', items: [('a', '   ')]),
      throwsA(isA<SmartSortException>()),
    );
  });

  test('callSmartSortShopping caps the payload at smartSortMaxItems', () async {
    final items = [
      for (var i = 0; i < smartSortMaxItems + 5; i++) ('id$i', 'Milk $i'),
    ];
    late Map<String, dynamic> sent;
    await callSmartSortShopping(
      hubId: 'hub1',
      items: items,
      call: (payload) async {
        sent = payload;
        final first = (payload['items'] as List).first as Map;
        return {
          'sortIndexes': {first['id']: 40},
        };
      },
    );
    expect((sent['items'] as List).length, smartSortMaxItems);
  });

  test(
    'smartSortShoppingIndexes uses the function result and fills gaps',
    () async {
      final result = await smartSortShoppingIndexes(
        [('a', 'Bananas'), ('b', 'Dog food'), ('c', 'Milk')],
        aiSort: () => callSmartSortShopping(
          hubId: 'hub1',
          items: [('a', 'Bananas'), ('b', 'Dog food'), ('c', 'Milk')],
          call: (_) async => {
            'sortIndexes': {'a': 12, 'c': 41},
          },
        ),
      );
      expect(result.usedFallback, isFalse);
      expect(result.sortIndexes, {'a': 12, 'b': 140, 'c': 41});
    },
  );

  test('smartSortShoppingIndexes falls back when the function fails', () async {
    final result = await smartSortShoppingIndexes(
      [('a', 'Bananas')],
      aiSort: () => callSmartSortShopping(
        hubId: 'hub1',
        items: [('a', 'Bananas')],
        call: (_) async =>
            throw SmartSortException("Couldn't sort the shopping list."),
      ),
    );
    expect(result.usedFallback, isTrue);
    expect(result.sortIndexes, {'a': 10});
  });

  test('messageForSmartSortCode covers the usual function errors', () {
    expect(
      messageForSmartSortCode('unauthenticated', null),
      'Sign in to sort the shopping list.',
    );
    expect(
      messageForSmartSortCode('not-found', null),
      contains('smartSortShopping'),
    );
    expect(
      messageForSmartSortCode('resource-exhausted', 'ignored'),
      startsWith('Too many sorts'),
    );
  });
}
