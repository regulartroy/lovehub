import 'package:cloud_firestore/cloud_firestore.dart';

import '../event_import/imported_event.dart';
import '../models/event_model.dart';

/// Writes event documents by id. Implementations merge so omitted fields
/// (notably `gcalId`) survive a retry.
abstract class EventBatchWriter {
  Future<void> commitMerges(
    String hubId,
    Map<String, Map<String, dynamic>> docs,
  );

  /// Patch one existing document. Throws [EventImportException] when it is missing.
  Future<void> updateFields(
    String hubId,
    String eventId,
    Map<String, dynamic> fields,
  );
}

class FirestoreEventBatchWriter implements EventBatchWriter {
  FirestoreEventBatchWriter(this._db);

  final FirebaseFirestore _db;
  static const int maxBatch = 400;

  @override
  Future<void> commitMerges(
    String hubId,
    Map<String, Map<String, dynamic>> docs,
  ) async {
    final collection = _db.collection('hubs').doc(hubId).collection('events');
    final entries = docs.entries.toList();
    for (var i = 0; i < entries.length; i += maxBatch) {
      final end = i + maxBatch > entries.length ? entries.length : i + maxBatch;
      final batch = _db.batch();
      for (final entry in entries.sublist(i, end)) {
        batch.set(
          collection.doc(entry.key),
          entry.value,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  @override
  Future<void> updateFields(
    String hubId,
    String eventId,
    Map<String, dynamic> fields,
  ) async {
    final ref = _db
        .collection('hubs')
        .doc(hubId)
        .collection('events')
        .doc(eventId);
    try {
      await ref.update(fields);
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        throw EventImportException(
          'No event $eventId in hub $hubId. Import it before confirming.',
        );
      }
      rethrow;
    }
  }
}

/// Firestore field map for an imported event. Dates become [Timestamp]s.
/// `gcalId` is not included.
Map<String, dynamic> firestoreMapFromImport(
  ImportedEvent event, {
  String? ownerId,
}) {
  final fields = event.toImportFields(ownerId: ownerId);
  return fields.map((key, value) {
    if (value is DateTime) {
      return MapEntry(key, Timestamp.fromDate(value));
    }
    return MapEntry(key, value);
  });
}

class EventRepository {
  EventRepository({FirebaseFirestore? firestore, EventBatchWriter? writer})
    : _firestore = firestore,
      _writer = writer;

  final FirebaseFirestore? _firestore;
  final EventBatchWriter? _writer;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  EventBatchWriter get _batchWriter =>
      _writer ?? FirestoreEventBatchWriter(_db);

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

  // Batch Add (recurring events and Google Calendar imports).
  // Always mints new document ids — not idempotent. Work-bot imports use
  // [upsertImportedEvents] instead.
  Future<void> batchAddEvents(String hubId, List<EventModel> events) async {
    final WriteBatch batch = _db.batch();
    final collection = _db.collection('hubs').doc(hubId).collection('events');

    for (var event in events) {
      final docRef = collection.doc();
      batch.set(docRef, event.toMap());
    }
    await batch.commit();
  }

  /// Idempotent bulk upsert. Document id is [ImportedEvent.docId]
  /// (`source:externalId`). A retry merges into the same doc.
  Future<void> upsertImportedEvents(
    String hubId,
    List<ImportedEvent> events, {
    String? ownerId,
  }) async {
    validateHubId(hubId);
    if (events.isEmpty) return;
    final docs = <String, Map<String, dynamic>>{};
    for (final event in events) {
      docs[event.docId] = firestoreMapFromImport(event, ownerId: ownerId);
    }
    await _batchWriter.commitMerges(hubId.trim(), docs);
  }

  /// Flip one imported event to confirmed without rewriting the rest of it.
  /// CLI `--confirm source:externalId` uses this.
  Future<void> confirmImportedEvent(
    String hubId,
    String source,
    String externalId,
  ) async {
    final target = parseConfirmTarget('$source:$externalId');
    await confirmEvent(hubId, target.docId);
  }

  /// In-app confirm. Sets `status` to confirmed on an existing document and
  /// leaves every other field alone — the same write as CLI `--confirm`.
  Future<void> confirmEvent(String hubId, String eventId) {
    return _setEventStatus(
      hubId,
      eventId,
      eventStatusConfirmed,
      emptyIdMessage: 'Event id is required to confirm.',
    );
  }

  /// In-app mark tentative. Sets `status` to tentative on an existing document
  /// and leaves every other field alone — the reverse of [confirmEvent].
  Future<void> markEventTentative(String hubId, String eventId) {
    return _setEventStatus(
      hubId,
      eventId,
      eventStatusTentative,
      emptyIdMessage: 'Event id is required to mark tentative.',
    );
  }

  Future<void> _setEventStatus(
    String hubId,
    String eventId,
    String status, {
    required String emptyIdMessage,
  }) async {
    validateHubId(hubId);
    final id = eventId.trim();
    if (id.isEmpty || id.contains('/')) {
      throw EventImportException(emptyIdMessage);
    }
    await _batchWriter.updateFields(hubId.trim(), id, {'status': status});
  }
}
