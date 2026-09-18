import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String text;
  final String listName;
  final bool isDone;
  final bool isUrgent;
  final String assignedTo;
  final String status;
  final DateTime? dueDate;
  final String? createdBy;
  final int? sortIndex; // <-- 1. ADD THIS FIELD
  Task({
    required this.id,
    required this.text,
    this.listName = 'General',
    this.isDone = false,
    this.isUrgent = false,
    this.assignedTo = 'shared',
    this.status = 'open',
    this.dueDate,
    this.createdBy,
    this.sortIndex, // <-- 2. ADD THIS TO CONSTRUCTOR
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      text: data['text'] ?? '',
      listName: data['listName'] ?? 'General',
      isDone: data['isDone'] ?? false,
      isUrgent: data['isUrgent'] ?? false,
      assignedTo: data['assignedTo'] ?? 'shared',
      status: data['status'] ?? 'open',
      dueDate: data['dueDate'] != null
          ? (data['dueDate'] as Timestamp).toDate()
          : null,
      createdBy: data['createdBy'],
      sortIndex: data['sortIndex'], // <-- 3. ADD THIS TO YOUR FROMMAP
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'listName': listName,
      'isDone': isDone,
      'isUrgent': isUrgent,
      'assignedTo': assignedTo,
      'status': status,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
