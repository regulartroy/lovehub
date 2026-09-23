import 'package:cloud_firestore/cloud_firestore.dart';

class EventModel {
  final String id;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String category;
  final String assignedTo;
  final String? gcalId; // Crucial for Google Calendar sync
  final String? ownerId;
  final bool isLovehubContext;

  /// Importer that created this doc (`c2-rota`, `seb`, `rot90s`, …).
  final String? source;

  /// Stable id inside [source]. Together they form the Firestore doc id.
  final String? externalId;

  /// Free text from the importer. Kept off [summary] so titles stay clean.
  final String? notes;

  /// `tentative` or `confirmed`. Null is a legacy event and displays as confirmed.
  final String? status;

  EventModel({
    required this.id,
    required this.summary,
    required this.start,
    required this.end,
    this.allDay = false,
    this.category = 'general',
    this.assignedTo = 'shared',
    this.gcalId,
    this.ownerId,
    this.isLovehubContext = true,
    this.source,
    this.externalId,
    this.notes,
    this.status,
  });

  bool get isTentative => isTentativeEventStatus(status);

  /// Same document, with `status` set to confirmed. Other fields stay put.
  EventModel asConfirmed() {
    if (!isTentative) return this;
    return _withStatus(_eventStatusConfirmed);
  }

  /// Same document, with `status` set to tentative. Other fields stay put.
  EventModel asTentative() {
    if (isTentative) return this;
    return _withStatus(_eventStatusTentative);
  }

  EventModel _withStatus(String status) {
    return EventModel(
      id: id,
      summary: summary,
      start: start,
      end: end,
      allDay: allDay,
      category: category,
      assignedTo: assignedTo,
      gcalId: gcalId,
      ownerId: ownerId,
      isLovehubContext: isLovehubContext,
      source: source,
      externalId: externalId,
      notes: notes,
      status: status,
    );
  }

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel.fromMap(data, id: doc.id);
  }

  factory EventModel.fromMap(Map<String, dynamic> data, {required String id}) {
    final start = _readDate(data['start']);
    return EventModel(
      id: id,
      summary: data['summary'] ?? 'Untitled Event',
      start: start,
      end: data['end'] != null ? _readDate(data['end']) : start,
      allDay: data['allDay'] ?? false,
      category: data['category'] ?? 'general',
      assignedTo: data['assignedTo'] ?? 'shared',
      gcalId: data['gcalId'],
      ownerId: data['ownerId'],
      isLovehubContext: data['isLovehubContext'] ?? true,
      source: data['source'],
      externalId: data['externalId'],
      notes: data['notes'],
      status: readStoredEventStatus(data['status']),
    );
  }

  static DateTime _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw ArgumentError('Expected a Firestore Timestamp or DateTime');
  }

  Map<String, dynamic> toMap() {
    // Explicitly declare this as Map<String, dynamic> so Dart doesn't panic
    final Map<String, dynamic> map = {
      'summary': summary,
      'start': Timestamp.fromDate(start),
      'end': Timestamp.fromDate(end),
      'allDay': allDay,
      'category': category,
      'assignedTo': assignedTo,
      'isLovehubContext': isLovehubContext,
    };

    // Now it will happily accept potentially null values!
    if (gcalId != null) map['gcalId'] = gcalId;
    if (ownerId != null) map['ownerId'] = ownerId;
    if (source != null) map['source'] = source;
    if (externalId != null) map['externalId'] = externalId;
    if (notes != null) map['notes'] = notes;
    if (status != null) map['status'] = status;

    return map;
  }
}

const _eventStatusTentative = 'tentative';
const _eventStatusConfirmed = 'confirmed';

/// Firestore may omit [status] on events created before imports. Those stay
/// confirmed. Unknown values are treated the same way so a bad write cannot
/// blank the calendar.
String? readStoredEventStatus(Object? raw) {
  if (raw is! String) return null;
  switch (raw.trim().toLowerCase()) {
    case _eventStatusTentative:
      return _eventStatusTentative;
    case _eventStatusConfirmed:
      return _eventStatusConfirmed;
    default:
      return null;
  }
}

bool isTentativeEventStatus(Object? raw) =>
    readStoredEventStatus(raw) == _eventStatusTentative;

/// Status the create/edit sheet writes. Off is explicit `confirmed` so a new
/// save does not rely on a missing field to look booked.
String eventFormStatus(bool tentative) =>
    tentative ? _eventStatusTentative : _eventStatusConfirmed;

/// A real hub event that is not already tentative can be marked from a chip.
/// Virtual birthdays (`bday_…`) are not event documents.
bool canMarkEventTentativeFromChip({
  required String eventId,
  required Object? status,
}) {
  final id = eventId.trim();
  if (id.isEmpty || id.startsWith('bday_')) return false;
  return !isTentativeEventStatus(status);
}
