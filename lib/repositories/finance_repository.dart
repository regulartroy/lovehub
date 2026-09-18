import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';

class FinanceRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream all expenses as strongly-typed models
  Stream<List<ExpenseModel>> streamExpenses(String hubId) {
    return _db
        .collection('hubs')
        .doc(hubId)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ExpenseModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Add a new expense (we pass a map here so we can use FieldValue.serverTimestamp)
  Future<void> addExpense(
    String hubId,
    Map<String, dynamic> expenseData,
  ) async {
    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('expenses')
        .add(expenseData);
  }

  // The Master Math: Calculates net balances from the perspective of the current user
  Map<String, double> calculateBalances(
    List<ExpenseModel> expenses,
    String currentUserId,
  ) {
    Map<String, double> balances = {};

    for (var expense in expenses) {
      if (expense.paidBy == currentUserId) {
        // I paid. Others owe me their share.
        expense.split.forEach((uid, amount) {
          if (uid != currentUserId) {
            balances[uid] = (balances[uid] ?? 0.0) + amount;
          }
        });
      } else {
        // Someone else paid. Do I owe them?
        if (expense.split.containsKey(currentUserId)) {
          double myShare = expense.split[currentUserId]!;
          balances[expense.paidBy] =
              (balances[expense.paidBy] ?? 0.0) - myShare;
        }
      }
    }

    return balances;
  }
}
