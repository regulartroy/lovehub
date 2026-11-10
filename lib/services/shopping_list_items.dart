import '../models/task_model.dart';
import 'shopping_aisle_sort.dart';

/// Shopping-list rows for a recipe's ingredient lines.
///
/// Each line keeps the recipe wording, quantity included, and gets the same
/// aisle [Task.sortIndex] the shopping list uses when Smart Sort is off.
List<Task> shoppingTasksForIngredients(List<String> ingredients) {
  final tasks = <Task>[];
  for (final raw in ingredients) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    tasks.add(
      Task(
        id: '',
        text: text,
        listName: 'Shopping',
        assignedTo: 'shared',
        sortIndex: categoriseShoppingItem(text).sortIndex,
      ),
    );
  }
  return tasks;
}
