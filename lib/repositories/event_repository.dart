import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';

class EventRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream all events for a hub
  Stream<List<EventModel>> streamEvents(String hubId) {
    return _db
        .collection('hubs')
        .doc(hubId)
        .collection('events')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EventModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Update an event
  Future<void> updateEvent(
    String hubId,
    String eventId,
    Map<String, dynamic> updates,
  ) async {
    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('events')
        .doc(eventId)
        .update(updates);
  }

  // Delete an event
  Future<void> deleteEvent(String hubId, String eventId) async {
    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('events')
        .doc(eventId)
        .delete();
  }

  // Batch Add (Perfect for your recurring events and Google Calendar imports!)
  Future<void> batchAddEvents(String hubId, List<EventModel> events) async {
    final WriteBatch batch = _db.batch();
    final collection = _db.collection('hubs').doc(hubId).collection('events');

    for (var event in events) {
      final docRef = collection.doc();
      batch.set(docRef, event.toMap());
    }
    await batch.commit();
  }
}
