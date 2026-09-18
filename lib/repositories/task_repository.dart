import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';

class TaskRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream all tasks for a hub
  Stream<List<Task>> streamTasks(String hubId) {
    return _db
        .collection('hubs')
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
    final collection = _db.collection('hubs').doc(hubId).collection('items');

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
    final tasks = ingredients
        .map(
          (item) => Task(
            id: '',
            text: item,
            listName: 'Shopping',
            assignedTo: 'shared',
          ),
        )
        .toList();
    await addTasks(hubId, tasks);
  }

  // Toggle completion
  Future<void> toggleTaskCompletion(
    String hubId,
    String taskId,
    bool isDone,
  ) async {
    await _db
        .collection('hubs')
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
        .collection('hubs')
        .doc(hubId)
        .collection('items')
        .doc(taskId)
        .update({'dueDate': Timestamp.fromDate(newDate)});
  }

  // Delete a single task
  Future<void> deleteTask(String hubId, String taskId) async {
    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('items')
        .doc(taskId)
        .delete();
  }

  // Delete an entire list
  Future<void> deleteList(String hubId, String listName) async {
    final snap = await _db
        .collection('hubs')
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
