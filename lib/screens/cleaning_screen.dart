import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // <-- ADD THIS
import '../repositories/rota_repository.dart';

class CleaningScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const CleaningScreen({
    super.key,
    required this.user,
    required this.visibleHubs,
  });

  @override
  State<CleaningScreen> createState() => _CleaningScreenState();
}

class _CleaningScreenState extends State<CleaningScreen> {
  String? _activeHubId;
  List<Map<String, dynamic>> _hubMembers = [];
  bool _isLoading = true;

  // --- APP STATE ---
  bool _isEditingWizard = true;
  bool _hasGenerated = false;
  DateTime? _anchorDate;
  Map<String, dynamic> _blueprint = {}; // Will hold Weeks 1, 2, 3, 4

  // --- NEW: Undo Grace Period State ---
  final Set<String> _locallyCompleted = {};
  final Map<String, Timer> _completionTimers = {};

  // Weekly Completion State
  List<String> _completedThisWeek = [];
  String _currentWeekId = "";

  @override
  void dispose() {
    // If the user leaves the screen before the timer finishes, force the save!
    for (var entry in _completionTimers.entries) {
      entry.value.cancel();
      _toggleChoreCompletion(entry.key, true);
    }
    super.dispose();
  }

  // --- WIZARD STATE ---
  int _currentStep = 0;
  bool _isGenerating = false;
  bool _hasUnsavedChanges = false;
  List<Map<String, dynamic>> _draftChores = [];
  DateTime _selectedStartDate = DateUtils.dateOnly(DateTime.now());

  final RotaRepository _rotaRepo = RotaRepository();

  // --- THEME COLORS ---
  final Color _bgColor = Colors.deepPurple.shade50;
  final Color _accentColor = Colors.deepPurple;
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    if (widget.visibleHubs.isEmpty) return;
    _activeHubId = widget.visibleHubs.first.key;

    try {
      final hubDoc = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(_activeHubId)
          .get();
      List<dynamic> memberIds = hubDoc.data()?['members'] ?? [];
      List<Map<String, dynamic>> members = [];

      for (String uid in memberIds) {
        final uDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        members.add({
          'uid': uid,
          'name': uDoc.data()?['displayName'] ?? 'Unknown',
        });
      }

      final configDoc = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(_activeHubId)
          .collection('rota_settings')
          .doc('config')
          .get();

      bool hasExisting = configDoc.exists;

      bool isModern8Week = false;

      if (hasExisting) {
        final data = configDoc.data()!;
        try {
          _blueprint = data['blueprint'] ?? {};

          // --- 1. THE GATEKEEPER: Is this the new 8-week format? ---
          if ((data['cycleLength'] != null && data['cycleLength'] == 8) ||
              _blueprint.containsKey('8')) {
            isModern8Week = true;
          }

          if (data['anchorDate'] != null) {
            _anchorDate = (data['anchorDate'] as Timestamp).toDate();
            _selectedStartDate = _anchorDate!;
          }

          // --- 2. THE CRASH PREVENTER: Safely parse old rawChores lists! ---
          if (data['rawChores'] != null) {
            _draftChores = (data['rawChores'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }

          if (isModern8Week) {
            _listenToWeeklyCompletions();
          }
        } catch (e) {
          debugPrint("Caught old rota data format: $e");
          isModern8Week = false; // Force them to the wizard!
        }
      }

      if (mounted) {
        setState(() {
          _hubMembers = members;

          // Only show the dashboard if it's the new 8-week format
          _hasGenerated = isModern8Week;

          // If they have old data, force the Wizard open!
          _isEditingWizard = !isModern8Week;

          // Prompt them to hit 'Generate' if we successfully salvaged their old chores
          _hasUnsavedChanges = !isModern8Week && _draftChores.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading rota data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToWeeklyCompletions() {
    if (_anchorDate == null || _activeHubId == null) return;

    final now = DateUtils.dateOnly(DateTime.now());
    final daysSince = now.difference(DateUtils.dateOnly(_anchorDate!)).inDays;

    if (daysSince < 0) return; // Hasn't started yet

    final int weeksSince = daysSince ~/ 7;
    final DateTime startOfWeek = DateUtils.dateOnly(
      _anchorDate!,
    ).add(Duration(days: weeksSince * 7));
    _currentWeekId = DateFormat('yyyy-MM-dd').format(startOfWeek);

    FirebaseFirestore.instance
        .collection('hubs')
        .doc(_activeHubId)
        .collection('rota_logs')
        .doc('week_$_currentWeekId')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          if (snap.exists) {
            setState(
              () => _completedThisWeek = List<String>.from(
                snap.data()?['completed'] ?? [],
              ),
            );
          } else {
            setState(() => _completedThisWeek = []);
          }
        });
  }

  Future<void> _toggleChoreCompletion(String choreId, bool isDone) async {
    if (_currentWeekId.isEmpty || _activeHubId == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('hubs')
        .doc(_activeHubId)
        .collection('rota_logs')
        .doc('week_$_currentWeekId');

    if (isDone) {
      await docRef.set({
        'completed': FieldValue.arrayUnion([choreId]),
      }, SetOptions(merge: true));
    } else {
      await docRef.set({
        'completed': FieldValue.arrayRemove([choreId]),
      }, SetOptions(merge: true));
    }
  }

  // --- WIZARD UI HELPERS ---
  void _showAddChoreDialog() {
    final titleCtrl = TextEditingController();
    int frequencyDays = 7;
    int effortMinutes = 15;
    List<String> eligibleUsers = _hubMembers
        .map((m) => m['uid'] as String)
        .toList();

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Add Chore",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: "Chore Name (e.g. Clean Bath)",
                    filled: true,
                    fillColor: _cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "How often?",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: frequencyDays,
                      items: const [
                        DropdownMenuItem(
                          value: 3,
                          child: Text("Twice a week"),
                        ), // <-- NEW!
                        DropdownMenuItem(
                          value: 7,
                          child: Text("Weekly (Every week)"),
                        ),
                        DropdownMenuItem(
                          value: 14,
                          child: Text("Fortnightly (Every 2 weeks)"),
                        ),
                        DropdownMenuItem(
                          value: 28,
                          child: Text("Monthly (Every 4 weeks)"),
                        ),
                      ],
                      onChanged: (val) =>
                          setModalState(() => frequencyDays = val!),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Time required:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      "$effortMinutes mins",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _accentColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: effortMinutes.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  activeColor: _accentColor,
                  label: "$effortMinutes mins",
                  onChanged: (val) =>
                      setModalState(() => effortMinutes = val.toInt()),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Who can do this?",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: _hubMembers.map((m) {
                    final isSelected = eligibleUsers.contains(m['uid']);
                    return FilterChip(
                      label: Text(m['name']),
                      selected: isSelected,
                      selectedColor: Colors.deepPurple.shade200,
                      backgroundColor: _cardColor,
                      onSelected: (selected) => setModalState(() {
                        if (selected)
                          eligibleUsers.add(m['uid']);
                        else
                          eligibleUsers.remove(m['uid']);
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    if (titleCtrl.text.isEmpty || eligibleUsers.isEmpty) return;
                    setState(() {
                      _draftChores.add({
                        'id': DateTime.now().millisecondsSinceEpoch.toString(),
                        'title': titleCtrl.text,
                        'frequencyDays': frequencyDays,
                        'effortMinutes': effortMinutes,
                        'eligibleUsers': eligibleUsers,
                      });
                      _hasUnsavedChanges = true;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Save Chore"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- BUILDERS ---
  Widget _buildDashboard() {
    final now = DateUtils.dateOnly(DateTime.now());
    int currentCycleWeek = 1;
    int absoluteWeekNum = 1;
    bool hasStarted = true;
    DateTime? weekEndDate;

    if (_anchorDate != null) {
      final daysSince = now.difference(DateUtils.dateOnly(_anchorDate!)).inDays;
      if (daysSince < 0) {
        hasStarted = false;
      } else {
        absoluteWeekNum = (daysSince ~/ 7) + 1;
        currentCycleWeek = ((daysSince ~/ 7) % 8) + 1; // 8-Week Math!

        final startOfWeek = DateUtils.dateOnly(
          _anchorDate!,
        ).add(Duration(days: (absoluteWeekNum - 1) * 7));
        weekEndDate = startOfWeek.add(const Duration(days: 6));
      }
    }

    final weekChores =
        _blueprint[currentCycleWeek.toString()] as List<dynamic>? ?? [];

    // --- UPDATED SORTING (Checks local state) ---
    weekChores.sort((a, b) {
      bool aDone =
          _completedThisWeek.contains(a['id']) ||
          _locallyCompleted.contains(a['id']);
      bool bDone =
          _completedThisWeek.contains(b['id']) ||
          _locallyCompleted.contains(b['id']);
      if (aDone && !bDone) return 1;
      if (!aDone && bDone) return -1;
      return 0;
    });

    // --- UPDATED PROGRESS ---
    int completedCount = weekChores
        .where(
          (c) =>
              _completedThisWeek.contains(c['id']) ||
              _locallyCompleted.contains(c['id']),
        )
        .length;
    double progress = weekChores.isEmpty
        ? 0
        : (completedCount / weekChores.length);

    return Column(
      children: [
        // --- TOP HEADER (Sticky) ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade100.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(color: Colors.deepPurple.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Week $absoluteWeekNum",
                    style: TextStyle(
                      color: Colors.deepPurple.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _isEditingWizard = true;
                      _currentStep = 0;
                      _isGenerating = false;
                    }),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text("Edit Rota"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple.shade900,
                      side: BorderSide(color: Colors.deepPurple.shade300),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!hasStarted && _anchorDate != null)
                Text(
                  "Your cycle begins on ${DateFormat('EEEE, MMM d').format(_anchorDate!)}",
                  style: TextStyle(color: Colors.deepPurple.shade800),
                )
              else if (weekEndDate != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Complete by Sunday, ${DateFormat('MMM d').format(weekEndDate)}",
                      style: TextStyle(
                        color: Colors.deepPurple.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.white,
                        color: progress == 1.0 ? Colors.green : _accentColor,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // --- SCROLLABLE CONTENT ---
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- SECTION 1: ACTIONABLE CHORES ---
              Text(
                "This Week's Action Items",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade900,
                ),
              ),
              const SizedBox(height: 12),

              if (!hasStarted)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      "Sit tight! The cycle hasn't started yet.",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else if (weekChores.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      "Nothing scheduled for this week!",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                ...weekChores.map((c) {
                  final chore = c as Map<String, dynamic>;
                  final bool isDone =
                      _completedThisWeek.contains(chore['id']) ||
                      _locallyCompleted.contains(chore['id']);
                  final String assigneeName = _hubMembers.firstWhere(
                    (m) => m['uid'] == chore['assignedTo'],
                    orElse: () => {'name': 'Shared'},
                  )['name'];

                  return Card(
                    elevation: isDone ? 0 : 2,
                    color: isDone ? Colors.white54 : Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDone
                            ? Colors.transparent
                            : Colors.deepPurple.shade100,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (!isDone) {
                          setState(() => _locallyCompleted.add(chore['id']));
                          _completionTimers[chore['id']] = Timer(
                            const Duration(seconds: 10),
                            () {
                              _toggleChoreCompletion(chore['id'], true);
                              _completionTimers.remove(chore['id']);
                              if (mounted)
                                setState(
                                  () => _locallyCompleted.remove(chore['id']),
                                );
                            },
                          );
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Chore completed'),
                              duration: const Duration(seconds: 8),
                              action: SnackBarAction(
                                label: 'UNDO',
                                textColor: Colors.greenAccent,
                                onPressed: () {
                                  _completionTimers[chore['id']]?.cancel();
                                  _completionTimers.remove(chore['id']);
                                  setState(
                                    () => _locallyCompleted.remove(chore['id']),
                                  );
                                },
                              ),
                            ),
                          );
                        } else {
                          _completionTimers[chore['id']]?.cancel();
                          _completionTimers.remove(chore['id']);
                          setState(() => _locallyCompleted.remove(chore['id']));
                          _toggleChoreCompletion(chore['id'], false);
                        }
                      },
                      child: Padding(
                        // --- SCALED DOWN PADDING ---
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            // --- SCALED DOWN CHECKBOX ICON ---
                            Icon(
                              isDone
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: isDone
                                  ? Colors.green
                                  : Colors.grey.shade400,
                              size: 26,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chore['title'],
                                    style: TextStyle(
                                      // --- SCALED DOWN FONT ---
                                      fontSize: 16,
                                      fontWeight: isDone
                                          ? FontWeight.normal
                                          : FontWeight.bold,
                                      color: isDone
                                          ? Colors.grey
                                          : Colors.black87,
                                      decoration: isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        chore['assignedTo'] == 'shared'
                                            ? Icons.favorite
                                            : Icons.person,
                                        size: 14,
                                        color: isDone
                                            ? Colors.grey
                                            : (chore['assignedTo'] == 'shared'
                                                  ? Colors.pinkAccent
                                                  : _accentColor),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        assigneeName,
                                        style: TextStyle(
                                          color: isDone
                                              ? Colors.grey
                                              : (chore['assignedTo'] == 'shared'
                                                    ? Colors.pinkAccent
                                                    : _accentColor),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${chore['effortMinutes']}m",
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 32),
              Divider(color: Colors.deepPurple.shade200),
              const SizedBox(height: 24),

              // --- SECTION 2: 8-WEEK MASTER PLAN ---
              Text(
                "8-Week Master Plan",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "The full cycle breakdown. Chores are automatically distributed to keep the workload perfectly balanced.",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),

              ...List.generate(8, (index) {
                int weekNum = index + 1;
                String weekKey = weekNum.toString();
                List<dynamic> chores = _blueprint[weekKey] ?? [];
                bool isCurrentWeek = hasStarted && currentCycleWeek == weekNum;

                // Calculate the total load (minutes) for each user this week
                Map<String, int> loads = {};
                for (var c in chores) {
                  String uid = c['assignedTo'];
                  loads[uid] = (loads[uid] ?? 0) + (c['effortMinutes'] as int);
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: isCurrentWeek
                      ? Colors.deepPurple.shade50
                      : Colors.white,
                  elevation: isCurrentWeek ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isCurrentWeek
                          ? _accentColor
                          : Colors.deepPurple.shade100,
                      width: isCurrentWeek ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Week $weekNum",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _accentColor,
                              ),
                            ),
                            if (isCurrentWeek)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accentColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "CURRENT",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Divider(height: 24),
                        if (chores.isEmpty)
                          const Text(
                            "No chores this week.",
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else
                          ...[
                            ..._hubMembers,
                            {'uid': 'shared', 'name': 'Shared Team Effort'},
                          ].map((member) {
                            final userChores = chores
                                .where((c) => c['assignedTo'] == member['uid'])
                                .toList();
                            final load = loads[member['uid']] ?? 0;

                            if (userChores.isEmpty)
                              return const SizedBox.shrink();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            member['uid'] == 'shared'
                                                ? Icons.favorite
                                                : Icons.person,
                                            size: 16,
                                            color: member['uid'] == 'shared'
                                                ? Colors.pinkAccent
                                                : Colors.deepPurple.shade300,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            member['name'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple.shade50,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          "${load}m total",
                                          style: TextStyle(
                                            color: _accentColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...userChores.map(
                                    (c) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 6,
                                        left: 24,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.subdirectory_arrow_right,
                                            size: 16,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              c['title'],
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            "${c['effortMinutes']}m",
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWizard() {
    return Stepper(
      type: StepperType.horizontal,
      currentStep: _currentStep,
      elevation: 0,
      onStepTapped: (step) {
        if (step == 1 && _draftChores.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Add at least one chore first!")),
          );
          return;
        }
        setState(() => _currentStep = step);
      },
      onStepContinue: () async {
        if (_currentStep == 0) {
          if (_draftChores.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Add at least one chore first!")),
            );
            return;
          }
          setState(() => _currentStep += 1);
        } else {
          if (_draftChores.isEmpty || !_hasUnsavedChanges) return;

          setState(() => _isGenerating = true);

          // NEW: Calling the soon-to-be-updated Weekly Blueprint generator!
          await _rotaRepo.generateWeeklyBlueprint(
            hubId: _activeHubId!,
            chores: _draftChores,
            startDate: _selectedStartDate,
          );

          await _initData();
        }
      },
      controlsBuilder: (context, details) {
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Row(
            children: [
              if (_currentStep < 1 || _hasUnsavedChanges)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _currentStep == 1
                          ? Colors.green
                          : _accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: details.onStepContinue,
                    child: Text(
                      _currentStep == 1 ? "Generate 8-Week Plan" : "Next",
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: _accentColor),
                      foregroundColor: _accentColor,
                    ),
                    onPressed: () {
                      setState(() => _isEditingWizard = false);
                      _initData();
                    },
                    child: const Text("Return to Dashboard"),
                  ),
                ),
            ],
          ),
        );
      },
      steps: [
        // STEP 1: CHORES
        Step(
          title: const Text("Chores"),
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasGenerated)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _isEditingWizard = false);
                      _initData();
                    },
                    icon: Icon(Icons.arrow_back, color: _accentColor),
                    label: Text(
                      "Back to Dashboard",
                      style: TextStyle(color: _accentColor),
                    ),
                  ),
                ),
              const Text(
                "What needs doing around the house?",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (_draftChores.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white60,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "No chores added yet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _draftChores.length,
                  itemBuilder: (ctx, i) {
                    final chore = _draftChores[i];
                    String freqStr = chore['frequencyDays'] <= 3
                        ? "Twice a week"
                        : chore['frequencyDays'] == 7
                        ? "Weekly"
                        : chore['frequencyDays'] == 14
                        ? "Fortnightly"
                        : "Monthly";
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                      ),
                      child: ListTile(
                        title: Text(
                          chore['title'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "$freqStr • ${chore['effortMinutes']} mins",
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => setState(() {
                            _draftChores.removeAt(i);
                            _hasUnsavedChanges = true;
                          }),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _showAddChoreDialog,
                icon: const Icon(Icons.add),
                label: const Text("Add Chore"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  foregroundColor: _accentColor,
                  side: BorderSide(color: _accentColor),
                ),
              ),
            ],
          ),
        ),

        // STEP 2: GENERATE
        Step(
          title: const Text("Plan"),
          isActive: _currentStep >= 1,
          content: _isGenerating
              ? Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: _accentColor),
                        const SizedBox(height: 20),
                        const Text("Calculating Master Cycle..."),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Icon(
                      _hasUnsavedChanges
                          ? Icons.auto_awesome
                          : Icons.check_circle_outline,
                      size: 60,
                      color: _hasUnsavedChanges ? _accentColor : Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _hasUnsavedChanges ? "Ready to Generate?" : "Up to date!",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasUnsavedChanges
                          ? "We will build a fair 4-week rotating schedule. Chores will be assigned to a week, and you can complete them whenever you have free time during that week!"
                          : "No changes have been made to your setup. You can still pick a new start date below and regenerate.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),

                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.deepPurple.shade200),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.calendar_month,
                          color: _accentColor,
                        ),
                        title: const Text(
                          "Cycle Start Date",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          DateFormat(
                            'EEEE, d MMMM yyyy',
                          ).format(_selectedStartDate),
                        ),
                        trailing: Icon(
                          Icons.edit,
                          size: 18,
                          color: _accentColor,
                        ),
                        onTap: () async {
                          final now = DateUtils.dateOnly(DateTime.now());
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _selectedStartDate.isBefore(
                                  now.subtract(const Duration(days: 7)),
                                )
                                ? now
                                : _selectedStartDate,
                            firstDate: now.subtract(const Duration(days: 7)),
                            lastDate: now.add(const Duration(days: 60)),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: _accentColor,
                                    onPrimary: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedStartDate = picked;
                              _hasUnsavedChanges = true;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    if (_activeHubId == null)
      return Scaffold(
        backgroundColor: _bgColor,
        body: const Center(child: Text("Please select a hub")),
      );

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text(
          _isEditingWizard ? "Rota Setup" : "Household Rota",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isEditingWizard ? _buildWizard() : _buildDashboard(),
    );
  }
}
