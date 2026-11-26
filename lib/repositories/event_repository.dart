import 'package:cloud_firestore/cloud_firestore.dart';

import '../event_import/imported_event.dart';
import '../models/event_model.dart';
import '../services/event_store.dart';
import '../services/hub_collection.dart';
import '../services/person_event_stream.dart';

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
    final collection = _db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('events');
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
        .collection(kHubsCollection)
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

/// Context needed to route a write when [EventStoreMode.person] is on.
/// Live (`hub`) writes ignore this and keep going to `sharedHubs/{hub}/events`.
class EventWriteHint {
  const EventWriteHint({
    this.ownerId,
    this.category = 'general',
    this.assignedTo = 'shared',
    this.viewerUid,
  });

  final String? ownerId;
  final String category;
  final String assignedTo;
  final String? viewerUid;

  factory EventWriteHint.fromEvent(EventModel event, {String? viewerUid}) {
    return EventWriteHint(
      ownerId: event.ownerId,
      category: event.category,
      assignedTo: event.assignedTo,
      viewerUid: viewerUid,
    );
  }

  factory EventWriteHint.fromMap(
    Map<String, dynamic> data, {
    String? viewerUid,
  }) {
    return EventWriteHint(
      ownerId: data['ownerId'] as String?,
      category: (data['category'] as String?) ?? 'general',
      assignedTo: (data['assignedTo'] as String?) ?? 'shared',
      viewerUid: viewerUid,
    );
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
  EventRepository({
    FirebaseFirestore? firestore,
    EventBatchWriter? writer,
    EventStoreMode? mode,
  }) : _firestore = firestore,
       _writer = writer,
       mode = mode ?? compileTimeEventStoreMode;

  final FirebaseFirestore? _firestore;
  final EventBatchWriter? _writer;
  final EventStoreMode mode;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  EventBatchWriter get _batchWriter =>
      _writer ?? FirestoreEventBatchWriter(_db);

  bool get isPersonStore => mode == EventStoreMode.person;

  // Stream all events for a hub
  Stream<List<EventModel>> streamEvents(String hubId, {String? viewerUid}) {
    if (isPersonStore) {
      final uid = viewerUid?.trim() ?? '';
      if (uid.isEmpty) {
        throw ArgumentError('viewerUid is required when EVENT_STORE=person');
      }
      return streamPersonHubEvents(db: _db, hubId: hubId, viewerUid: uid);
    }
    return _db
        .collection(kHubsCollection)
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
    Map<String, dynamic> updates, {
    EventWriteHint? hint,
  }) async {
    final ref = _resolveWriteRef(hubId: hubId, eventId: eventId, hint: hint);
    if (isPersonStore &&
        eventWriteTarget(
              mode: mode,
              category: hint!.category,
              assignedTo: hint.assignedTo,
            ) ==
            EventWriteTarget.previewSharedEvents) {
      final payload = Map<String, dynamic>.from(updates)
        ..[kPreviewDeletedField] = false;
      await ref.set(payload, SetOptions(merge: true));
      return;
    }
    await ref.update(updates);
  }

  // Delete an event
  Future<void> deleteEvent(
    String hubId,
    String eventId, {
    EventWriteHint? hint,
  }) async {
    final ref = _resolveWriteRef(hubId: hubId, eventId: eventId, hint: hint);
    if (isPersonStore &&
        eventWriteTarget(
              mode: mode,
              category: hint!.category,
              assignedTo: hint.assignedTo,
            ) ==
            EventWriteTarget.previewSharedEvents) {
      await ref.set({kPreviewDeletedField: true}, SetOptions(merge: true));
      return;
    }
    await ref.delete();
  }

  // Batch Add (recurring events and Google Calendar imports).
  // Always mints new document ids — not idempotent. Work-bot imports use
  // [upsertImportedEvents] instead.
  Future<void> batchAddEvents(
    String hubId,
    List<EventModel> events, {
    String? viewerUid,
  }) async {
    if (events.isEmpty) return;
    if (!isPersonStore) {
      final WriteBatch batch = _db.batch();
      final collection = _db
          .collection(kHubsCollection)
          .doc(hubId)
          .collection('events');

      for (var event in events) {
        final docRef = collection.doc();
        batch.set(docRef, event.toMap());
      }
      await batch.commit();
      return;
    }

    final WriteBatch batch = _db.batch();
    for (final event in events) {
      final hint = EventWriteHint.fromEvent(event, viewerUid: viewerUid);
      final collection = _resolveWriteRef(
        hubId: hubId,
        eventId: '_',
        hint: hint,
      ).parent;
      final data = Map<String, dynamic>.from(event.toMap());
      if (eventWriteTarget(
            mode: mode,
            category: event.category,
            assignedTo: event.assignedTo,
          ) ==
          EventWriteTarget.personEvents) {
        data['ownerId'] = personEventOwnerUid(
          ownerId: event.ownerId,
          viewerUid: viewerUid ?? '',
        );
      }
      batch.set(collection.doc(), data);
    }
    await batch.commit();
  }

  /// Add one event and return its new document id.
  Future<String> addEvent(
    String hubId,
    Map<String, dynamic> data, {
    EventWriteHint? hint,
  }) async {
    if (!isPersonStore) {
      final doc = await _db
          .collection(kHubsCollection)
          .doc(hubId)
          .collection('events')
          .add(data);
      return doc.id;
    }
    final resolved = hint ?? EventWriteHint.fromMap(data);
    final collection = _resolveWriteRef(
      hubId: hubId,
      eventId: '_',
      hint: resolved,
    ).parent;
    final payload = Map<String, dynamic>.from(data);
    if (eventWriteTarget(
          mode: mode,
          category: resolved.category,
          assignedTo: resolved.assignedTo,
        ) ==
        EventWriteTarget.personEvents) {
      payload['ownerId'] = personEventOwnerUid(
        ownerId: resolved.ownerId,
        viewerUid: resolved.viewerUid ?? '',
      );
    }
    final doc = await collection.add(payload);
    return doc.id;
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
    if (!isPersonStore) {
      await _batchWriter.commitMerges(hubId.trim(), docs);
      return;
    }
    final uid = ownerId?.trim() ?? '';
    if (uid.isEmpty) {
      throw EventImportException(
        'ownerId is required to upsert into the person event store.',
      );
    }
    await _commitMergesTo(
      _db.collection('users').doc(uid).collection('events'),
      docs,
    );
  }

  /// Flip one imported event to confirmed without rewriting the rest of it.
  /// CLI `--confirm source:externalId` uses this.
  Future<void> confirmImportedEvent(
    String hubId,
    String source,
    String externalId, {
    EventWriteHint? hint,
  }) async {
    final target = parseConfirmTarget('$source:$externalId');
    await confirmEvent(hubId, target.docId, hint: hint);
  }

  /// In-app confirm. Sets `status` to confirmed on an existing document and
  /// leaves every other field alone — the same write as CLI `--confirm`.
  Future<void> confirmEvent(
    String hubId,
    String eventId, {
    EventWriteHint? hint,
  }) {
    return _setEventStatus(
      hubId,
      eventId,
      eventStatusConfirmed,
      emptyIdMessage: 'Event id is required to confirm.',
      hint: hint,
    );
  }

  /// In-app mark tentative. Sets `status` to tentative on an existing document
  /// and leaves every other field alone — the reverse of [confirmEvent].
  Future<void> markEventTentative(
    String hubId,
    String eventId, {
    EventWriteHint? hint,
  }) {
    return _setEventStatus(
      hubId,
      eventId,
      eventStatusTentative,
      emptyIdMessage: 'Event id is required to mark tentative.',
      hint: hint,
    );
  }

  Future<void> _setEventStatus(
    String hubId,
    String eventId,
    String status, {
    required String emptyIdMessage,
    EventWriteHint? hint,
  }) async {
    validateHubId(hubId);
    final id = eventId.trim();
    if (id.isEmpty || id.contains('/')) {
      throw EventImportException(emptyIdMessage);
    }
    if (!isPersonStore) {
      await _batchWriter.updateFields(hubId.trim(), id, {'status': status});
      return;
    }
    await updateEvent(hubId, id, {'status': status}, hint: hint);
  }

  Future<void> _commitMergesTo(
    CollectionReference<Map<String, dynamic>> collection,
    Map<String, Map<String, dynamic>> docs,
  ) async {
    final entries = docs.entries.toList();
    const maxBatch = FirestoreEventBatchWriter.maxBatch;
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

  DocumentReference<Map<String, dynamic>> _resolveWriteRef({
    required String hubId,
    required String eventId,
    required EventWriteHint? hint,
  }) {
    if (!isPersonStore) {
      return _db
          .collection(kHubsCollection)
          .doc(hubId)
          .collection('events')
          .doc(eventId);
    }
    if (hint == null) {
      throw StateError(
        'Event write hint is required when EVENT_STORE=person, '
        'so preview builds never write to live sharedHubs events.',
      );
    }
    final target = eventWriteTarget(
      mode: mode,
      category: hint.category,
      assignedTo: hint.assignedTo,
    );
    switch (target) {
      case EventWriteTarget.hubEvents:
        throw StateError(
          'EVENT_STORE=person must not write to live sharedHubs events.',
        );
      case EventWriteTarget.previewSharedEvents:
        return _db
            .collection(kHubsCollection)
            .doc(hubId)
            .collection(kPreviewSharedEventsCollection)
            .doc(eventId);
      case EventWriteTarget.personEvents:
        final owner = personEventOwnerUid(
          ownerId: hint.ownerId,
          viewerUid: hint.viewerUid ?? '',
        );
        if (owner.isEmpty) {
          throw StateError(
            'viewerUid is required to write a person-owned event.',
          );
        }
        return _db
            .collection('users')
            .doc(owner)
            .collection('events')
            .doc(eventId);
    }
  }
}
