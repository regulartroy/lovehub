import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import '../repositories/finance_repository.dart';

class FinanceScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const FinanceScreen({
    super.key,
    required this.user,
    required this.visibleHubs,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final FinanceRepository _financeRepo = FinanceRepository();
  final Map<String, String> _namesCache = {};

  // --- THEME COLORS ---
  final Color _bgColor = const Color(0xFF0F172A); // Slate 900
  final Color _cardColor = const Color(0xFF1E293B); // Slate 800
  final Color _borderColor = const Color(0xFF334155); // Slate 700
  final Color _mutedTextColor = const Color(0xFF94A3B8); // Slate 400

  @override
  void initState() {
    super.initState();
  }

  // --- SMART NAME FETCHER ---
  Future<void> _resolveNamesForExpenses(List<ExpenseModel> expenses) async {
    final Set<String> uidsToFetch = {};

    for (var expense in expenses) {
      if (expense.paidBy.isNotEmpty) uidsToFetch.add(expense.paidBy);
      uidsToFetch.addAll(expense.split.keys);
    }

    uidsToFetch.removeWhere(
      (uid) => _namesCache.containsKey(uid) || uid == widget.user.uid,
    );

    if (uidsToFetch.isEmpty) return;

    try {
      for (String uid in uidsToFetch) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (userDoc.exists) {
          _namesCache[uid] = userDoc.data()?['displayName'] ?? "Unknown";
        } else {
          _namesCache[uid] = "Unknown User";
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      print("Name resolution error: $e");
    }
  }

  String _getName(String? uid) {
    if (uid == null || uid.isEmpty) return "Unknown";
    if (uid == widget.user.uid) return "You";
    return _namesCache[uid] ?? "Loading...";
  }

  // --- ADD EXPENSE DIALOG ---
  void _showAddExpenseDialog() async {
    if (widget.visibleHubs.isEmpty) return;
    String hubId = widget.visibleHubs.first.key;

    Map<String, String> selectablePartners = {};
    try {
      final hubDoc = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .get();
      final List members = hubDoc.data()?['members'] ?? [];
      for (String uid in members) {
        if (uid != widget.user.uid) {
          if (_namesCache.containsKey(uid)) {
            selectablePartners[uid] = _namesCache[uid]!;
          } else {
            final uDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            selectablePartners[uid] = uDoc.data()?['displayName'] ?? "Partner";
            _namesCache[uid] = selectablePartners[uid]!;
          }
        }
      }
    } catch (e) {
      print("Error fetching partners: $e");
    }

    if (selectablePartners.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No partners found to split with.")),
        );
      return;
    }
    if (!mounted) return;

    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String paidBy = widget.user.uid;
    String splitType = 'equal';
    Set<String> involvedUserIds = {widget.user.uid, ...selectablePartners.keys};
    Map<String, TextEditingController> exactCtrls = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Add Expense",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: titleCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Description",
                            labelStyle: TextStyle(color: _mutedTextColor),
                            hintText: "e.g. Dinner",
                            hintStyle: TextStyle(color: _borderColor),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Amount",
                            labelStyle: TextStyle(color: _mutedTextColor),
                            prefixText: "£",
                            prefixStyle: const TextStyle(color: Colors.white),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                          ),
                          onChanged: (_) => setModalState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Paid By",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _mutedTextColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text("Me"),
                            selected: paidBy == widget.user.uid,
                            onSelected: (v) =>
                                setModalState(() => paidBy = widget.user.uid),
                            backgroundColor: _cardColor,
                            selectedColor: Colors.white,
                            labelStyle: TextStyle(
                              color: paidBy == widget.user.uid
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...selectablePartners.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: paidBy == e.key,
                              onSelected: (v) =>
                                  setModalState(() => paidBy = e.key),
                              backgroundColor: _cardColor,
                              selectedColor: Colors.white,
                              labelStyle: TextStyle(
                                color: paidBy == e.key
                                    ? Colors.black
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Split Options",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _mutedTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: Icon(
                            Icons.call_split,
                            size: 16,
                            color: splitType == 'equal'
                                ? Colors.black
                                : Colors.white,
                          ),
                          label: const Text("Split Equally"),
                          selected: splitType == 'equal',
                          onSelected: (v) =>
                              setModalState(() => splitType = 'equal'),
                          backgroundColor: _cardColor,
                          selectedColor: Colors.white,
                          labelStyle: TextStyle(
                            color: splitType == 'equal'
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          avatar: Icon(
                            Icons.edit,
                            size: 16,
                            color: splitType == 'exact'
                                ? Colors.black
                                : Colors.white,
                          ),
                          label: const Text("Custom"),
                          selected: splitType == 'exact',
                          onSelected: (v) =>
                              setModalState(() => splitType = 'exact'),
                          backgroundColor: _cardColor,
                          selectedColor: Colors.white,
                          labelStyle: TextStyle(
                            color: splitType == 'exact'
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Column(
                      children: [
                        _buildSplitRow(
                          widget.user.uid,
                          "Me",
                          splitType,
                          amountCtrl.text,
                          involvedUserIds,
                          exactCtrls,
                          setModalState,
                        ),
                        ...selectablePartners.entries.map(
                          (e) => _buildSplitRow(
                            e.key,
                            e.value,
                            splitType,
                            amountCtrl.text,
                            involvedUserIds,
                            exactCtrls,
                            setModalState,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text(
                      "Save Expense",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      final double total =
                          double.tryParse(amountCtrl.text) ?? 0.0;
                      if (titleCtrl.text.isEmpty || total <= 0) return;

                      Map<String, double> finalSplit = {};
                      if (splitType == 'equal') {
                        if (involvedUserIds.isEmpty) return;
                        double share = total / involvedUserIds.length;
                        for (String uid in involvedUserIds)
                          finalSplit[uid] = share;
                      } else {
                        exactCtrls.forEach((uid, ctrl) {
                          double amt = double.tryParse(ctrl.text) ?? 0.0;
                          if (amt > 0) finalSplit[uid] = amt;
                        });
                      }

                      await _financeRepo.addExpense(hubId, {
                        'description': titleCtrl.text,
                        'amount': total,
                        'paidBy': paidBy,
                        'split': finalSplit,
                        'date': FieldValue.serverTimestamp(),
                        'createdBy': widget.user.uid,
                      });

                      if (mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSplitRow(
    String uid,
    String name,
    String type,
    String totalStr,
    Set<String> involved,
    Map<String, TextEditingController> ctrls,
    StateSetter setState,
  ) {
    if (type == 'equal') {
      final bool isChecked = involved.contains(uid);
      final double total = double.tryParse(totalStr) ?? 0.0;
      final String share = isChecked && involved.isNotEmpty
          ? "£${(total / involved.length).toStringAsFixed(2)}"
          : "£0.00";
      return CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(name, style: const TextStyle(color: Colors.white)),
        secondary: Text(
          share,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        value: isChecked,
        activeColor: Colors.white,
        checkColor: Colors.black,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(color: _mutedTextColor),
        ), // Makes unchecked box visible
        onChanged: (val) => setState(
          () => val == true ? involved.add(uid) : involved.remove(uid),
        ),
      );
    } else {
      if (!ctrls.containsKey(uid)) ctrls[uid] = TextEditingController();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: ctrls[uid],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixText: "£",
                  prefixStyle: const TextStyle(color: Colors.white),
                  hintText: "0.00",
                  hintStyle: TextStyle(color: _borderColor),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.visibleHubs.isEmpty)
      return const Center(
        child: Text(
          "Select a hub to see expenses.",
          style: TextStyle(color: Colors.white),
        ),
      );
    final String activeHubId = widget.visibleHubs.first.key;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text(
          "Shared Finance",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: _financeRepo.streamExpenses(activeHubId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Offline or poor connection.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final expenses = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resolveNamesForExpenses(expenses),
          );

          if (expenses.isEmpty)
            return Center(
              child: Text(
                "No expenses yet",
                style: TextStyle(color: _mutedTextColor),
              ),
            );

          Map<String, double> balances = _financeRepo.calculateBalances(
            expenses,
            widget.user.uid,
          );

          return Column(
            children: [
              _buildBalanceSummaryCard(balances),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expense = expenses[index];

                    bool showHeader = false;
                    if (index == 0) {
                      showHeader = true;
                    } else {
                      final prevDate = expenses[index - 1].date;
                      if (prevDate.month != expense.date.month ||
                          prevDate.year != expense.date.year)
                        showHeader = true;
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                            child: Text(
                              DateFormat(
                                'MMMM yyyy',
                              ).format(expense.date).toUpperCase(),
                              style: TextStyle(
                                color: _mutedTextColor,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        _buildExpenseTile(expense),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text(
          "Add Expense",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildBalanceSummaryCard(Map<String, double> balances) {
    double totalNet = 0.0;
    balances.values.forEach((v) => totalNet += v);
    final activeBalances = balances.entries
        .where((e) => e.value.abs() > 0.01)
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Text(
            "NET BALANCE",
            style: TextStyle(
              color: _mutedTextColor,
              letterSpacing: 1.5,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalNet >= 0
                ? "+£${totalNet.toStringAsFixed(2)}"
                : "-£${totalNet.abs().toStringAsFixed(2)}",
            style: TextStyle(
              color: totalNet >= 0 ? Colors.greenAccent : Colors.redAccent,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          Divider(height: 40, color: _borderColor),
          if (activeBalances.isEmpty)
            Text(
              "You are all settled up!",
              style: TextStyle(color: _mutedTextColor),
            )
          else
            Column(
              children: activeBalances.map((e) {
                final String name = _getName(e.key);
                final double val = e.value;
                final bool iAreOwed = val > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            iAreOwed ? "owes you " : "you owe ",
                            style: TextStyle(
                              color: _mutedTextColor,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "£${val.abs().toStringAsFixed(2)}",
                            style: TextStyle(
                              color: iAreOwed
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildExpenseTile(ExpenseModel expense) {
    final String paidByName = _getName(expense.paidBy);
    String impactText = "";
    Color impactColor = _mutedTextColor;

    if (expense.paidBy == widget.user.uid) {
      double othersOwe = 0.0;
      expense.split.forEach((uid, amount) {
        if (uid != widget.user.uid) othersOwe += amount;
      });
      if (othersOwe > 0) {
        impactText = "You lent £${othersOwe.toStringAsFixed(2)}";
        impactColor = Colors.greenAccent;
      } else {
        impactText = "Personal expense";
      }
    } else {
      if (expense.split.containsKey(widget.user.uid)) {
        double myShare = expense.split[widget.user.uid]!;
        impactText = "You owe £${myShare.toStringAsFixed(2)}";
        impactColor = Colors.redAccent;
      } else {
        impactText = "Not involved";
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: _borderColor,
          child: const Icon(Icons.receipt_long, color: Colors.white),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              expense.description,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              "£${expense.amount.toStringAsFixed(2)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              "Paid by $paidByName • ${DateFormat('d MMM').format(expense.date)}",
              style: TextStyle(color: _mutedTextColor),
            ),
            const SizedBox(height: 4),
            Text(
              impactText,
              style: TextStyle(
                color: impactColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
