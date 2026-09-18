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
  });

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      summary: data['summary'] ?? 'Untitled Event',
      start: (data['start'] as Timestamp).toDate(),
      end: data['end'] != null
          ? (data['end'] as Timestamp).toDate()
          : (data['start'] as Timestamp).toDate(),
      allDay: data['allDay'] ?? false,
      category: data['category'] ?? 'general',
      assignedTo: data['assignedTo'] ?? 'shared',
      gcalId: data['gcalId'],
      ownerId: data['ownerId'],
      isLovehubContext: data['isLovehubContext'] ?? true,
    );
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

    return map;
  }
}
