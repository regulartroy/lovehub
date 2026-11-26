import '../models/event_model.dart';

export 'event_store_core.dart';

import 'event_store_core.dart';

String eventDedupeKey(EventModel event) {
  return eventDedupeKeyFor(
    id: event.id,
    category: event.category,
    assignedTo: event.assignedTo,
    ownerId: event.ownerId,
    source: event.source,
    externalId: event.externalId,
  );
}

/// Merge live hub-shared events, preview-only joint edits, and person-owned
/// events. Preview docs with [EventModel.previewDeleted] hide the live event
/// with the same key. Person events win over hub copies of the same key.
List<EventModel> mergeVisibleEvents({
  required List<EventModel> liveShared,
  required List<EventModel> previewShared,
  required List<EventModel> personEvents,
}) {
  return mergeVisibleEventRecords<EventModel>(
    liveShared: liveShared,
    previewShared: previewShared,
    personEvents: personEvents,
    isJoint: (event) =>
        isHubJointEvent(category: event.category, assignedTo: event.assignedTo),
    isDeleted: (event) => event.previewDeleted,
    keyOf: eventDedupeKey,
  );
}

/// Document map for dashboard/feed widgets, including the document id.
Map<String, dynamic> eventModelToDocumentMap(EventModel event) {
  return {'id': event.id, ...event.toMap()};
}
