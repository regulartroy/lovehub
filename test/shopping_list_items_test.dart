import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/task_model.dart';
import 'package:lovehub/services/shopping_aisle_sort.dart';
import 'package:lovehub/services/shopping_list_items.dart';

void main() {
  test('recipe lines keep their quantities and land in aisle order', () {
    final tasks = shoppingTasksForIngredients([
      '1 kilogram chicken thighs (skin on and bone in)',
      '250 grams basmati rice',
      '300 grams Greek yoghurt (I use 10% fat)',
      'a handful of coriander leaves',
      'a pinch of saffron',
      '   ',
    ]);

    expect(tasks, hasLength(5));
    expect(tasks.map((task) => task.listName), everyElement('Shopping'));
    expect(tasks.map((task) => task.assignedTo), everyElement('shared'));
    expect(tasks.map((task) => task.text).first, contains('1 kilogram'));
    expect(tasks.map((task) => task.sortIndex).toList(), [
      ShoppingAisle.meatFish.sortIndex,
      ShoppingAisle.tinsDry.sortIndex,
      ShoppingAisle.dairyEggs.sortIndex,
      ShoppingAisle.fruitVeg.sortIndex,
      ShoppingAisle.other.sortIndex,
    ]);
  });

  test('a shopping task writes its aisle index', () {
    final task = Task(
      id: '',
      text: 'basmati rice',
      listName: 'Shopping',
      sortIndex: ShoppingAisle.tinsDry.sortIndex,
    );
    expect(task.toMap()['sortIndex'], ShoppingAisle.tinsDry.sortIndex);
    expect(task.toMap().containsKey('createdAt'), isTrue);

    final other = Task(id: '', text: 'Call the vet');
    expect(other.toMap().containsKey('sortIndex'), isFalse);
  });
}
