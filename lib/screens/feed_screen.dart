import 'dart:async';
import 'package:flutter/material.dart';
import '../services/event_sanity.dart';
import '../services/shared_streams.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'dashboard_screen.dart';
import 'manage_hub_screen.dart';
import 'food_screen.dart';
import '../repositories/rota_repository.dart';
import '../services/member_profile.dart';
import '../theme/calendar_colors.dart';
import '../widgets/member_avatar.dart';
import '../models/quote_model.dart';
import '../repositories/quote_repository.dart';
import '../services/home_feed_logic.dart';
import '../services/home_feed_weather.dart';
import '../widgets/home_feed/home_feed_view.dart';

class FeedScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> joinedHubs;
  final Map<String, dynamic> pendingHubs;
  final List<MapEntry<String, dynamic>> visibleHubs;

  /// Switches the bottom tab (cards tap through to their section).
  final ValueChanged<int>? onOpenTab;

  const FeedScreen({
    this.onOpenTab,
    super.key,
    required this.user,
    required this.joinedHubs,
    required this.pendingHubs,
    required this.visibleHubs,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  // Existing Task trackers
  final Set<String> _locallyCompleted = {};
  final Map<String, Timer> _completionTimers = {};

  // --- NEW: Chore Trackers ---
  final Set<String> _locallyCompletedChores = {};
  final Map<String, Timer> _choreCompletionTimers = {};
  final Map<String, String> _choreWeekIds = {};

  Map<String, Map<String, dynamic>> _hubMembers = {};
  List<Map<String, dynamic>> _birthdays = [];

  Timer? _midnightTimer;

  StreamSubscription<QuerySnapshot>? _birthdaySub;
  StreamSubscription<List<QuoteModel>>? _quoteSub;
  QuoteModel? _quote;
  FeedWeather? _weather;
  Timer? _weatherTimer;
  late final HubMemberDirectory _memberDirectory;

  /// One Firestore listener per query for this screen's lifetime; build()
  /// only looks streams up here (see [SharedStreams]).
  final SharedStreams _streams = SharedStreams();
  @visibleForTesting
  SharedStreams get debugStreams => _streams;

  @override
  void initState() {
    super.initState();
    _memberDirectory = HubMemberDirectory(
      currentUser: widget.user,
      onChanged: (members) {
        if (!mounted) return;
        setState(() {
          _hubMembers = {
            for (final member in members) member['uid'].toString(): member,
          };
        });
      },
    );
    _listenToHubMembers();

    if (widget.visibleHubs.isNotEmpty) {
      _birthdaySub = FirebaseFirestore.instance
          .collection('hubs')
          .doc(widget.visibleHubs.first.key)
          .collection('birthdays')
          .snapshots()
          .listen((snap) {
            if (mounted) {
              setState(() {
                _birthdays = snap.docs
                    .map((d) => {'id': d.id, ...d.data()})
                    .toList();
              });
            }
          });
    }

    // Ticks every minute: keeps the hero countdown and the day fresh.
    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });

    _listenToQuotes();
    _loadWeather();
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _loadWeather(),
    );
  }

  void _listenToQuotes() {
    _quoteSub?.cancel();
    if (widget.visibleHubs.isEmpty) return;
    _quoteSub = FirestoreQuoteRepository()
        .watch(widget.visibleHubs.first.key)
        .listen((quotes) {
          if (!mounted) return;
          final usable = quotes.where((q) => q.text.isNotEmpty).toList();
          final day = DateTime.now().difference(DateTime(2026)).inDays;
          setState(
            () => _quote = usable.isEmpty ? null : usable[day % usable.length],
          );
        }, onError: (_) {});
  }

  Future<void> _loadWeather() async {
    final w = await fetchHomeFeedWeather(widget.user.uid);
    if (mounted && w != null) setState(() => _weather = w);
  }

  HomeFeedData _feedData({
    required List<Map<String, dynamic>> allEvents,
    required List<QueryDocumentSnapshot> allItems,
    required Map<String, dynamic>? rotaInfo,
    required List<String> completedChores,
  }) {
    final chores = <FeedChore>[];
    if (rotaInfo != null && rotaInfo['isStarted'] == true) {
      for (final c in List<Map<String, dynamic>>.from(
        rotaInfo['chores'] ?? const [],
      )) {
        final id = (c['id'] ?? '').toString();
        chores.add(
          FeedChore(
            id: id,
            title: (c['title'] ?? 'Chore').toString(),
            assignedTo: (c['assignedTo'] ?? 'shared').toString(),
            minutes: (c['effortMinutes'] as num?)?.toInt(),
            done:
                completedChores.contains(id) ||
                _locallyCompletedChores.contains(id),
          ),
        );
      }
    }
    final tasks = <FeedTask>[];
    for (final doc in allItems) {
      final m = doc.data() as Map<String, dynamic>;
      if (m['status'] == 'pending_acceptance') continue;
      final due = m['dueDate'];
      tasks.add(
        FeedTask(
          id: doc.id,
          text: (m['text'] ?? '').toString(),
          listName: (m['listName'] ?? 'General').toString(),
          urgent: m['isUrgent'] == true,
          due: due is Timestamp ? due.toDate() : null,
          assignedTo: (m['assignedTo'] ?? 'shared').toString(),
          done: _locallyCompleted.contains(doc.id),
        ),
      );
    }
    return HomeFeedData(
      now: DateTime.now(),
      myUid: widget.user.uid,
      names: {
        for (final e in _hubMembers.entries)
          e.key: (e.value['name'] ?? '').toString().split(' ').first,
      },
      events: allEvents,
      chores: chores,
      tasks: tasks,
      weather: _weather,
      quote: _quote?.text,
      quoteAuthor: _quote?.author,
    );
  }

  void _onChoreToggled(
    BuildContext context,
    String hubId,
    String choreId,
    String weekId,
    bool done,
  ) {
    if (done) {
      setState(() => _locallyCompletedChores.add(choreId));
      _choreWeekIds[choreId] = weekId;
      _choreCompletionTimers[choreId]?.cancel();
      _choreCompletionTimers[choreId] = Timer(const Duration(seconds: 10), () {
        _toggleWeeklyChore(hubId, choreId, true, weekId);
        _choreCompletionTimers.remove(choreId);
        _choreWeekIds.remove(choreId);
        if (mounted) setState(() => _locallyCompletedChores.remove(choreId));
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Chore completed 🎉'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.deepPurpleAccent,
            onPressed: () {
              _choreCompletionTimers[choreId]?.cancel();
              _choreCompletionTimers.remove(choreId);
              _choreWeekIds.remove(choreId);
              setState(() => _locallyCompletedChores.remove(choreId));
            },
          ),
        ),
      );
    } else {
      _choreCompletionTimers[choreId]?.cancel();
      _choreCompletionTimers.remove(choreId);
      _choreWeekIds.remove(choreId);
      setState(() => _locallyCompletedChores.remove(choreId));
      _toggleWeeklyChore(hubId, choreId, false, weekId);
    }
  }

  void _completeTask(BuildContext context, QueryDocumentSnapshot t) {
    if (_locallyCompleted.contains(t.id)) {
      _completionTimers[t.id]?.cancel();
      _completionTimers.remove(t.id);
      setState(() => _locallyCompleted.remove(t.id));
      return;
    }
    setState(() => _locallyCompleted.add(t.id));
    _completionTimers[t.id] = Timer(const Duration(seconds: 10), () {
      t.reference.update({'isDone': true});
      _completionTimers.remove(t.id);
      if (mounted) setState(() => _locallyCompleted.remove(t.id));
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Task completed'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Colors.tealAccent,
          onPressed: () {
            _completionTimers[t.id]?.cancel();
            _completionTimers.remove(t.id);
            setState(() => _locallyCompleted.remove(t.id));
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _streams.dispose();
    _midnightTimer?.cancel();
    _weatherTimer?.cancel();
    _quoteSub?.cancel();

    // Save pending Tasks
    for (var entry in _completionTimers.entries) {
      entry.value.cancel();
      if (widget.visibleHubs.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('hubs')
            .doc(widget.visibleHubs.first.key)
            .collection('items')
            .doc(entry.key)
            .update({'isDone': true});
      }
    }

    // --- NEW: Save pending Chores ---
    for (var entry in _choreCompletionTimers.entries) {
      entry.value.cancel();
      final weekId = _choreWeekIds[entry.key];
      if (weekId != null && widget.visibleHubs.isNotEmpty) {
        _toggleWeeklyChore(
          widget.visibleHubs.first.key,
          entry.key,
          true,
          weekId,
        );
      }
    }

    _birthdaySub?.cancel();
    _memberDirectory.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldHubId = oldWidget.visibleHubs.isNotEmpty
        ? oldWidget.visibleHubs.first.key
        : null;
    final newHubId = widget.visibleHubs.isNotEmpty
        ? widget.visibleHubs.first.key
        : null;

    if (oldHubId != newHubId) {
      _listenToHubMembers();
      _listenToBirthdays();
      _listenToQuotes();
    }
  }

  void _listenToBirthdays() {
    _birthdaySub?.cancel();
    if (widget.visibleHubs.isNotEmpty) {
      _birthdaySub = FirebaseFirestore.instance
          .collection('hubs')
          .doc(widget.visibleHubs.first.key)
          .collection('birthdays')
          .snapshots()
          .listen((snap) {
            if (mounted) {
              setState(() {
                _birthdays = snap.docs
                    .map((d) => {'id': d.id, ...d.data()})
                    .toList();
              });
            }
          });
    } else {
      if (mounted) setState(() => _birthdays = []);
    }
  }

  HubMemberPalette get _feedPalette =>
      HubMemberPalette.fromMembers(_hubMembers.values);

  void _listenToHubMembers() {
    if (widget.visibleHubs.isEmpty) {
      _memberDirectory.watch(null);
      return;
    }
    _memberDirectory.watch(widget.visibleHubs.first.key);
  }

  List<Map<String, dynamic>> _getProjectedBirthdays() {
    List<Map<String, dynamic>> virtualEvents = [];
    final int currentYear = DateTime.now().year;
    for (var b in _birthdays) {
      int month = b['month'];
      int day = b['day'];
      int? year = b['year'];

      for (int y = currentYear - 1; y <= currentYear + 2; y++) {
        String title = year != null
            ? "${b['name']}'s ${y - year}th Birthday"
            : "${b['name']}'s Birthday";
        DateTime date = DateTime(y, month, day);
        virtualEvents.add({
          'id': 'bday_${b['id']}_$y',
          'summary': title,
          'start': Timestamp.fromDate(date),
          'end': Timestamp.fromDate(date),
          'allDay': true,
          'category': 'birthday',
          'assignedTo': 'shared',
        });
      }
    }
    return virtualEvents;
  }

  // --- NEW: Weekly Rota Helpers ---
  Map<String, dynamic>? _getWeeklyRotaInfo(
    Map<String, dynamic>? rotaConfig,
    DateTime now,
  ) {
    if (rotaConfig == null || rotaConfig['anchorDate'] == null) return null;
    if (rotaConfig.containsKey('cycleLength')) return {'isLegacy': true};

    final anchorDate = (rotaConfig['anchorDate'] as Timestamp).toDate();
    final daysSince = DateUtils.dateOnly(
      now,
    ).difference(DateUtils.dateOnly(anchorDate)).inDays;

    if (daysSince < 0) return {'isStarted': false, 'isLegacy': false};

    int absoluteWeekNum = (daysSince ~/ 7) + 1;
    int currentCycleWeek = ((daysSince ~/ 7) % 8) + 1;

    final startOfWeek = DateUtils.dateOnly(
      anchorDate,
    ).add(Duration(days: (absoluteWeekNum - 1) * 7));
    final weekId = DateFormat('yyyy-MM-dd').format(startOfWeek);

    final blueprint = rotaConfig['blueprint'] as Map<String, dynamic>? ?? {};
    final weekChores = List<Map<String, dynamic>>.from(
      blueprint[currentCycleWeek.toString()] ?? [],
    );

    return {
      'isLegacy': false,
      'isStarted': true,
      'weekId': weekId,
      'weekNum': absoluteWeekNum,
      'chores': weekChores,
    };
  }

  void _toggleWeeklyChore(
    String hubId,
    String choreId,
    bool isDone,
    String weekId,
  ) {
    final docRef = FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('rota_logs')
        .doc('week_$weekId');
    if (isDone) {
      docRef.set({
        'completed': FieldValue.arrayUnion([choreId]),
      }, SetOptions(merge: true));
    } else {
      docRef.set({
        'completed': FieldValue.arrayRemove([choreId]),
      }, SetOptions(merge: true));
    }
  }

  Widget _buildTopAvatar(String? uid) {
    if (uid == null || !_hubMembers.containsKey(uid)) {
      return MemberAvatar(
        radius: 50,
        backgroundColor: Colors.grey.shade300,
        foregroundColor: Colors.white,
        border: Border.all(color: Colors.grey.shade200, width: 2),
        icon: Icons.person,
      );
    }

    final data = _hubMembers[uid]!;
    return MemberAvatar(
      photoURL: data['photoURL']?.toString(),
      name: data['name']?.toString(),
      radius: 48,
      backgroundColor: Colors.indigo.shade400,
      border: Border.all(color: Colors.grey.shade300, width: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleHubs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: widget.pendingHubs.isNotEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      size: 60,
                      color: Colors.orange.shade400,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Request Sent!",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Waiting for approval to join:\n${widget.pendingHubs.values.first}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Please join or create a Hub from the side menu.',
                  style: TextStyle(color: Colors.grey),
                ),
        ),
      );
    }

    final activeHubId = widget.visibleHubs.first.key;
    // Day-granular so the query (and its listener) only changes once a day.
    final lookBack = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(const Duration(days: 60));
    final dayKey = DateFormat('yyyy-MM-dd').format(lookBack);
    _streams.evictPrefix(
      'events:$activeHubId:',
      keep: 'events:$activeHubId:$dayKey',
    );

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        tooltip: 'Open Dashboard',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(visibleHubs: widget.visibleHubs),
          ),
        ),
        child: const Icon(Icons.tv),
      ),

      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _streams.watch(
          'rota:$activeHubId',
          () => RotaRepository().streamRotaConfig(activeHubId),
        ),
        builder: (context, rotaSnapshot) {
          final rotaConfig = rotaSnapshot.data;
          final rotaInfo = _getWeeklyRotaInfo(rotaConfig, DateTime.now());
          final String logDocId = rotaInfo?['weekId'] != null
              ? 'week_${rotaInfo!['weekId']}'
              : 'dummy_log';

          _streams.evictPrefix(
            'log:$activeHubId:',
            keep: 'log:$activeHubId:$logDocId',
          );
          return StreamBuilder<DocumentSnapshot>(
            stream: _streams.watch(
              'log:$activeHubId:$logDocId',
              () => FirebaseFirestore.instance
                  .collection('hubs')
                  .doc(activeHubId)
                  .collection('rota_logs')
                  .doc(logDocId)
                  .snapshots(),
            ),
            builder: (context, weeklyLogSnapshot) {
              final weeklyLogDoc = weeklyLogSnapshot.data;

              List<String> completedChores = [];
              if (weeklyLogDoc != null && weeklyLogDoc.exists) {
                completedChores = List<String>.from(
                  (weeklyLogDoc.data() as Map<String, dynamic>)['completed'] ??
                      [],
                );
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _streams.watch(
                  'notifs:$activeHubId',
                  () => FirebaseFirestore.instance
                      .collection('hubs')
                      .doc(activeHubId)
                      .collection('notifications')
                      .where('toUid', isEqualTo: widget.user.uid)
                      .where('isRead', isEqualTo: false)
                      .snapshots(),
                ),
                builder: (context, notifSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _streams.watch(
                      'events:$activeHubId:$dayKey',
                      () => FirebaseFirestore.instance
                          .collection('hubs')
                          .doc(activeHubId)
                          .collection('events')
                          .where(
                            'start',
                            isGreaterThan: Timestamp.fromDate(lookBack),
                          )
                          .orderBy('start')
                          .snapshots(),
                    ),
                    builder: (context, eventSnapshot) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _streams.watch(
                          'items:$activeHubId',
                          () => FirebaseFirestore.instance
                              .collection('hubs')
                              .doc(activeHubId)
                              .collection('items')
                              .where('isDone', isEqualTo: false)
                              .snapshots(),
                        ),
                        builder: (context, itemSnapshot) {
                          if (!eventSnapshot.hasData && !eventSnapshot.hasError)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!itemSnapshot.hasData && !itemSnapshot.hasError)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );

                          final rawEvents = sanitizeEventMaps(
                            (eventSnapshot.data?.docs ?? const []).map(
                              (d) => {
                                'id': d.id,
                                ...d.data() as Map<String, dynamic>,
                              },
                            ),
                          );
                          final allEvents = [
                            ...rawEvents,
                            ..._getProjectedBirthdays(),
                          ];

                          final allItems = itemSnapshot.data?.docs ?? [];

                          final pendingNotifs =
                              notifSnapshot.data?.docs.toList() ?? [];
                          pendingNotifs.sort((a, b) {
                            final aTime =
                                (a.data() as Map<String, dynamic>)['createdAt']
                                    as Timestamp?;
                            final bTime =
                                (b.data() as Map<String, dynamic>)['createdAt']
                                    as Timestamp?;
                            if (aTime == null || bTime == null) return 0;
                            return bTime.compareTo(aTime);
                          });

                          final pendingTasks = allItems.where((d) {
                            final m = d.data() as Map<String, dynamic>;
                            final bool isPending =
                                m['status'] == 'pending_acceptance';
                            final bool isAssignedToMe =
                                m['assignedTo'] == widget.user.uid;
                            final bool isCreatedByMe =
                                m['createdBy'] == widget.user.uid;
                            return isPending &&
                                (isAssignedToMe || isCreatedByMe);
                          }).toList();

                          final List<String> rawMembers = _hubMembers.keys
                              .toList();

                          return CustomScrollView(
                            slivers: [
                              // --- COMPACT HEADER ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    50,
                                    20,
                                    20,
                                  ),
                                  child: Column(
                                    children: [
                                      Builder(
                                        builder: (context) {
                                          final firstName =
                                              widget.user.displayName?.split(
                                                ' ',
                                              )[0] ??
                                              '';
                                          return Text(
                                            feedGreeting(
                                              DateTime.now(),
                                              firstName,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w300,
                                              color: Color.fromARGB(
                                                221,
                                                120,
                                                120,
                                                120,
                                              ),
                                              letterSpacing: -0.5,
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _buildTopAvatar(
                                            rawMembers.isNotEmpty
                                                ? rawMembers[0].toString()
                                                : null,
                                          ),
                                          const SizedBox(width: 20),
                                          Column(
                                            children: [
                                              Text(
                                                (widget.joinedHubs[activeHubId]?['name'] ??
                                                        'Your Hub')
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.black45,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Image.asset(
                                                'assets/logo.png',
                                                height: 100,
                                                width: 100,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (ctx, err, stack) => Icon(
                                                      Icons.favorite,
                                                      color:
                                                          Colors.pink.shade400,
                                                      size: 54,
                                                    ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 20),
                                          _buildTopAvatar(
                                            rawMembers.length > 1
                                                ? rawMembers[1].toString()
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // --- ALERTS ---
                              if (widget.pendingHubs.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.orange.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.hourglass_empty,
                                          color: Colors.orange.shade700,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            "You have ${widget.pendingHubs.length} pending request(s) waiting for approval.",
                                            style: TextStyle(
                                              color: Colors.orange.shade900,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              if (widget.joinedHubs[activeHubId]?['role'] ==
                                  'admin')
                                StreamBuilder<QuerySnapshot>(
                                  stream: _streams.watch(
                                    'requests:$activeHubId',
                                    () => FirebaseFirestore.instance
                                        .collection('hubs')
                                        .doc(activeHubId)
                                        .collection('requests')
                                        .snapshots(),
                                  ),
                                  builder: (context, reqSnapshot) {
                                    if (!reqSnapshot.hasData ||
                                        reqSnapshot.data!.docs.isEmpty)
                                      return const SliverToBoxAdapter(
                                        child: SizedBox(),
                                      );
                                    return SliverToBoxAdapter(
                                      child: GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ManageHubScreen(
                                              hubId: activeHubId,
                                              hubName:
                                                  widget
                                                      .joinedHubs[activeHubId]?['name'] ??
                                                  'Hub',
                                              currentUserId: widget.user.uid,
                                            ),
                                          ),
                                        ),
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            16,
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.red.shade300,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.person_add_alt_1,
                                                color: Colors.red,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  "${reqSnapshot.data!.docs.length} person wants to join your Hub! Tap here to manage.",
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              if (pendingNotifs.isNotEmpty ||
                                  pendingTasks.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'NEEDS ATTENTION',
                                  icon: Icons.notifications_active_rounded,
                                  color: Colors.deepOrange,
                                ),
                                SliverList(
                                  delegate: SliverChildListDelegate([
                                    ...pendingNotifs.map(
                                      (n) => _buildNotificationCard(
                                        n,
                                        activeHubId,
                                      ),
                                    ),
                                    ...pendingTasks.map(
                                      (t) => _buildTaskTile(t),
                                    ),
                                  ]),
                                ),
                              ],

                              // --- Legacy rota notice ---
                              if (rotaInfo != null &&
                                  rotaInfo['isLegacy'] == true)
                                SliverToBoxAdapter(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.deepPurple.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.deepPurple.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          color: Colors.deepPurple.shade400,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "Your Household Rota has been upgraded! Head over to the Rota tab to generate your new 8-Week Plan.",
                                            style: TextStyle(
                                              color: Colors.deepPurple.shade800,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // --- ADAPTIVE HOME FEED ---
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: HomeFeedView(
                                    data: _feedData(
                                      allEvents: allEvents,
                                      allItems: allItems,
                                      rotaInfo: rotaInfo,
                                      completedChores: completedChores,
                                    ),
                                    palette: _feedPalette,
                                    onOpenTab: widget.onOpenTab,
                                    onToggleChore: (chore, done) =>
                                        _onChoreToggled(
                                          context,
                                          activeHubId,
                                          chore.id,
                                          rotaInfo!['weekId'] as String,
                                          done,
                                        ),
                                    onCompleteTask: (t) {
                                      final doc = allItems
                                          .where((d) => d.id == t.id)
                                          .firstOrNull;
                                      if (doc != null) {
                                        _completeTask(context, doc);
                                      }
                                    },
                                    onPrepMeal: (m) => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => IngredientReviewSheet(
                                        mealTitle: m['summary'],
                                        ingredients: m['ingredients'],
                                        hubId: activeHubId,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 100),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {IconData? icon, Color? color}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color ?? Colors.grey),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: TextStyle(
                color: color ?? Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(QueryDocumentSnapshot doc, String hubId) {
    final d = doc.data() as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: ListTile(
          leading: const Icon(
            Icons.notifications_active,
            color: Colors.deepOrange,
          ),
          title: Text(
            d['text'] ?? 'New notification',
            style: TextStyle(color: Colors.orange.shade900),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.check, color: Colors.deepOrange),
            onPressed: () => doc.reference.update({'isRead': true}),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTile(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final bool isWaitingOnMe = d['assignedTo'] == widget.user.uid;

    if (isWaitingOnMe) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: ListTile(
            leading: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.blue,
            ),
            title: Text(
              d['text'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Pending your acceptance',
              style: TextStyle(color: Colors.blue),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.blue),
              onPressed: () => doc.reference.update({'status': 'open'}),
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: ListTile(
            leading: Icon(
              Icons.hourglass_top_rounded,
              color: Colors.orange.shade700,
            ),
            title: Text(
              d['text'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
              ),
            ),
            subtitle: Text(
              'Waiting for partner to accept...',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }
  }
}
