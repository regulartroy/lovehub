import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseModel {
  final String id;
  final String description;
  final double amount;
  final String paidBy;
  final Map<String, double> split;
  final DateTime date;
  final String createdBy;

  ExpenseModel({
    required this.id,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.split,
    required this.date,
    required this.createdBy,
  });

  factory ExpenseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExpenseModel(
      id: doc.id,
      description: data['description'] ?? 'Expense',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paidBy: data['paidBy'] ?? '',
      // Safely convert the Firestore map into a strict Map<String, double>
      split:
          (data['split'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, (value as num).toDouble()),
          ) ??
          {},
      date: data['date'] != null
          ? (data['date'] as Timestamp).toDate()
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }
}
