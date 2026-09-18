import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../models/task_model.dart';
import '../repositories/task_repository.dart';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';

class TasksScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;
  final String initialList;
  final bool hideAppBar;
  final bool isShoppingOnly; // <-- NEW

  const TasksScreen({
    super.key,
    required this.user,
    required this.visibleHubs,
    this.initialList = 'All',
    this.hideAppBar = false,
    this.isShoppingOnly = false, // <-- NEW
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late String _currentList;
  Map<String, String> _hubMembers = {};
  bool _isLoadingMembers = true;
  final TaskRepository _taskRepo = TaskRepository();
  bool _isSortingAI = false; // <-- NEW: Loading state for the AI
  static const String _allTab = 'All';
  static const String _shoppingTab = 'Shopping';
  Set<String> _knownLists = {_shoppingTab, 'General'};

  // --- DYNAMIC THEME HELPERS ---
  // --- DYNAMIC THEME HELPERS ---
  // --- DYNAMIC THEME HELPERS ---
  bool get _isShopping => _currentList == _shoppingTab;
  Color get _bgColor => _isShopping
      ? Colors.white
      : Colors.amber.shade50; // New soft yellow background!
  Color get _accentColor => _isShopping
      ? Colors.green.shade700
      : Colors.amber.shade800; // Green vs Amber!

  // --- DELAYED COMPLETION STATE ---
  final Set<String> _locallyCompleted = {};
  final Map<String, Timer> _completionTimers = {};

  @override
  void initState() {
    super.initState();
    _currentList = widget.initialList;
    _fetchHubMembers();
  }

  @override
  void dispose() {
    for (var entry in _completionTimers.entries) {
      entry.value.cancel();
      if (widget.visibleHubs.isNotEmpty) {
        _taskRepo.toggleTaskCompletion(
          widget.visibleHubs.first.key,
          entry.key,
          true,
        );
      }
    }
    super.dispose();
  }

  Future<void> _aiSortShoppingList(List<Task> items, String hubId) async {
    if (items.isEmpty) return;
    setState(() => _isSortingAI = true);

    try {
      final model = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );

      // 1. Create a safe payload (IDs and Text ONLY)
      final payload = items.map((t) => {'id': t.id, 'text': t.text}).toList();

      // 2. The Strict Prompt
      final prompt =
          """You are a supermarket layout expert. Look at this JSON list of shopping items. 
      Assign each item a 'sortIndex' based on the typical path through a supermarket:
      10: Produce (Fruit/Vegetables)
      20: Bakery
      30: Meat/Seafood
      40: Dairy/Eggs
      50: Pantry/Dry Goods
      60: Frozen Foods
      70: Household/Toiletries
      80: Other

      Return ONLY a JSON array of objects. Each object MUST have the 'id' (exactly as provided) and the 'sortIndex' (integer). 
      Do NOT omit any IDs.
      Items: ${jsonEncode(payload)}""";

      final response = await model.generateContent([Content.text(prompt)]);
      String rawText = response.text ?? '[]';
      rawText = rawText.replaceAll('```json', '').replaceAll('```', '').trim();

      final List<dynamic> parsed = jsonDecode(rawText);

      // 3. Batch Update Firestore (Only touches the sortIndex number, completely protecting your text!)
      final batch = FirebaseFirestore.instance.batch();
      for (var item in parsed) {
        final docRef = FirebaseFirestore.instance
            .collection('hubs')
            .doc(hubId)
            .collection('items')
            .doc(item['id']);
        batch.update(docRef, {'sortIndex': item['sortIndex']});
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Shopping list smartly sorted!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sorting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSortingAI = false);
    }
  }

  Future<void> _fetchHubMembers() async {
    if (widget.visibleHubs.isEmpty) return;
    try {
      final hubId = widget.visibleHubs.first.key;
      final hubDoc = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .get();
      final List members = hubDoc.data()?['members'] ?? [];
      final Map<String, String> names = {};
      for (String uid in members) {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        names[uid] = uDoc.data()?['displayName'] ?? 'Unknown';
      }
      if (mounted) {
        setState(() {
          _hubMembers = names;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
    }
  }

  String _getName(String? uid) {
    if (uid == 'shared' || uid == null) return 'Shared';
    if (uid == widget.user.uid) return 'Me';
    return _hubMembers[uid] ?? 'Unknown';
  }

  List<String> _buildTabOrder(Set<String> lists) {
    final others = lists.where((l) => l != _shoppingTab).toList()..sort();
    return [_allTab, _shoppingTab, ...others];
  }

  Future<void> _deleteList(String listName, String hubId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$listName"?'),
        content: const Text(
          'This will permanently delete all tasks in this list. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _taskRepo.deleteList(hubId, listName);
    if (mounted) setState(() => _currentList = _allTab);
  }

  // --- UPDATED DIALOG (Now accepts an existing Task!) ---
  void _showAddTaskDialog({Task? existingTask}) {
    if (widget.visibleHubs.isEmpty) return;
    final String activeHubId = widget.visibleHubs.first.key;

    final textCtrl = TextEditingController(text: existingTask?.text ?? '');
    final newListCtrl = TextEditingController();

    String selectedList;
    if (existingTask != null) {
      selectedList = _knownLists.contains(existingTask.listName)
          ? existingTask.listName
          : 'General';
    } else {
      selectedList = (_currentList == _allTab) ? 'General' : _currentList;
    }

    bool isCreatingList = false;
    String assignedTo = existingTask?.assignedTo ?? 'shared';
    bool isUrgent = existingTask?.isUrgent ?? false;
    DateTime? dueDate = existingTask?.dueDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bool isShoppingDialog = selectedList == _shoppingTab;
          final Color dialogAccent = isShoppingDialog
              ? const Color(0xFFD84315)
              : Colors.teal.shade700;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 24,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  existingTask != null
                      ? 'Edit Item'
                      : (isShoppingDialog ? 'Add Items' : 'New Tasks'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: textCtrl,
                  autofocus: true,
                  maxLines: 5,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: existingTask != null
                        ? 'Item description'
                        : (isShoppingDialog
                              ? 'Milk\nBread\nEggs\n(one per line)'
                              : 'What needs doing?\n(one per line)'),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Icon(
                        isShoppingDialog
                            ? Icons.shopping_basket_outlined
                            : Icons.check_circle_outline,
                        color: dialogAccent,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),

                if (!isCreatingList)
                  DropdownButtonFormField<String>(
                    value: _knownLists.contains(selectedList)
                        ? selectedList
                        : 'General',
                    decoration: InputDecoration(
                      labelText: 'List',
                      prefixIcon: Icon(Icons.list_rounded, color: dialogAccent),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: [
                      ..._knownLists.map(
                        (l) => DropdownMenuItem(value: l, child: Text(l)),
                      ),
                      const DropdownMenuItem(
                        value: 'NEW',
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16),
                            SizedBox(width: 8),
                            Text('Create new list…'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == 'NEW') {
                        setModalState(() => isCreatingList = true);
                      } else {
                        setModalState(() => selectedList = val!);
                      }
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newListCtrl,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'New list name',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setModalState(() => isCreatingList = false),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),

                Text(
                  'Assign To',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: dialogAccent.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _assignChip(
                        label: 'Shared',
                        icon: Icons.people,
                        value: 'shared',
                        assignedTo: assignedTo,
                        activeColor: dialogAccent,
                        onTap: () => setModalState(() => assignedTo = 'shared'),
                      ),
                      ..._hubMembers.entries.map(
                        (e) => _assignChip(
                          label: e.key == widget.user.uid ? 'Me' : e.value,
                          initial: e.value[0],
                          value: e.key,
                          assignedTo: assignedTo,
                          activeColor: dialogAccent,
                          onTap: () => setModalState(() => assignedTo = e.key),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    isShoppingDialog
                        ? 'Priority / Need tonight'
                        : 'Urgent / time-sensitive',
                  ),
                  secondary: Icon(
                    Icons.access_time_rounded,
                    color: isUrgent
                        ? Colors.red
                        : dialogAccent.withOpacity(0.4),
                  ),
                  value: isUrgent,
                  activeColor: Colors.red,
                  onChanged: (val) => setModalState(() {
                    isUrgent = val;
                    if (isUrgent && dueDate == null) dueDate = DateTime.now();
                  }),
                ),

                if (isUrgent && !isShoppingDialog)
                  InkWell(
                    onTap: () async {
                      // FIX: Set the firstDate to 2020 so old overdue tasks don't crash the picker!
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setModalState(() => dueDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Due Date',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          Text(
                            dueDate == null
                                ? 'Select date'
                                : DateFormat('EEE, d MMM').format(dueDate!),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: dialogAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: Icon(existingTask != null ? Icons.save : Icons.add),
                  label: Text(
                    existingTask != null
                        ? 'Save Changes'
                        : (isShoppingDialog ? 'Add Items' : 'Add Tasks'),
                  ),
                  onPressed: () async {
                    if (textCtrl.text.trim().isEmpty) return;

                    final String finalList = isCreatingList
                        ? (newListCtrl.text.trim().isEmpty
                              ? 'General'
                              : newListCtrl.text.trim())
                        : selectedList;

                    if (existingTask != null) {
                      // --- UPDATE EXISTING TASK ---
                      final bool isNomination =
                          assignedTo != 'shared' &&
                          assignedTo != widget.user.uid &&
                          assignedTo != existingTask.assignedTo;
                      final String status = isNomination
                          ? 'pending_acceptance'
                          : existingTask.status;

                      await FirebaseFirestore.instance
                          .collection('hubs')
                          .doc(activeHubId)
                          .collection('items')
                          .doc(existingTask.id)
                          .update({
                            'text': textCtrl.text.trim(),
                            'listName': finalList,
                            'assignedTo': assignedTo,
                            'isUrgent': isUrgent,
                            'dueDate':
                                (isUrgent &&
                                    !isShoppingDialog &&
                                    dueDate != null)
                                ? Timestamp.fromDate(dueDate!)
                                : null,
                            'status': status,
                          });

                      if (isNomination) {
                        await FirebaseFirestore.instance
                            .collection('hubs')
                            .doc(activeHubId)
                            .collection('notifications')
                            .add({
                              'type': 'task_nomination',
                              'toUid': assignedTo,
                              'fromUid': widget.user.uid,
                              'fromName':
                                  _hubMembers[widget.user.uid] ??
                                  'Your partner',
                              'itemId': existingTask.id,
                              'text':
                                  "Reassigned you an item in $finalList: ${textCtrl.text.trim()}",
                              'listName': finalList,
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                      }
                    } else {
                      // --- CREATE NEW TASK ---
                      final bool isNomination =
                          assignedTo != 'shared' &&
                          assignedTo != widget.user.uid;
                      final String status = isNomination
                          ? 'pending_acceptance'
                          : 'open';

                      List<String> lines = textCtrl.text
                          .split('\n')
                          .where((s) => s.trim().isNotEmpty)
                          .toList();
                      List<Task> newTasks = lines
                          .map(
                            (line) => Task(
                              id: '',
                              text: line.trim(),
                              isDone: false,
                              listName: finalList,
                              assignedTo: assignedTo,
                              isUrgent: isUrgent,
                              dueDate: (isUrgent && !isShoppingDialog)
                                  ? dueDate
                                  : null,
                              status: status,
                              createdBy: widget.user.uid,
                            ),
                          )
                          .toList();

                      await _taskRepo.addTasks(activeHubId, newTasks);

                      if (isNomination) {
                        await FirebaseFirestore.instance
                            .collection('hubs')
                            .doc(activeHubId)
                            .collection('notifications')
                            .add({
                              'type': 'task_nomination',
                              'toUid': assignedTo,
                              'fromUid': widget.user.uid,
                              'fromName':
                                  _hubMembers[widget.user.uid] ??
                                  'Your partner',
                              'itemId': '',
                              'text':
                                  "Assigned you ${lines.length} items in $finalList",
                              'listName': finalList,
                              'isRead': false,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                      }
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    setState(() {
                      _knownLists.add(finalList);
                      _currentList = finalList;
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _assignChip({
    required String label,
    required String value,
    required String assignedTo,
    required Color activeColor,
    required VoidCallback onTap,
    IconData? icon,
    String? initial,
  }) {
    final bool selected = assignedTo == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : Colors.black12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            if (initial != null)
              CircleAvatar(
                radius: 8,
                backgroundColor: selected ? Colors.white : Colors.grey.shade400,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 9,
                    color: selected ? activeColor : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _negotiateDate(String taskId, DateTime currentDue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDue,
      // FIX: Widen the range here too!
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      await _taskRepo.updateDueDate(
        widget.visibleHubs.first.key,
        taskId,
        picked,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rescheduled to ${DateFormat('d MMM').format(picked)}',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleHubs.isEmpty)
      return const Center(child: Text('Select a hub in the drawer.'));
    final String activeHubId = widget.visibleHubs.first.key;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              // <-- NEW
              title: const Text(
                'Tasks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTaskDialog(),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Task>>(
        stream: _taskRepo.streamTasks(activeHubId),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(
              child: Text(
                'Offline or poor connection.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          if (!snapshot.hasData)
            return Center(
              child: CircularProgressIndicator(color: _accentColor),
            );

          final allTasks = snapshot.data!;
          final Set<String> lists = {_shoppingTab, 'General'};
          for (var task in allTasks) {
            lists.add(task.listName);
          }
          _knownLists = lists;
          final tabOrder = _buildTabOrder(lists);

          if (_currentList != _allTab && !lists.contains(_currentList)) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _currentList = _allTab),
            );
          }

          final displayTasks = _currentList == _allTab
              ? allTasks.where((t) => !t.isDone).toList()
              : allTasks.where((t) => t.listName == _currentList).toList();

          return Column(
            children: [
              // TABS CONTAINER
              if (!widget.isShoppingOnly) // <-- ADD THIS IF STATEMENT
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: tabOrder.map((listName) {
                          final bool selected = _currentList == listName;
                          final bool isAnchored =
                              listName == _allTab || listName == _shoppingTab;

                          Widget chip = _buildTab(
                            listName: listName,
                            selected: selected,
                            isAnchored: isAnchored,
                            onTap: () =>
                                setState(() => _currentList = listName),
                          );

                          if (!isAnchored)
                            chip = GestureDetector(
                              onLongPress: () =>
                                  _deleteList(listName, activeHubId),
                              child: chip,
                            );
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: chip,
                          );
                        }).toList(),
                      ),
                    ),
                    if (_currentList != _allTab && _currentList != _shoppingTab)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 0, 4),
                        child: Text(
                          'Long-press tab to delete list',
                          style: TextStyle(
                            fontSize: 10,
                            color: _accentColor.withOpacity(0.5),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                  ],
                ),

              Expanded(
                child: displayTasks.isEmpty
                    ? _buildEmpty()
                    : _currentList == _allTab
                    ? _buildAllView(displayTasks, activeHubId)
                    : _isShopping
                    ? _buildShoppingLayout(displayTasks, activeHubId)
                    : _buildTaskList(displayTasks, activeHubId),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTab({
    required String listName,
    required bool selected,
    required bool isAnchored,
    required VoidCallback onTap,
  }) {
    Color selectedBg = listName == _allTab
        ? Colors.black
        : (listName == _shoppingTab
              ? const Color(0xFFD84315)
              : Colors.teal.shade700);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? selectedBg : Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (listName == _shoppingTab)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.shopping_basket_rounded,
                  size: 13,
                  color: selected ? Colors.white : const Color(0xFFD84315),
                ),
              ),
            if (listName == _allTab)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Icon(
                  Icons.grid_view_rounded,
                  size: 13,
                  color: selected ? Colors.white : Colors.black,
                ),
              ),
            Text(
              listName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- NEW: Bulk Delete Completed Tasks ---
  Future<void> _clearCompletedTasks(
    List<Task> completedTasks,
    String hubId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Completed?'),
        content: const Text(
          'This will permanently delete all completed items in this list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Batch delete all completed tasks at once
    final batch = FirebaseFirestore.instance.batch();
    for (var t in completedTasks) {
      final ref = FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('items')
          .doc(t.id);
      batch.delete(ref);
    }
    await batch.commit();
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isShopping
                ? Icons.shopping_bag_outlined
                : (_currentList == _allTab
                      ? Icons.check_circle_outline_rounded
                      : Icons.check_box_outline_blank),
            size: 60,
            color: _accentColor.withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            _isShopping
                ? 'Basket is empty'
                : (_currentList == _allTab
                      ? 'Nothing to do — enjoy!'
                      : 'No tasks in $_currentList'),
            style: TextStyle(
              color: _accentColor.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllView(List<Task> tasks, String hubId) {
    final urgentTasks = tasks
        .where((t) => t.isUrgent && t.listName != _shoppingTab)
        .toList();
    final urgentShopping = tasks
        .where((t) => t.isUrgent && t.listName == _shoppingTab)
        .toList();
    final regularShopping = tasks
        .where((t) => !t.isUrgent && t.listName == _shoppingTab)
        .toList();
    final Map<String, List<Task>> regularOther = {};
    for (var t in tasks.where(
      (t) => !t.isUrgent && t.listName != _shoppingTab,
    )) {
      regularOther.putIfAbsent(t.listName, () => []).add(t);
    }
    final otherListsSorted = regularOther.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (urgentTasks.isNotEmpty) ...[
          _listGroupHeader('PRIORITY TASKS', Colors.red, Icons.priority_high),
          ...urgentTasks.map((t) => _buildTaskTile(t, hubId)),
          const SizedBox(height: 16),
        ],
        if (urgentShopping.isNotEmpty) ...[
          _listGroupHeader(
            'PRIORITY SHOPPING',
            Colors.red,
            Icons.shopping_cart_checkout,
          ),
          ...urgentShopping.map((t) => _buildTaskTile(t, hubId)),
          const SizedBox(height: 16),
        ],
        ...otherListsSorted.map((listName) {
          final listTasks = regularOther[listName]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _listGroupHeader(
                listName.toUpperCase(),
                Colors.amber.shade800, // <-- Changed from Teal
                Icons.list_rounded,
              ),
              ...listTasks.map((t) => _buildTaskTile(t, hubId)),
              const SizedBox(height: 16),
            ],
          );
        }),
        // --- SHOPPING SAFELY AT THE BOTTOM ---
        if (regularShopping.isNotEmpty) ...[
          _listGroupHeader(
            'SHOPPING LIST',
            Colors.green.shade700, // <-- Changed from Orange/Peach
            Icons.shopping_basket,
          ),
          ...regularShopping.map((t) => _buildTaskTile(t, hubId)),
          const SizedBox(height: 16),
        ],
      ], // <-- This was likely the missing bracket!
    );
  }

  Widget _buildShoppingLayout(List<Task> tasks, String hubId) {
    // --- NEW: Separate completed tasks! ---
    final completed = tasks.where((t) => t.isDone).toList();

    // --- SORT BOTH ACTIVE LISTS BY AI INDEX ---
    final priority = tasks.where((t) => t.isUrgent && !t.isDone).toList()
      ..sort((a, b) => (a.sortIndex ?? 999).compareTo(b.sortIndex ?? 999));

    final regular = tasks.where((t) => !t.isUrgent && !t.isDone).toList()
      ..sort((a, b) => (a.sortIndex ?? 999).compareTo(b.sortIndex ?? 999));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (priority.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _listGroupHeader(
                'PRIORITY / TONIGHT',
                Colors.red,
                Icons.warning_rounded,
              ),
              TextButton.icon(
                onPressed: _isSortingAI
                    ? null
                    : () => _aiSortShoppingList(priority, hubId),
                icon: _isSortingAI
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      )
                    : const Icon(
                        Icons.auto_awesome,
                        color: Colors.orange,
                        size: 16,
                      ),
                label: const Text(
                  "Smart Sort",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ...priority.map((t) => _buildTaskTile(t, hubId)),
          const SizedBox(height: 20),
        ],
        if (regular.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _listGroupHeader(
                'REGULAR SHOP',
                _accentColor,
                Icons.shopping_basket,
              ),
              TextButton.icon(
                onPressed: _isSortingAI
                    ? null
                    : () => _aiSortShoppingList(regular, hubId),
                icon: _isSortingAI
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      )
                    : const Icon(
                        Icons.auto_awesome,
                        color: Colors.orange,
                        size: 16,
                      ),
                label: const Text(
                  "Smart Sort",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ...regular.map((t) => _buildTaskTile(t, hubId)),
        ],

        // --- NEW: COMPLETED SECTION ---
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _listGroupHeader(
                'COMPLETED',
                Colors.grey.shade600,
                Icons.check_circle_outline,
              ),
              TextButton.icon(
                onPressed: () => _clearCompletedTasks(completed, hubId),
                icon: Icon(
                  Icons.delete_sweep,
                  color: Colors.grey.shade600,
                  size: 16,
                ),
                label: Text(
                  "Clear All",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ...completed.map((t) => _buildTaskTile(t, hubId)),
        ],
      ],
    );
  }

  Widget _buildTaskList(List<Task> tasks, String hubId) {
    // --- NEW: Separate completed tasks! ---
    final completed = tasks.where((t) => t.isDone).toList();

    // --- Sort so urgent items bubble to the top! ---
    final activeTasks = tasks.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        if (a.isUrgent && !b.isUrgent) return -1;
        if (!a.isUrgent && b.isUrgent) return 1;
        return 0;
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        ...activeTasks.map((t) => _buildTaskTile(t, hubId)),

        // --- NEW: COMPLETED SECTION ---
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _listGroupHeader(
                'COMPLETED',
                Colors.grey.shade600,
                Icons.check_circle_outline,
              ),
              TextButton.icon(
                onPressed: () => _clearCompletedTasks(completed, hubId),
                icon: Icon(
                  Icons.delete_sweep,
                  color: Colors.grey.shade600,
                  size: 16,
                ),
                label: Text(
                  "Clear All",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ...completed.map((t) => _buildTaskTile(t, hubId)),
        ],
      ],
    );
  }

  Widget _listGroupHeader(String label, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(Task task, String hubId) {
    final bool isPendingMyAcceptance =
        task.status == 'pending_acceptance' &&
        task.assignedTo == widget.user.uid &&
        task.createdBy != widget.user.uid;
    final bool isPendingOthers =
        task.status == 'pending_acceptance' &&
        task.assignedTo != widget.user.uid;

    final bool isShoppingItem = task.listName == _shoppingTab;

    final bool isVisuallyDone =
        task.isDone || _locallyCompleted.contains(task.id);

    Color cardColor;
    Color borderColor;

    if (isPendingMyAcceptance) {
      cardColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
    } else if (isShoppingItem && task.isUrgent) {
      cardColor = Colors.green.shade50; // Green bg
      borderColor = Colors.red.shade300;
    } else if (task.isUrgent) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade100;
    } else if (isShoppingItem) {
      cardColor = Colors.green.shade50; // Green bg
      borderColor = Colors.green.shade200; // Green border
    } else {
      cardColor = Colors.white;
      borderColor = Colors.black12;
    }

    Color titleColor = isVisuallyDone
        ? Colors.grey.shade400
        : (isShoppingItem && task.isUrgent
              ? Colors.red.shade900
              : Colors.black);

    Color iconColor = isVisuallyDone
        ? Colors.green
        : task.isUrgent
        ? Colors.red
        : (isShoppingItem
              ? Colors
                    .green
                    .shade700 // Green checkbox
              : Colors.amber.shade800.withOpacity(0.5)); // Amber checkbox

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            // --- NEW: TAP TO EDIT ---
            onTap: () => _showAddTaskDialog(existingTask: task),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: GestureDetector(
              onTap: () {
                if (!isVisuallyDone) {
                  setState(() => _locallyCompleted.add(task.id));

                  _completionTimers[task.id] = Timer(
                    const Duration(seconds: 10),
                    () {
                      _taskRepo.toggleTaskCompletion(hubId, task.id, true);
                      _completionTimers.remove(task.id);
                      if (mounted)
                        setState(() => _locallyCompleted.remove(task.id));
                    },
                  );

                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Item checked off'),
                      duration: const Duration(seconds: 8),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: 'UNDO',
                        textColor: Colors.tealAccent,
                        onPressed: () {
                          _completionTimers[task.id]?.cancel();
                          _completionTimers.remove(task.id);
                          setState(() => _locallyCompleted.remove(task.id));
                        },
                      ),
                    ),
                  );
                } else {
                  if (_locallyCompleted.contains(task.id)) {
                    _completionTimers[task.id]?.cancel();
                    _completionTimers.remove(task.id);
                    setState(() => _locallyCompleted.remove(task.id));
                  } else {
                    _taskRepo.toggleTaskCompletion(hubId, task.id, false);
                  }
                }
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isVisuallyDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  key: ValueKey(isVisuallyDone),
                  color: iconColor,
                  size: 26,
                ),
              ),
            ),
            title: Text(
              task.text,
              style: TextStyle(
                decoration: isVisuallyDone ? TextDecoration.lineThrough : null,
                fontWeight: task.isUrgent ? FontWeight.bold : FontWeight.normal,
                color: titleColor,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (task.isUrgent)
                    _badge(
                      task.dueDate != null
                          ? 'DUE ${DateFormat('d MMM').format(task.dueDate!).toUpperCase()}'
                          : 'Priority',
                      Colors.red,
                      Colors.white,
                    ),
                  if (isPendingMyAcceptance)
                    _badge(
                      'NEEDS ACCEPTANCE',
                      Colors.blue.shade700,
                      Colors.white,
                    ),
                  if (isPendingOthers)
                    _badge(
                      'WAITING FOR ${_getName(task.assignedTo).toUpperCase()}',
                      Colors.orange.shade700,
                      Colors.white,
                    ),
                  _badge(
                    _getName(task.assignedTo),
                    isShoppingItem
                        ? const Color(0xFFFFCC80)
                        : Colors.grey.shade100,
                    isShoppingItem
                        ? Colors.orange.shade900
                        : Colors.grey.shade700,
                    icon: Icons.person,
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: isShoppingItem
                    ? Colors.orange.shade300
                    : Colors.grey.shade400,
              ),
              onPressed: () => _taskRepo.deleteTask(hubId, task.id),
            ),
          ),
          if (isPendingMyAcceptance)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 14,
                    color: Colors.blue.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_getName(task.createdBy)} asked you to do this',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                  if (task.dueDate != null)
                    GestureDetector(
                      onTap: () => _negotiateDate(task.id, task.dueDate!),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          'RESCHEDULE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => FirebaseFirestore.instance
                        .collection('hubs')
                        .doc(hubId)
                        .collection('items')
                        .doc(task.id)
                        .update({'status': 'open'}),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ACCEPT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isPendingOthers)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 13,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Waiting for ${_getName(task.assignedTo)} to accept…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
