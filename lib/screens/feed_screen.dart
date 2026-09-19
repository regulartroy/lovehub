import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'dashboard_screen.dart';
import 'manage_hub_screen.dart';
import 'food_screen.dart';
import '../repositories/rota_repository.dart';
import '../services/member_profile.dart';
import '../widgets/member_avatar.dart';

class FeedScreen extends StatefulWidget {
  final User user;
  final Map<String, dynamic> joinedHubs;
  final Map<String, dynamic> pendingHubs;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const FeedScreen({
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
  DateTime _currentDay = DateUtils.dateOnly(DateTime.now());

  StreamSubscription<QuerySnapshot>? _birthdaySub;
  late final HubMemberDirectory _memberDirectory;

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
      FirebaseFirestore.instance
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

    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateUtils.dateOnly(DateTime.now());
      if (now.isAfter(_currentDay)) {
        setState(() => _currentDay = now);
      }
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();

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

  bool _eventOverlapsDay(Map<String, dynamic> data, DateTime day) {
    if (data['start'] == null) return false;
    final checkDay = DateUtils.dateOnly(day);
    final DateTime s = (data['start'] as Timestamp).toDate();
    final DateTime e = data['end'] != null
        ? (data['end'] as Timestamp).toDate()
        : s;
    final dayStart = DateUtils.dateOnly(s);
    final dayEnd = DateUtils.dateOnly(e);
    return (checkDay.isAtSameMomentAs(dayStart) ||
            checkDay.isAfter(dayStart)) &&
        (checkDay.isAtSameMomentAs(dayEnd) || checkDay.isBefore(dayEnd));
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
    final lookBack = DateTime.now().subtract(const Duration(days: 60));

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
        stream: RotaRepository().streamRotaConfig(activeHubId),
        builder: (context, rotaSnapshot) {
          final rotaConfig = rotaSnapshot.data;
          final rotaInfo = _getWeeklyRotaInfo(rotaConfig, DateTime.now());
          final String logDocId = rotaInfo?['weekId'] != null
              ? 'week_${rotaInfo!['weekId']}'
              : 'dummy_log';

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('hubs')
                .doc(activeHubId)
                .collection('rota_logs')
                .doc(logDocId)
                .snapshots(),
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
                stream: FirebaseFirestore.instance
                    .collection('hubs')
                    .doc(activeHubId)
                    .collection('notifications')
                    .where('toUid', isEqualTo: widget.user.uid)
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
                builder: (context, notifSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('hubs')
                        .doc(activeHubId)
                        .collection('events')
                        .where(
                          'start',
                          isGreaterThan: Timestamp.fromDate(lookBack),
                        )
                        .orderBy('start')
                        .snapshots(),
                    builder: (context, eventSnapshot) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('hubs')
                            .doc(activeHubId)
                            .collection('items')
                            .where('isDone', isEqualTo: false)
                            .snapshots(),
                        builder: (context, itemSnapshot) {
                          if (!eventSnapshot.hasData && !eventSnapshot.hasError)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!itemSnapshot.hasData && !itemSnapshot.hasError)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );

                          final rawEvents =
                              eventSnapshot.data?.docs
                                  .map((d) => d.data() as Map<String, dynamic>)
                                  .toList() ??
                              [];
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

                          final now = DateTime.now();
                          final todayStart = DateUtils.dateOnly(now);

                          final myEvents = allEvents.where((d) {
                            return d['assignedTo'] == widget.user.uid ||
                                d['assignedTo'] == 'shared';
                          }).toList();

                          final todaysEvents = myEvents.where((d) {
                            if (!_eventOverlapsDay(d, now)) return false;
                            final bool isAllDay = d['allDay'] ?? false;
                            if (!isAllDay) {
                              final DateTime s = (d['start'] as Timestamp)
                                  .toDate();
                              final DateTime e = d['end'] != null
                                  ? (d['end'] as Timestamp).toDate()
                                  : s;
                              if (e.isBefore(now)) return false;
                            }
                            return true;
                          }).toList();

                          todaysEvents.sort((a, b) {
                            final bool aAllDay = a['allDay'] ?? false;
                            final bool bAllDay = b['allDay'] ?? false;
                            if (aAllDay && !bAllDay) return -1;
                            if (!aAllDay && bAllDay) return 1;
                            final aStart = a['start'] as Timestamp;
                            final bStart = b['start'] as Timestamp;
                            return aStart.compareTo(bStart);
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

                          final activeItems = allItems.where((d) {
                            final m = d.data() as Map<String, dynamic>;
                            return m['status'] != 'pending_acceptance' &&
                                (m['assignedTo'] == widget.user.uid ||
                                    m['assignedTo'] == 'shared');
                          }).toList();

                          final priorityItems =
                              activeItems
                                  .where(
                                    (d) =>
                                        (d.data() as Map)['isUrgent'] == true,
                                  )
                                  .toList()
                                ..sort((a, b) {
                                  final aIsShop =
                                      (a.data() as Map)['listName'] ==
                                          'Shopping'
                                      ? 1
                                      : 0;
                                  final bIsShop =
                                      (b.data() as Map)['listName'] ==
                                          'Shopping'
                                      ? 1
                                      : 0;
                                  return aIsShop.compareTo(bIsShop);
                                });

                          final regularItems =
                              activeItems
                                  .where(
                                    (d) =>
                                        (d.data() as Map)['isUrgent'] != true,
                                  )
                                  .toList()
                                ..sort((a, b) {
                                  final aIsShop =
                                      (a.data() as Map)['listName'] ==
                                          'Shopping'
                                      ? 1
                                      : 0;
                                  final bIsShop =
                                      (b.data() as Map)['listName'] ==
                                          'Shopping'
                                      ? 1
                                      : 0;
                                  return aIsShop.compareTo(bIsShop);
                                });

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
                                          final hour = DateTime.now().hour;
                                          String greeting = hour < 12
                                              ? 'Good morning'
                                              : hour < 17
                                              ? 'Good afternoon'
                                              : 'Good evening';
                                          final firstName =
                                              widget.user.displayName?.split(
                                                ' ',
                                              )[0] ??
                                              '';
                                          return Text(
                                            firstName.isNotEmpty
                                                ? '$greeting, $firstName'
                                                : greeting,
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
                                  stream: FirebaseFirestore.instance
                                      .collection('hubs')
                                      .doc(activeHubId)
                                      .collection('requests')
                                      .snapshots(),
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

                              // --- 1. TODAY'S CALENDAR EVENTS ---
                              if (todaysEvents
                                  .where((e) => e['category'] != 'meal')
                                  .isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      children: todaysEvents
                                          .where((e) => e['category'] != 'meal')
                                          .map(
                                            (e) =>
                                                _buildHeroCard(e, todayStart),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),

                              // --- 2. PRIORITY ITEMS ---
                              if (priorityItems.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'PRIORITY',
                                  icon: Icons.priority_high_rounded,
                                  color: Colors.red,
                                ),
                                SliverList(
                                  delegate: SliverChildListDelegate(
                                    priorityItems
                                        .map(
                                          (item) => _buildCheckableTile(item),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],

                              // --- 3. TODAY'S MENU ---
                              if (todaysEvents
                                  .where((e) => e['category'] == 'meal')
                                  .isNotEmpty)
                                SliverToBoxAdapter(
                                  child: Builder(
                                    builder: (context) {
                                      final todaysMeals = todaysEvents
                                          .where((e) => e['category'] == 'meal')
                                          .toList();

                                      return Column(
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              20,
                                              24,
                                              20,
                                              8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.restaurant_menu,
                                                  size: 16,
                                                  color: Colors.green,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  "TODAY'S MENU",
                                                  style: TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            child: Column(
                                              children: todaysMeals.map((d) {
                                                final bool hasIngredients =
                                                    d.containsKey(
                                                      'ingredients',
                                                    ) &&
                                                    (d['ingredients'] as List)
                                                        .isNotEmpty;

                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          Colors.green.shade200,
                                                    ),
                                                  ),
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.restaurant,
                                                      color:
                                                          Colors.green.shade600,
                                                    ),
                                                    title: Text(
                                                      d['summary'] ?? '',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .green
                                                            .shade900,
                                                      ),
                                                    ),
                                                    trailing: hasIngredients
                                                        ? FilledButton(
                                                            style: FilledButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors
                                                                      .green
                                                                      .shade600,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                            ),
                                                            onPressed: () {
                                                              showModalBottomSheet(
                                                                context:
                                                                    context,
                                                                isScrollControlled:
                                                                    true,
                                                                backgroundColor:
                                                                    Colors
                                                                        .transparent,
                                                                builder: (_) => IngredientReviewSheet(
                                                                  mealTitle:
                                                                      d['summary'],
                                                                  ingredients:
                                                                      d['ingredients'],
                                                                  hubId:
                                                                      activeHubId,
                                                                ),
                                                              );
                                                            },
                                                            child: const Text(
                                                              "Prep",
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),

                              // --- 4. YOUR TASKS ---
                              if (regularItems.isNotEmpty) ...[
                                _buildSectionHeader(
                                  'YOUR TASKS',
                                  icon: Icons.check_circle_outline,
                                  color: Colors.amber.shade800,
                                ),
                                SliverList(
                                  delegate: SliverChildListDelegate(
                                    regularItems
                                        .map(
                                          (item) => _buildCheckableTile(item),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],

                              // --- 5. THIS WEEK'S CHORES ---
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
                                )
                              else if (rotaInfo != null &&
                                  rotaInfo['isStarted'] == true &&
                                  (rotaInfo['chores'] as List).isNotEmpty) ...[
                                _buildSectionHeader(
                                  'THIS WEEK\'S CHORES',
                                  icon: Icons.cleaning_services_rounded,
                                  color: Colors.deepPurple.shade400,
                                ),
                                SliverToBoxAdapter(
                                  child: Builder(
                                    builder: (context) {
                                      final weekChores =
                                          List<Map<String, dynamic>>.from(
                                            rotaInfo['chores'],
                                          );
                                      final String weekId = rotaInfo['weekId'];

                                      // Sort: Unfinished first, then by assigned person
                                      weekChores.sort((a, b) {
                                        bool aDone =
                                            completedChores.contains(a['id']) ||
                                            _locallyCompletedChores.contains(
                                              a['id'],
                                            );
                                        bool bDone =
                                            completedChores.contains(b['id']) ||
                                            _locallyCompletedChores.contains(
                                              b['id'],
                                            );
                                        if (aDone && !bDone) return 1;
                                        if (!aDone && bDone) return -1;
                                        int aIsMe =
                                            a['assignedTo'] == widget.user.uid
                                            ? 0
                                            : 1;
                                        int bIsMe =
                                            b['assignedTo'] == widget.user.uid
                                            ? 0
                                            : 1;
                                        return aIsMe.compareTo(bIsMe);
                                      });

                                      return Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple.shade50,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.deepPurple.shade100,
                                          ),
                                        ),
                                        child: Column(
                                          children: weekChores.map((chore) {
                                            final bool isMe =
                                                chore['assignedTo'] ==
                                                widget.user.uid;
                                            final bool isShared =
                                                chore['assignedTo'] == 'shared';

                                            // Uses local state for instant UI updates!
                                            final bool isDone =
                                                completedChores.contains(
                                                  chore['id'],
                                                ) ||
                                                _locallyCompletedChores
                                                    .contains(chore['id']);

                                            String assigneeText = "Partner";
                                            if (isMe) assigneeText = "YOU";
                                            if (isShared)
                                              assigneeText = "Shared";

                                            return CheckboxListTile(
                                              dense: true,
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              activeColor:
                                                  Colors.deepPurple.shade400,
                                              value: isDone,
                                              // Undo Grace Period Logic!
                                              onChanged: (val) {
                                                if (val == true) {
                                                  setState(
                                                    () =>
                                                        _locallyCompletedChores
                                                            .add(chore['id']),
                                                  );
                                                  _choreWeekIds[chore['id']] =
                                                      weekId;
                                                  _choreCompletionTimers[chore['id']] =
                                                      Timer(
                                                        const Duration(
                                                          seconds: 10,
                                                        ),
                                                        () {
                                                          _toggleWeeklyChore(
                                                            activeHubId,
                                                            chore['id'],
                                                            true,
                                                            weekId,
                                                          );
                                                          _choreCompletionTimers
                                                              .remove(
                                                                chore['id'],
                                                              );
                                                          _choreWeekIds.remove(
                                                            chore['id'],
                                                          );
                                                          if (mounted)
                                                            setState(
                                                              () => _locallyCompletedChores
                                                                  .remove(
                                                                    chore['id'],
                                                                  ),
                                                            );
                                                        },
                                                      );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).clearSnackBars();
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: const Text(
                                                        'Chore completed',
                                                      ),
                                                      duration: const Duration(
                                                        seconds: 8,
                                                      ),
                                                      action: SnackBarAction(
                                                        label: 'UNDO',
                                                        textColor: Colors
                                                            .deepPurpleAccent,
                                                        onPressed: () {
                                                          _choreCompletionTimers[chore['id']]
                                                              ?.cancel();
                                                          _choreCompletionTimers
                                                              .remove(
                                                                chore['id'],
                                                              );
                                                          _choreWeekIds.remove(
                                                            chore['id'],
                                                          );
                                                          setState(
                                                            () => _locallyCompletedChores
                                                                .remove(
                                                                  chore['id'],
                                                                ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                } else {
                                                  _choreCompletionTimers[chore['id']]
                                                      ?.cancel();
                                                  _choreCompletionTimers.remove(
                                                    chore['id'],
                                                  );
                                                  _choreWeekIds.remove(
                                                    chore['id'],
                                                  );
                                                  setState(
                                                    () =>
                                                        _locallyCompletedChores
                                                            .remove(
                                                              chore['id'],
                                                            ),
                                                  );
                                                  _toggleWeeklyChore(
                                                    activeHubId,
                                                    chore['id'],
                                                    false,
                                                    weekId,
                                                  );
                                                }
                                              },
                                              title: Text(
                                                chore['title'],
                                                style: TextStyle(
                                                  fontWeight: isMe
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isDone
                                                      ? Colors.grey
                                                      : (isMe
                                                            ? Colors.black87
                                                            : Colors
                                                                  .grey
                                                                  .shade600),
                                                  decoration: isDone
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                ),
                                              ),
                                              subtitle: Text(
                                                "${chore['effortMinutes']} mins",
                                                style: TextStyle(
                                                  color: isDone
                                                      ? Colors.grey
                                                      : (isMe
                                                            ? Colors
                                                                  .deepPurple
                                                                  .shade300
                                                            : Colors
                                                                  .grey
                                                                  .shade400),
                                                ),
                                              ),
                                              secondary: isMe
                                                  // Dims the "YOU" box if completed!
                                                  ? Chip(
                                                      label: const Text("YOU"),
                                                      backgroundColor: isDone
                                                          ? Colors
                                                                .deepPurple
                                                                .shade200
                                                          : Colors.deepPurple,
                                                      labelStyle:
                                                          const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                    )
                                                  : Text(
                                                      assigneeText,
                                                      style: TextStyle(
                                                        color: isShared
                                                            ? Colors.pinkAccent
                                                            : (isDone
                                                                  ? Colors
                                                                        .grey
                                                                        .shade300
                                                                  : Colors
                                                                        .grey
                                                                        .shade400),
                                                        fontSize: 12,
                                                        fontWeight: isShared
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
                                            );
                                          }).toList(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],

                              // --- 6. THE HORIZON ---
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 40),
                              ),
                              _buildSectionHeader(
                                'THE HORIZON',
                                icon: Icons.remove_red_eye_outlined,
                              ),

                              SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final day = todayStart.add(
                                    Duration(days: index + 1),
                                  );

                                  final dayEvents =
                                      myEvents
                                          .where(
                                            (d) => _eventOverlapsDay(d, day),
                                          )
                                          .toList()
                                        ..sort(
                                          (a, b) => (a['start'] as Timestamp)
                                              .compareTo(
                                                b['start'] as Timestamp,
                                              ),
                                        );

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildDateDivider(day),
                                        if (dayEvents.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.only(
                                              left: 8,
                                              bottom: 20,
                                            ),
                                            child: Text(
                                              'Nothing scheduled',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 14,
                                              ),
                                            ),
                                          )
                                        else ...[
                                          ...dayEvents.map(
                                            (e) => _buildSmallEventTile(e, day),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                      ],
                                    ),
                                  );
                                }, childCount: 7),
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

  Widget _buildHeroCard(Map<String, dynamic> d, DateTime day) {
    final bool isAllDay = d['allDay'] ?? false;
    final DateTime s = (d['start'] as Timestamp).toDate();
    final DateTime now = DateTime.now();

    final DateTime e = d['end'] != null ? (d['end'] as Timestamp).toDate() : s;
    bool isHappeningNow = false;
    if (isAllDay) {
      if (_eventOverlapsDay(d, now)) isHappeningNow = true;
    } else {
      if (s.isBefore(now) && e.isAfter(now)) isHappeningNow = true;
    }

    final String timeStr = isAllDay ? 'All Day' : DateFormat('HH:mm').format(s);
    final String badgeText = isHappeningNow ? 'HAPPENING NOW' : 'ON TODAY';

    final String category = d['category'] ?? 'general';
    final String assignedTo = d['assignedTo'] ?? 'shared';

    Color cardColor;
    if (category == 'work') {
      cardColor = Colors.blue.shade500;
    } else if (category == 'birthday') {
      cardColor = Colors.purple.shade400;
    } else if (assignedTo == 'shared') {
      cardColor = Colors.pink.shade500;
    } else {
      cardColor = Colors.grey.shade600;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cardColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badgeText,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            d['summary'] ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!isAllDay) ...[
            const SizedBox(height: 2),
            Text(
              timeStr,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmallEventTile(Map<String, dynamic> d, DateTime day) {
    final bool isAllDay = d['allDay'] ?? false;
    final DateTime s = (d['start'] as Timestamp).toDate();
    final String timeStr = isAllDay ? 'All Day' : DateFormat('HH:mm').format(s);

    final bool isMeal = d['category'] == 'meal';
    final String category = d['category'] ?? 'general';
    final String assignedTo = d['assignedTo'] ?? 'shared';

    Color cardColor;
    Color borderColor;
    Color iconColor;
    Color textColor;

    if (isMeal) {
      cardColor = Colors.green.shade500;
      borderColor = Colors.green.shade600;
      iconColor = Colors.white;
      textColor = Colors.white;
    } else if (category == 'work') {
      cardColor = Colors.blue.shade500;
      borderColor = Colors.blue.shade600;
      iconColor = Colors.white;
      textColor = Colors.white;
    } else if (category == 'birthday') {
      cardColor = Colors.purple.shade400;
      borderColor = Colors.purple.shade500;
      iconColor = Colors.white;
      textColor = Colors.white;
    } else if (assignedTo == 'shared') {
      cardColor = Colors.pink.shade500;
      borderColor = Colors.pink.shade600;
      iconColor = Colors.white;
      textColor = Colors.white;
    } else {
      cardColor = Colors.grey.shade600;
      borderColor = Colors.grey.shade700;
      iconColor = Colors.white;
      textColor = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              isMeal ? '' : timeStr,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  if (isMeal) ...[
                    Icon(Icons.restaurant, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                  ],
                  if (!isMeal && category == 'birthday') ...[
                    Icon(Icons.cake, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                  ],
                  if (!isMeal && category == 'work') ...[
                    Icon(Icons.work, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      d['summary'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime day) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Row(
        children: [
          Text(
            DateFormat('EEEE, d MMM').format(day).toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: Colors.grey.shade300)),
        ],
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

  Widget _buildCheckableTile(QueryDocumentSnapshot t) {
    return Builder(
      builder: (context) {
        final d = t.data() as Map<String, dynamic>;
        final bool isUrgent = d['isUrgent'] == true;
        final bool isShopping = d['listName'] == 'Shopping';
        final bool isVisuallyDone = _locallyCompleted.contains(t.id);

        Color bgColor;
        Color borderColor;
        Color tickColor;

        if (isUrgent && isShopping) {
          bgColor = Colors.green.shade50;
          borderColor = Colors.red.shade300;
          tickColor = Colors.red;
        } else if (isUrgent) {
          bgColor = Colors.red.shade50;
          borderColor = Colors.red.shade100;
          tickColor = Colors.red;
        } else if (isShopping) {
          bgColor = Colors.green.shade50;
          borderColor = Colors.green.shade300;
          tickColor = Colors.green.shade700;
        } else {
          bgColor = Colors.amber.shade50; // Amber task background
          borderColor = Colors.amber.shade200; // Amber border
          tickColor = Colors.amber.shade800; // Amber tick
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Checkbox(
                value: isVisuallyDone,
                activeColor: tickColor,
                checkColor: Colors.white,
                side: BorderSide(color: tickColor),
                onChanged: (v) {
                  if (v == true) {
                    setState(() => _locallyCompleted.add(t.id));
                    _completionTimers[t.id] = Timer(
                      const Duration(seconds: 10),
                      () {
                        t.reference.update({'isDone': true});
                        _completionTimers.remove(t.id);
                        if (mounted)
                          setState(() => _locallyCompleted.remove(t.id));
                      },
                    );
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
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
                  } else {
                    _completionTimers[t.id]?.cancel();
                    _completionTimers.remove(t.id);
                    setState(() => _locallyCompleted.remove(t.id));
                  }
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isUrgent) ...[
                          const Icon(
                            Icons.warning_rounded,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            d['text'] ?? '',
                            style: TextStyle(
                              fontWeight: isUrgent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isVisuallyDone
                                  ? Colors.grey
                                  : Colors.black87,
                              decoration: isVisuallyDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
