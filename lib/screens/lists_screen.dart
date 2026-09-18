import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ListsScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const ListsScreen({super.key, required this.user, required this.visibleHubs});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  void _showAddItemDialog() {
    if (widget.visibleHubs.isEmpty) return;

    final TextEditingController textController = TextEditingController();
    String selectedHubId = widget.visibleHubs.first.key;
    DateTime? selectedDate;
    TimeOfDay? selectedTime;
    String? assignedUserId;
    String selectedCategory = 'general';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("New Task"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: "What needs doing?",
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),

                  if (widget.visibleHubs.length > 1)
                    DropdownButtonFormField<String>(
                      value: selectedHubId,
                      decoration: const InputDecoration(
                        labelText: "Hub",
                        contentPadding: EdgeInsets.zero,
                      ),
                      items: widget.visibleHubs
                          .map(
                            (h) => DropdownMenuItem(
                              value: h.key,
                              child: Text(h.value['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => selectedHubId = val!),
                    ),
                  const SizedBox(height: 16),

                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('hubs')
                        .doc(selectedHubId)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final List members = snapshot.data!['members'] ?? [];
                      return DropdownButtonFormField<String>(
                        value: assignedUserId,
                        decoration: const InputDecoration(
                          labelText: "Assign To",
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        hint: const Text("Anyone (Open Task)"),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text("Anyone"),
                          ),
                          ...members.map(
                            (uid) => DropdownMenuItem(
                              value: uid,
                              child: FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .get(),
                                builder: (c, s) => Text(
                                  s.data?['displayName']?.split(' ')[0] ??
                                      "Loading...",
                                ),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) =>
                            setState(() => assignedUserId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            selectedDate == null
                                ? "Date"
                                : "${selectedDate!.day}/${selectedDate!.month}",
                          ),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (date != null)
                              setState(() => selectedDate = date);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(
                            selectedTime == null
                                ? "Time"
                                : selectedTime!.format(context),
                          ),
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null)
                              setState(() => selectedTime = time);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    "Category",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Wrap(
                    spacing: 8,
                    children: ['General', 'House', 'Urgent', 'Admin']
                        .map(
                          (cat) => ChoiceChip(
                            label: Text(cat),
                            selected: selectedCategory == cat.toLowerCase(),
                            selectedColor: Colors.pink.shade100,
                            onSelected: (val) => setState(
                              () => selectedCategory = cat.toLowerCase(),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () async {
                  if (textController.text.isNotEmpty) {
                    Navigator.pop(context);
                    DateTime? finalDate = selectedDate;
                    if (selectedDate != null && selectedTime != null) {
                      finalDate = DateTime(
                        selectedDate!.year,
                        selectedDate!.month,
                        selectedDate!.day,
                        selectedTime!.hour,
                        selectedTime!.minute,
                      );
                    }
                    await FirebaseFirestore.instance.collection('items').add({
                      'text': textController.text,
                      'hubId': selectedHubId,
                      'isDone': false,
                      'addedBy': widget.user.uid,
                      'createdAt': FieldValue.serverTimestamp(),
                      'category': selectedCategory,
                      'dueDate': finalDate,
                      'assignedTo': assignedUserId,
                      'status':
                          (assignedUserId != null &&
                              assignedUserId != widget.user.uid)
                          ? 'pending'
                          : 'accepted',
                    });
                  }
                },
                child: const Text("Add Task"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleHubs.isEmpty)
      return const Center(child: Text("Select a hub in the drawer."));
    final visibleHubIds = widget.visibleHubs.map((e) => e.key).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _showAddItemDialog,
            icon: const Icon(Icons.add),
            label: const Text("New Task"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('items')
                .where('hubId', whereIn: visibleHubIds)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final items = snapshot.data!.docs;
              if (items.isEmpty)
                return const Center(child: Text("No tasks found."));

              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final data = item.data() as Map<String, dynamic>;
                  final isDone = data['isDone'] ?? false;
                  final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
                  final assignedTo = data['assignedTo'];
                  final status = data['status'] ?? 'accepted';
                  final category = data['category'] ?? 'general';
                  final isPendingForMe =
                      status == 'pending' && assignedTo == widget.user.uid;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    color: isPendingForMe
                        ? Colors.orange.shade50
                        : (isDone ? Colors.grey.shade50 : Colors.white),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Checkbox(
                            value: isDone,
                            activeColor: Colors.pink,
                            onChanged: (val) => FirebaseFirestore.instance
                                .collection('items')
                                .doc(item.id)
                                .update({'isDone': val}),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['text'],
                                  style: TextStyle(
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              if (category != 'general')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    category.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (status == 'pending')
                                const Text(
                                  "Status: Pending Acceptance",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              Row(
                                children: [
                                  if (dueDate != null) ...[
                                    Icon(
                                      Icons.calendar_today,
                                      size: 12,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${dueDate.day}/${dueDate.month}",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if (assignedTo != null)
                                    FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(assignedTo)
                                          .get(),
                                      builder: (c, s) {
                                        if (!s.hasData) return const SizedBox();
                                        final name =
                                            s.data?['displayName']?.split(
                                              ' ',
                                            )[0] ??
                                            "?";
                                        return Row(
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 14,
                                              color: Colors.grey,
                                            ),
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (isPendingForMe)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 8,
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  "Assigned to you:",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => FirebaseFirestore.instance
                                      .collection('items')
                                      .doc(item.id)
                                      .update({
                                        'assignedTo': null,
                                        'status': 'accepted',
                                      }),
                                  child: const Text(
                                    "Decline",
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Colors.orange,
                                  ),
                                  onPressed: () => FirebaseFirestore.instance
                                      .collection('items')
                                      .doc(item.id)
                                      .update({'status': 'accepted'}),
                                  child: const Text("Accept"),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
