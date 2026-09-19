import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../models/event_model.dart';
import '../repositories/event_repository.dart';
import '../theme/calendar_colors.dart';
import '../widgets/calendar_split_pill.dart';
import '../widgets/dashboard/dashboard_calendar_overview.dart';
import '../services/member_profile.dart';

// --- TOP LEVEL HELPERS ---
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

// ------------------------------------------------

class CalendarScreen extends StatefulWidget {
  final User user;
  final Function(bool) onSyncRequest;

  const CalendarScreen({
    super.key,
    required this.user,
    required this.onSyncRequest,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late TabController _tabController;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Map<String, dynamic>> _birthdays = [];
  // CLEAN ARCHITECTURE
  final EventRepository _eventRepo = EventRepository();
  List<EventModel> _allEvents = [];

  List<Map<String, dynamic>> _hubMembers = [];
  String? _activeHubId;
  HubMemberDirectory? _memberDirectory;

  // FILTER STATE
  String? _selectedMemberFilter;

  // Google Auth
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [gcal.CalendarApi.calendarReadonlyScope],
  );
  gcal.CalendarApi? _calendarApi;
  List<gcal.CalendarListEntry> _googleCalendars = [];
  String? _selectedCalendarId;
  bool _isLoadingCalendars = false;

  Map<String, bool> _filters = {
    'work': true,
    'shared': true,
    'birthday': true,
    'general': true,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 1);
    _selectedDay = null;
    _memberDirectory = HubMemberDirectory(
      currentUser: widget.user,
      meLabel: 'Me',
      onChanged: (members) {
        if (mounted) setState(() => _hubMembers = members);
      },
    );

    // --- NEW: Clear the selected date when leaving the calendar tab ---
    _tabController.addListener(() {
      if (_tabController.index != 0 && _selectedDay != null) {
        setState(() => _selectedDay = null);
      }
    });

    _initHubData();
    _loadSavedSettings();
    _silentLogin();
  }

  @override
  void dispose() {
    _memberDirectory?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initHubData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _activeHubId = data['activeHubId'];

        if (_activeHubId != null) {
          _memberDirectory?.watch(_activeHubId);
          // Listen to the new birthdays collection
          FirebaseFirestore.instance
              .collection('hubs')
              .doc(_activeHubId)
              .collection('birthdays')
              .snapshots()
              .listen((snap) {
                if (mounted)
                  setState(
                    () => _birthdays = snap.docs
                        .map((d) => {'id': d.id, ...d.data()})
                        .toList(),
                  );
              });
        }
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _hubMembers = [
            {
              'uid': widget.user.uid,
              'name': 'Me',
              'displayName': widget.user.displayName ?? 'Me',
              'photoURL': widget.user.photoURL ?? '',
            },
          ],
        );
    }
  }

  Future<void> _loadSavedSettings() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();
    if (userDoc.exists && userDoc.data()!.containsKey('targetCalendarId')) {
      if (mounted)
        setState(
          () => _selectedCalendarId = userDoc.data()!['targetCalendarId'],
        );
    }
  }

  Future<void> _saveTargetCalendar(String id) async {
    setState(() => _selectedCalendarId = id);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .set({'targetCalendarId': id}, SetOptions(merge: true));
  }

  Future<void> _silentLogin() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        final client = await _googleSignIn.authenticatedClient();
        if (client != null) {
          if (mounted) setState(() => _calendarApi = gcal.CalendarApi(client));
          _fetchGoogleCalendars(silent: true);
        }
      }
    } catch (e) {
      print("Silent login info: $e");
    }
  }

  Future<void> _connectGoogleCalendar() async {
    setState(() => _isLoadingCalendars = true);
    try {
      if (_calendarApi == null) {
        try {
          await _googleSignIn.disconnect();
        } catch (_) {}
        final account = await _googleSignIn.signIn();
        if (account == null) {
          setState(() => _isLoadingCalendars = false);
          return;
        }
        final client = await _googleSignIn.authenticatedClient();
        if (client != null) _calendarApi = gcal.CalendarApi(client);
      }
      await _fetchGoogleCalendars();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Connection failed: $e")));
    } finally {
      if (mounted) setState(() => _isLoadingCalendars = false);
    }
  }

  Future<void> _fetchGoogleCalendars({bool silent = false}) async {
    if (_calendarApi == null) return;
    try {
      final list = await _calendarApi!.calendarList.list();
      if (mounted) {
        setState(() {
          _googleCalendars = list.items ?? [];
          if (_selectedCalendarId == null && _googleCalendars.isNotEmpty) {
            final primary = _googleCalendars.firstWhere(
              (c) => c.primary == true,
              orElse: () => _googleCalendars.first,
            );
            _saveTargetCalendar(primary.id!);
          }
        });
      }
    } catch (e) {
      if (!silent) rethrow;
    }
  }

  Future<void> _importFromGoogle() async {
    if (_selectedCalendarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Connect Calendar in Sidebar first!")),
      );
      Scaffold.of(context).openDrawer();
      return;
    }
    if (_calendarApi == null) {
      await _connectGoogleCalendar();
      if (_calendarApi == null) return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final now = DateTime.now();
      final timeMin = now.toUtc();
      final timeMax = now.add(const Duration(days: 360)).toUtc();

      final events = await _calendarApi!.events.list(
        _selectedCalendarId!,
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: true,
      );

      final Set<String> knownGcalIds = _allEvents
          .map((e) => e.gcalId)
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      List<gcal.Event> newFoundEvents = [];
      int rawCount = events.items?.length ?? 0;

      for (var gEvent in events.items ?? []) {
        if (gEvent.id != null && !knownGcalIds.contains(gEvent.id)) {
          newFoundEvents.add(gEvent);
        }
      }

      if (mounted) Navigator.pop(context);

      if (newFoundEvents.isNotEmpty) {
        newFoundEvents.sort((a, b) {
          DateTime dA = a.start?.dateTime ?? a.start?.date ?? DateTime.now();
          DateTime dB = b.start?.dateTime ?? b.start?.date ?? DateTime.now();
          return dA.compareTo(dB);
        });
        if (mounted) _showImportDialog(newFoundEvents);
      } else {
        if (mounted)
          _showStatusDialog(
            "All Caught Up!",
            "Checked $rawCount events.\nNo new events found.",
          );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
        _showStatusDialog("Import Failed", "Could not read calendar: $e");
    }
  }

  void _showStatusDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(List<gcal.Event> events) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Found ${events.length} New Events"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select events to import:",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final e = events[index];
                    String timeStr;
                    if (e.start?.dateTime != null) {
                      timeStr = DateFormat(
                        'EEE, d MMM • HH:mm',
                      ).format(e.start!.dateTime!.toLocal());
                    } else if (e.start?.date != null) {
                      DateTime start = e.start!.date!;
                      DateTime endInclusive = e.end!.date!.subtract(
                        const Duration(days: 1),
                      );
                      if (isSameDay(start, endInclusive))
                        timeStr =
                            "All Day [${DateFormat('d MMM').format(start)}]";
                      else
                        timeStr =
                            "All Day [${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(endInclusive)}]";
                    } else {
                      timeStr = "Unknown Date";
                    }

                    return ListTile(
                      dense: true,
                      title: Text(
                        e.summary ?? "Untitled",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        timeStr,
                        style: const TextStyle(color: Colors.blueGrey),
                      ),
                      trailing: const Icon(Icons.download, size: 14),
                      onTap: () {
                        Navigator.pop(context);
                        _showEditOrImportDialog(gcalEvent: e);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  DateTime _getShiftedDate(DateTime orig, String repeat, int index) {
    if (index == 0) return orig;
    if (repeat == 'Daily') return orig.add(Duration(days: index));
    if (repeat == 'Weekly') return orig.add(Duration(days: index * 7));
    if (repeat == 'Monthly')
      return DateTime(
        orig.year,
        orig.month + index,
        orig.day,
        orig.hour,
        orig.minute,
      );
    if (repeat == 'Yearly')
      return DateTime(
        orig.year + index,
        orig.month,
        orig.day,
        orig.hour,
        orig.minute,
      );
    return orig;
  }

  IconData _getBdayIcon(String seed) {
    final icons = [
      Icons.cake_rounded,
      Icons.celebration_rounded,
      Icons.card_giftcard_rounded,
      Icons.stars_rounded,
      Icons.local_play_rounded,
    ];
    return icons[seed.hashCode.abs() % icons.length];
  }

  void _showEditOrImportDialog({
    EventModel? existingEvent,
    gcal.Event? gcalEvent,
    DateTime? initialDate, // <-- NEW: Allow passing a specific date!
  }) {
    if (_activeHubId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Error: No Hub Found.")));
      return;
    }

    final TextEditingController titleCtrl = TextEditingController();
    DateTime? startDt = initialDate ?? _selectedDay;
    DateTime? endDt = startDt?.add(const Duration(hours: 1));
    bool isAllDay = false;
    String category = 'general';
    String assignedTo = 'shared';
    String? gcalId;

    String repeatOption = 'Never';
    final List<String> repeatOptions = [
      'Never',
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
    ];

    if (existingEvent != null) {
      titleCtrl.text = existingEvent.summary;
      startDt = existingEvent.start;
      endDt = existingEvent.end;
      isAllDay = existingEvent.allDay;
      category = existingEvent.category;
      assignedTo = existingEvent.assignedTo;
      gcalId = existingEvent.gcalId;

      if (category == 'birthday') {
        repeatOption = 'Yearly';
        if (existingEvent.id.startsWith('bday_')) {
          String realId = existingEvent.id.split('_')[1];
          final bdayData = _birthdays.firstWhere(
            (b) => b['id'] == realId,
            orElse: () => {},
          );
          if (bdayData.isNotEmpty) {
            startDt = DateTime(
              bdayData['year'] ?? DateTime.now().year,
              bdayData['month'],
              bdayData['day'],
            );
            endDt = startDt;
          }
        }
      }
    } else if (gcalEvent != null) {
      String rawSummary = gcalEvent.summary ?? "";
      titleCtrl.text = rawSummary.replaceAll(RegExp(r'\[.*?\]'), '').trim();

      if (gcalEvent.start?.date != null) {
        isAllDay = true;
        startDt = gcalEvent.start!.date!;
        if (gcalEvent.end?.date != null) {
          endDt = gcalEvent.end!.date!.subtract(const Duration(days: 1));
        } else {
          endDt = startDt;
        }
      } else if (gcalEvent.start?.dateTime != null) {
        isAllDay = false;
        startDt = gcalEvent.start!.dateTime!;
        endDt =
            gcalEvent.end?.dateTime ?? startDt.add(const Duration(hours: 1));
      }
      gcalId = gcalEvent.id;
    }

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existingEvent != null ? "Edit Event" : "New Event",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (existingEvent != null)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () {
                          if (existingEvent.id.startsWith('bday_')) {
                            String realId = existingEvent.id.split('_')[1];
                            FirebaseFirestore.instance
                                .collection('hubs')
                                .doc(_activeHubId)
                                .collection('birthdays')
                                .doc(realId)
                                .delete();
                          } else {
                            _eventRepo.deleteEvent(
                              _activeHubId!,
                              existingEvent.id,
                            );
                          }
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: "Title",
                    prefixIcon: Icon(
                      category == 'work'
                          ? Icons.work
                          : category == 'birthday'
                          ? Icons.cake
                          : Icons.event,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 15),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['general', 'work', 'birthday'].map((cat) {
                      final catColor = CalendarColors.categoryTint(cat);

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat == 'general' ? 'Personal' : cat.capitalize()),
                          selected: category == cat,
                          selectedColor: catColor.withValues(alpha: 0.28),
                          onSelected: (v) => setSheetState(() {
                            category = cat;
                            if (cat == 'birthday') {
                              repeatOption = 'Yearly';
                              isAllDay = true;
                            } else {
                              repeatOption = 'Never';
                              isAllDay = false;
                            }
                          }),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("All Day"),
                  value: isAllDay,
                  activeColor: Colors.pink,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setSheetState(() => isAllDay = val),
                ),

                Row(
                  children: [
                    Expanded(
                      child: _buildDateInput(
                        context,
                        label: "From",
                        date: startDt,
                        isAllDay:
                            isAllDay, // <-- FIXED: Removed 'time' parameter
                        onTap: () async {
                          final safeStart =
                              startDt ??
                              DateTime.now(); // Fallback to today if null
                          final d = await showDatePicker(
                            context: context,
                            initialDate: safeStart,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            setSheetState(() {
                              final n = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                safeStart.hour,
                                safeStart.minute,
                              );
                              final safeEnd =
                                  endDt ?? n.add(const Duration(hours: 1));
                              if (n.isAfter(safeEnd) || isSameDay(n, safeEnd)) {
                                endDt = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  safeEnd.hour,
                                  safeEnd.minute,
                                );
                              }
                              startDt = n;
                            });
                          }
                        },
                        onTimeTap: isAllDay || startDt == null
                            ? null
                            : () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    startDt!,
                                  ), // Safe with !
                                  builder: (context, child) => MediaQuery(
                                    data: MediaQuery.of(
                                      context,
                                    ).copyWith(alwaysUse24HourFormat: true),
                                    child: child!,
                                  ),
                                );
                                if (t != null) {
                                  final newStartDt = DateTime(
                                    startDt!.year,
                                    startDt!.month,
                                    startDt!.day,
                                    t.hour,
                                    t.minute,
                                  );
                                  final newEndDt = newStartDt.add(
                                    const Duration(hours: 1),
                                  );

                                  setSheetState(() {
                                    startDt = newStartDt;
                                    endDt = newEndDt;
                                  });

                                  final endT = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      newEndDt,
                                    ),
                                    builder: (context, child) => MediaQuery(
                                      data: MediaQuery.of(
                                        context,
                                      ).copyWith(alwaysUse24HourFormat: true),
                                      child: child!,
                                    ),
                                  );

                                  if (endT != null) {
                                    setSheetState(() {
                                      DateTime finalEndDt = DateTime(
                                        newEndDt.year,
                                        newEndDt.month,
                                        newEndDt.day,
                                        endT.hour,
                                        endT.minute,
                                      );
                                      if (finalEndDt.isBefore(newStartDt))
                                        finalEndDt = finalEndDt.add(
                                          const Duration(days: 1),
                                        );
                                      endDt = finalEndDt;
                                    });
                                  }
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDateInput(
                        context,
                        label: "To",
                        date: endDt,
                        isAllDay:
                            isAllDay, // <-- FIXED: Removed 'time' parameter
                        onTap: () async {
                          final safeEnd =
                              endDt ??
                              startDt?.add(const Duration(hours: 1)) ??
                              DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: safeEnd,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            setSheetState(
                              () => endDt = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                safeEnd.hour,
                                safeEnd.minute,
                              ),
                            );
                          }
                        },
                        onTimeTap: isAllDay || endDt == null
                            ? null
                            : () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    endDt!,
                                  ), // Safe with !
                                  builder: (context, child) => MediaQuery(
                                    data: MediaQuery.of(
                                      context,
                                    ).copyWith(alwaysUse24HourFormat: true),
                                    child: child!,
                                  ),
                                );
                                if (t != null) {
                                  setSheetState(() {
                                    DateTime tempEnd = DateTime(
                                      endDt!.year,
                                      endDt!.month,
                                      endDt!.day,
                                      t.hour,
                                      t.minute,
                                    );
                                    if (startDt != null &&
                                        tempEnd.isBefore(startDt!)) {
                                      tempEnd = tempEnd.add(
                                        const Duration(days: 1),
                                      );
                                    }
                                    endDt = tempEnd;
                                  });
                                }
                              },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),
                Row(
                  children: [
                    const Icon(Icons.repeat, color: Colors.grey, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      "Repeat:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: repeatOption,
                      items: repeatOptions
                          .map(
                            (String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setSheetState(() => repeatOption = val!),
                      underline: Container(),
                    ),
                  ],
                ),
                const Divider(),

                const Text(
                  "Assigned To",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                Wrap(
                  spacing: 8.0,
                  children: [
                    ChoiceChip(
                      label: const Text("Shared"),
                      selected: assignedTo == 'shared',
                      selectedColor: CalendarColors.shared.withValues(alpha: 0.28),
                      onSelected: (v) =>
                          setSheetState(() => assignedTo = 'shared'),
                    ),
                    ..._hubMembers.map(
                      (m) => ChoiceChip(
                        label: Text(m['name']),
                        selected: assignedTo == m['uid'],
                        selectedColor: _palette
                            .whoColor(m['uid'])
                            .withValues(alpha: 0.28),
                        onSelected: (v) =>
                            setSheetState(() => assignedTo = m['uid']),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          // 1. Block saving if dates are blank
                          if (titleCtrl.text.isEmpty ||
                              _activeHubId == null ||
                              startDt == null ||
                              endDt == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Please add a title and select a date.",
                                ),
                              ),
                            );
                            return;
                          }
                          setSheetState(() => isSaving = true);

                          // 2. CREATE STRICT NON-NULL VARIABLES FOR THE DATABASE
                          final DateTime finalStart = startDt!;
                          final DateTime finalEnd = endDt!;

                          // Intercept Birthday Saves
                          if (category == 'birthday' && existingEvent == null) {
                            await FirebaseFirestore.instance
                                .collection('hubs')
                                .doc(_activeHubId!)
                                .collection('birthdays')
                                .add({
                                  'name': titleCtrl.text,
                                  'month': finalStart.month,
                                  'day': finalStart.day,
                                  'year': finalStart.year == DateTime.now().year
                                      ? null
                                      : finalStart.year,
                                });
                            if (mounted) Navigator.pop(context);
                            return;
                          }

                          int iterations = 1;
                          if (repeatOption == 'Daily') iterations = 30;
                          if (repeatOption == 'Weekly') iterations = 52;
                          if (repeatOption == 'Monthly') iterations = 12;
                          if (repeatOption == 'Yearly') iterations = 5;

                          if (existingEvent != null) {
                            if (existingEvent.id.startsWith('bday_')) {
                              String realId = existingEvent.id.split('_')[1];
                              await FirebaseFirestore.instance
                                  .collection('hubs')
                                  .doc(_activeHubId!)
                                  .collection('birthdays')
                                  .doc(realId)
                                  .update({
                                    'name': titleCtrl.text,
                                    'month': finalStart.month,
                                    'day': finalStart.day,
                                    'year':
                                        finalStart.year == DateTime.now().year
                                        ? null
                                        : finalStart.year,
                                  });
                              if (mounted) Navigator.pop(context);
                              return;
                            }

                            final updatedEvent = EventModel(
                              id: existingEvent.id,
                              summary: titleCtrl.text,
                              start: finalStart, // Use finalStart
                              end: finalEnd, // Use finalEnd
                              allDay: isAllDay,
                              category: category,
                              assignedTo: assignedTo,
                              gcalId: gcalId,
                              ownerId: widget.user.uid,
                            );
                            await _eventRepo.updateEvent(
                              _activeHubId!,
                              existingEvent.id,
                              updatedEvent.toMap(),
                            );

                            if (iterations > 1) {
                              List<EventModel> futureEvents = [];
                              for (int i = 1; i < iterations; i++) {
                                futureEvents.add(
                                  EventModel(
                                    id: '',
                                    summary: titleCtrl.text,
                                    start: _getShiftedDate(
                                      finalStart,
                                      repeatOption,
                                      i,
                                    ),
                                    end: _getShiftedDate(
                                      finalEnd,
                                      repeatOption,
                                      i,
                                    ),
                                    allDay: isAllDay,
                                    category: category,
                                    assignedTo: assignedTo,
                                    gcalId: gcalId,
                                    ownerId: widget.user.uid,
                                  ),
                                );
                              }
                              await _eventRepo.batchAddEvents(
                                _activeHubId!,
                                futureEvents,
                              );
                            }
                          } else {
                            List<EventModel> eventsToCreate = [];
                            for (int i = 0; i < iterations; i++) {
                              eventsToCreate.add(
                                EventModel(
                                  id: '',
                                  summary: titleCtrl.text,
                                  start: _getShiftedDate(
                                    finalStart,
                                    repeatOption,
                                    i,
                                  ),
                                  end: _getShiftedDate(
                                    finalEnd,
                                    repeatOption,
                                    i,
                                  ),
                                  allDay: isAllDay,
                                  category: category,
                                  assignedTo: assignedTo,
                                  gcalId: gcalId,
                                  ownerId: widget.user.uid,
                                ),
                              );
                            }
                            await _eventRepo.batchAddEvents(
                              _activeHubId!,
                              eventsToCreate,
                            );
                          }

                          if (mounted) Navigator.pop(context);
                          if (gcalEvent != null) _importFromGoogle();
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Save to Lovehub"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateInput(
    BuildContext context, {
    required String label,
    required DateTime? date,
    required bool isAllDay,
    required VoidCallback onTap,
    VoidCallback? onTimeTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Column(
            children: [
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: isAllDay ? const Radius.circular(12) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: date != null
                            ? Colors.pink
                            : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        date != null
                            ? DateFormat('d MMM yyyy').format(date)
                            : "Select Date",
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: date != null
                              ? Colors.black
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isAllDay) ...[
                const Divider(height: 1, indent: 10, endIndent: 10),
                InkWell(
                  onTap: onTimeTap,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: date != null
                              ? Colors.blueGrey
                              : Colors.grey.shade300,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          date != null
                              ? DateFormat('HH:mm').format(date)
                              : '--:--',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: date != null
                                ? Colors.black
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  HubMemberPalette get _palette => HubMemberPalette.fromMembers(_hubMembers);

  Widget _buildMemberFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              showCheckmark: false,
              avatar: _selectedMemberFilter == null
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
              label: const Text("All"),
              selected: _selectedMemberFilter == null,
              onSelected: (bool selected) =>
                  setState(() => _selectedMemberFilter = null),
              selectedColor: Colors.black,
              labelStyle: TextStyle(
                color: _selectedMemberFilter == null
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          ..._hubMembers.map((member) {
            bool isSelected = _selectedMemberFilter == member['uid'];
            final who = _palette.whoColor(member['uid']);
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: CircleAvatar(
                  backgroundColor: isSelected ? Colors.white : who.withValues(alpha: 0.18),
                  radius: 10,
                  child: Text(
                    member['name'][0],
                    style: TextStyle(
                      fontSize: 10,
                      color: who,
                    ),
                  ),
                ),
                label: Text(member['name']),
                selected: isSelected,
                onSelected: (bool selected) => setState(
                  () => _selectedMemberFilter = selected ? member['uid'] : null,
                ),
                selectedColor: who,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // --- CLEAN HELPERS ---
  List<EventModel> _getEventsForDay(DateTime day) {
    final checkDay = DateTime(day.year, day.month, day.day);

    final eventsOnDay = _allEvents.where((event) {
      DateTime start = event.start;
      DateTime end = event.end;
      DateTime dayStart = DateTime(start.year, start.month, start.day);
      DateTime dayEnd = DateTime(end.year, end.month, end.day);
      return (checkDay.isAtSameMomentAs(dayStart) ||
              checkDay.isAfter(dayStart)) &&
          (checkDay.isAtSameMomentAs(dayEnd) || checkDay.isBefore(dayEnd));
    }).toList();

    final memberFiltered = eventsOnDay.where((event) {
      if (event.category == 'meal') return false;
      if (_selectedMemberFilter == null) return true;
      return event.assignedTo == _selectedMemberFilter ||
          event.assignedTo == 'shared';
    }).toList();

    return memberFiltered.where((event) {
      if (event.assignedTo == 'shared' && (_filters['shared'] == false))
        return false;
      return _filters[event.category] ?? true;
    }).toList();
  }

  String _getAssignedName(String? uid) {
    if (uid == 'shared') return 'Shared';
    final member = _hubMembers.firstWhere(
      (m) => m['uid'] == uid,
      orElse: () => {'name': 'Unknown'},
    );
    return member['name'];
  }

  List<EventModel> _getProjectedBirthdays() {
    List<EventModel> virtualEvents = [];
    final int currentYear = DateTime.now().year;
    for (var b in _birthdays) {
      int month = b['month'];
      int day = b['day'];
      int? year = b['year']; // Optional!

      for (int y = currentYear - 1; y <= currentYear + 2; y++) {
        String title = year != null
            ? "${b['name']} (${y - year})"
            : "${b['name']}";
        DateTime date = DateTime(y, month, day);
        virtualEvents.add(
          EventModel(
            id: 'bday_${b['id']}_$y', // Unique virtual ID
            summary: title,
            start: date,
            end: date,
            allDay: true,
            category: 'birthday',
            assignedTo: 'shared',
            ownerId: 'system',
          ),
        );
      }
    }
    return virtualEvents;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_activeHubId == null)
      return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text(
          "Calendar",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (c) => IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => Scaffold.of(c).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _importFromGoogle,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.pink,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.pink,
          isScrollable: true,
          tabs: const [
            Tab(text: "Calendar"),
            Tab(text: "Overview"),
            Tab(text: "General"),
            Tab(text: "Work"),
            Tab(text: "Birthdays"),
          ],
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.pink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.calendar_month, color: Colors.white, size: 40),
                  SizedBox(height: 10),
                  Text(
                    "Filters & Sync",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "TARGET CALENDAR",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isLoadingCalendars)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_googleCalendars.isEmpty)
              ListTile(
                leading: const Icon(Icons.link, color: Colors.blue),
                title: const Text("Connect Google Calendar"),
                subtitle: const Text("Tap to sign in"),
                onTap: _connectGoogleCalendar,
              )
            else
              ..._googleCalendars.map(
                (cal) => RadioListTile<String>(
                  title: Text(cal.summary ?? "Unknown"),
                  value: cal.id!,
                  groupValue: _selectedCalendarId,
                  onChanged: (val) => _saveTargetCalendar(val!),
                  dense: true,
                ),
              ),
            const Divider(),
            SwitchListTile(
              title: const Text("Shared Plans"),
              secondary: const Icon(Icons.favorite, color: CalendarColors.shared),
              value: _filters['shared']!,
              activeColor: CalendarColors.shared,
              onChanged: (v) => setState(() => _filters['shared'] = v),
            ),
            SwitchListTile(
              title: const Text("Work"),
              secondary: const Icon(Icons.work, color: CalendarColors.work),
              value: _filters['work']!,
              activeColor: CalendarColors.work,
              onChanged: (v) => setState(() => _filters['work'] = v),
            ),
            SwitchListTile(
              title: const Text("Birthdays"),
              secondary: const Icon(Icons.cake, color: CalendarColors.birthday),
              value: _filters['birthday']!,
              activeColor: CalendarColors.birthday,
              onChanged: (v) => setState(() => _filters['birthday'] = v),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.blue.shade100],
          ),
        ),
        child: Column(
          children: [
            _buildMemberFilter(),
            Expanded(
              child: StreamBuilder<List<EventModel>>(
                stream: _eventRepo.streamEvents(_activeHubId!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());

                  _allEvents = [...snapshot.data!, ..._getProjectedBirthdays()];

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(
                        child: Column(
                          children: [
                            TableCalendar(
                              firstDay: DateTime.utc(2020, 1, 1),
                              lastDay: DateTime.utc(2030, 12, 31),
                              focusedDay: _focusedDay,
                              calendarFormat: _calendarFormat,
                              selectedDayPredicate: (day) =>
                                  isSameDay(_selectedDay, day),
                              onDaySelected: (s, f) => setState(() {
                                _selectedDay = s;
                                _focusedDay = f;
                              }),
                              eventLoader: _getEventsForDay,
                              calendarStyle: const CalendarStyle(
                                todayDecoration: BoxDecoration(
                                  color: Color(0xFF8A8680),
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                              ),
                              calendarBuilders: CalendarBuilders(
                                markerBuilder: (context, date, dynamicEvents) {
                                  if (dynamicEvents.isEmpty)
                                    return const SizedBox();
                                  final events = dynamicEvents
                                      .cast<EventModel>();
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: events.take(3).map((e) {
                                      final style = CalendarColors.fromEvent(
                                        e,
                                        palette: _palette,
                                      );
                                      return CalendarGlanceDot(
                                        style: style,
                                        size: 7,
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: CalendarGlanceLegend(
                                palette: _palette,
                                compact: true,
                                dark: false,
                              ),
                            ),
                            const Divider(),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "Schedule for ${DateFormat('MMM d').format(_selectedDay ?? DateTime.now())}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final events = _getEventsForDay(
                                  _selectedDay ?? DateTime.now(),
                                );
                                // --- FIX: Sort overview by time ---
                                events.sort(
                                  (a, b) => a.start.compareTo(b.start),
                                );

                                if (events.isEmpty)
                                  return const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      "No events",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  );

                                return ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: events.length,
                                  // --- FIX: Add Avatar to overview items ---
                                  itemBuilder: (context, index) =>
                                      _buildEventTile(
                                        events[index],
                                        showAvatar: true,
                                      ),
                                );
                              },
                            ),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),

                      _buildFilteredList(
                        (e) => true,
                        "No events found",
                        Icons.event_note,
                        showAvatar: true,
                        fillMissingDays: true, // <-- NEW
                      ),
                      _buildFilteredList(
                        (e) => e.category == 'general',
                        "No general events",
                        Icons.event,
                        showAvatar: true,
                        fillMissingDays: true, // <-- NEW
                      ),
                      _buildFilteredList(
                        (e) => e.category == 'work',
                        "No work shifts",
                        Icons.work,
                        showAvatar: true,
                        fillMissingDays: true, // <-- NEW
                      ),
                      _buildFilteredList(
                        (e) => e.category == 'birthday',
                        "No birthdays",
                        Icons.cake_outlined,
                        showAvatar: true,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditOrImportDialog(),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFilteredList(
    bool Function(EventModel) filter,
    String emptyMsg,
    IconData icon, {
    bool hideSubtitle = false,
    bool showAvatar = false,
    bool fillMissingDays = false, // <-- ADDED THIS BACK!
  }) {
    // 1. Get absolute midnight today (Safely strips time!)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 2. Filter events (Keeping shared events visible!)
    final events = _allEvents.where((e) {
      if (e.category == 'meal') return false;

      // If a member is selected, ONLY show their events AND shared events
      if (_selectedMemberFilter != null) {
        if (e.assignedTo != _selectedMemberFilter && e.assignedTo != 'shared') {
          return false;
        }
      }

      // Use e.end to keep multi-day events visible until they finish
      final eventEnd = DateTime(e.end.year, e.end.month, e.end.day);
      final isUpcoming =
          eventEnd.isAtSameMomentAs(today) || eventEnd.isAfter(today);

      return filter(e) && isUpcoming;
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    // =========================================================
    // VIEW 1: SPARSE LIST (Used for Birthdays)
    // =========================================================
    if (!fillMissingDays) {
      if (events.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 60, color: Colors.grey.shade300),
              const SizedBox(height: 10),
              Text(emptyMsg, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final doc = events[index];
          bool showHeader =
              index == 0 ||
              events[index - 1].start.day != doc.start.day ||
              events[index - 1].start.month != doc.start.month;
          return Column(
            children: [
              if (showHeader) _buildDateHeader(doc.start),
              _buildEventTile(
                doc,
                hideSubtitle: hideSubtitle,
                showAvatar: showAvatar,
              ),
            ],
          );
        },
      );
    }

    // =========================================================
    // VIEW 2: CONTINUOUS TIMELINE (Used for Overview, Work, General)
    // =========================================================
    int daysToShow = 30;
    if (events.isNotEmpty) {
      final lastEvent = events.last.start;
      final diff =
          DateTime(
                lastEvent.year,
                lastEvent.month,
                lastEvent.day,
              ).difference(today).inHours ~/
              24 +
          1;
      if (diff > daysToShow) daysToShow = diff + 2;
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: daysToShow,
      itemBuilder: (context, index) {
        // DST Safe Math!
        final currentDay = DateTime(today.year, today.month, today.day + index);

        final dayEvents = events.where((e) {
          final dayStart = DateTime(e.start.year, e.start.month, e.start.day);
          final dayEnd = DateTime(e.end.year, e.end.month, e.end.day);
          return (currentDay.isAtSameMomentAs(dayStart) ||
                  currentDay.isAfter(dayStart)) &&
              (currentDay.isAtSameMomentAs(dayEnd) ||
                  currentDay.isBefore(dayEnd));
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateHeader(currentDay),
            if (dayEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 4, bottom: 20),
                child: Text(
                  "Nothing scheduled",
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              )
            else
              ...dayEvents.map(
                (e) => _buildEventTile(
                  e,
                  hideSubtitle: hideSubtitle,
                  showAvatar: showAvatar,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date) {
    String label = DateFormat('EEEE, d MMMM').format(date);
    if (isSameDay(date, DateTime.now())) label = "Today • $label";
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          // --- NEW: Wrap the existing container in a GestureDetector! ---
          GestureDetector(
            onTap: () => _showEditOrImportDialog(initialDate: date),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _buildEventTile(
    EventModel event, {
    bool hideSubtitle = false,
    bool showAvatar = false,
  }) {
    final style = CalendarColors.fromEvent(event, palette: _palette);

    bool isMulti = !isSameDay(event.start, event.end);
    String cleanTitle = event.summary.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    if (cleanTitle.isEmpty) cleanTitle = event.summary;

    Widget? avatarWidget;
    if (showAvatar && event.assignedTo != 'shared') {
      final member = _hubMembers.firstWhere(
        (m) => m['uid'] == event.assignedTo,
        orElse: () => {'name': '?', 'photoURL': ''},
      );
      final pUrl = member['photoURL'] as String?;
      final initial = member['name'][0].toUpperCase();

      if (pUrl != null && pUrl.isNotEmpty) {
        avatarWidget = CircleAvatar(
          backgroundImage: NetworkImage(pUrl),
          radius: 14,
        );
      } else {
        avatarWidget = CircleAvatar(
          backgroundColor: Colors.white.withValues(alpha: 0.22),
          radius: 14,
          child: Text(
            initial,
            style: TextStyle(
              color: style.inkOnWho,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        );
      }
    } else if (event.assignedTo == 'shared') {
      avatarWidget = Icon(
        Icons.favorite,
        size: 16,
        color: style.inkOnWho,
      );
    }

    final timeLabel = hideSubtitle || (event.allDay && !isMulti)
        ? null
        : isMulti
        ? "${DateFormat('d MMM').format(event.start)} - ${DateFormat('d MMM').format(event.end)}"
        : "${DateFormat('HH:mm').format(event.start)} - ${DateFormat('HH:mm').format(event.end)}";

    return CalendarSplitPill(
      style: style,
      title: cleanTitle,
      subtitle: timeLabel,
      density: CalendarSplitPillDensity.regular,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      onTap: () => _showEditOrImportDialog(existingEvent: event),
      leading: avatarWidget,
      trailing: event.category == 'birthday'
          ? Icon(_getBdayIcon(event.id), size: 18)
          : event.category == 'work'
          ? const Icon(Icons.work, size: 16)
          : null,
    );
  }
}
