import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../services/shopping_list_items.dart';
import '../services/hub_collection.dart';
import '../services/shopping_aisle_sort.dart';
import '../services/shopping_voice.dart';

class TaskRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream all tasks for a hub
  Stream<List<Task>> streamTasks(String hubId) {
    return _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList(),
        );
  }

  // Add multiple tasks at once (Batching!)
  Future<void> addTasks(String hubId, List<Task> tasks) async {
    final WriteBatch batch = _db.batch();
    final collection = _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items');

    for (var task in tasks) {
      final docRef = collection.doc();
      batch.set(docRef, task.toMap());
    }
    await batch.commit();
  }

  // Add missing ingredients (Used by Food Screen)
  Future<void> addMissingIngredientsToShoppingList(
    String hubId,
    List<String> ingredients,
  ) async {
    await addTasks(hubId, shoppingTasksForIngredients(ingredients));
  }

  /// Adds [items] to the hub's Shopping list, skipping any that are already
  /// on it and unticked. New rows get the aisle `sortIndex`, like recipe
  /// ingredients, so they land in shop order straight away.
  Future<({List<String> added, List<String> alreadyThere})> addShoppingItems(
    String hubId,
    List<String> items, {
    String? createdBy,
  }) async {
    final snap = await _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .where('listName', isEqualTo: 'Shopping')
        .get();
    final unticked = <String>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isDone'] == true) continue;
      final text = data['text'];
      if (text is String) unticked.add(text);
    }
    final split = splitNewShoppingItems(items, unticked);
    if (split.toAdd.isNotEmpty) {
      await addTasks(hubId, [
        for (final text in split.toAdd)
          Task(
            id: '',
            text: text,
            listName: 'Shopping',
            assignedTo: 'shared',
            createdBy: createdBy,
            sortIndex: categoriseShoppingItem(text).sortIndex,
          ),
      ]);
    }
    return (added: split.toAdd, alreadyThere: split.alreadyThere);
  }

  // Toggle completion
  Future<void> toggleTaskCompletion(
    String hubId,
    String taskId,
    bool isDone,
  ) async {
    await _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .doc(taskId)
        .update({'isDone': isDone});
  }

  // Reschedule
  Future<void> updateDueDate(
    String hubId,
    String taskId,
    DateTime newDate,
  ) async {
    await _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .doc(taskId)
        .update({'dueDate': Timestamp.fromDate(newDate)});
  }

  // Delete a single task
  Future<void> deleteTask(String hubId, String taskId) async {
    await _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .doc(taskId)
        .delete();
  }

  // Delete an entire list
  Future<void> deleteList(String hubId, String listName) async {
    final snap = await _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('items')
        .where('listName', isEqualTo: listName)
        .get();

    final batch = _db.batch();
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
