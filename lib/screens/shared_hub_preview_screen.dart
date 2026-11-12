import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/event_sanity.dart';
import '../services/member_profile.dart';
import '../widgets/dashboard/dashboard_calendar_overview.dart';
import '../widgets/dashboard/dashboard_theme.dart';
import '../widgets/member_avatar.dart';

const String kSharedHubsCollection = 'sharedHubs';

/// Read-only preview of a hub reconstituted in the new `sharedHubs` collection.
class SharedHubPreviewScreen extends StatefulWidget {
  const SharedHubPreviewScreen({super.key, required this.user, this.firestore});

  final User user;
  final FirebaseFirestore? firestore;

  @override
  State<SharedHubPreviewScreen> createState() => _SharedHubPreviewScreenState();
}

class _SharedHubPreviewScreenState extends State<SharedHubPreviewScreen>
    with SingleTickerProviderStateMixin {
  late final FirebaseFirestore _db =
      widget.firestore ?? FirebaseFirestore.instance;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<_SharedHubInfo> _hubs = [];
  String? _selectedId;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

  @override
  void initState() {
    super.initState();
    _loadHubs();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadHubs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _db
          .collection(kSharedHubsCollection)
          .where('members', arrayContains: widget.user.uid)
          .get();
      final hubs =
          snap.docs.map((doc) {
            final data = doc.data();
            final members = ((data['members'] as List?) ?? [])
                .map((e) => e.toString())
                .toList();
            final profiles = Map<String, dynamic>.from(
              data['memberProfiles'] as Map? ?? const {},
            );
            final eventCount = data['eventCount'];
            return _SharedHubInfo(
              id: doc.id,
              name: (data['name'] as String?)?.trim().isNotEmpty == true
                  ? (data['name'] as String).trim()
                  : 'Shared hub',
              members: members,
              memberProfiles: profiles,
              eventCount: eventCount is int
                  ? eventCount
                  : int.tryParse('$eventCount'),
            );
          }).toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
      if (!mounted) return;
      setState(() {
        _hubs = hubs;
        _selectedId = hubs.length == 1 ? hubs.first.id : _selectedId;
        _loading = false;
      });
      if (_selectedId != null) await _loadEvents(_selectedId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the new hub data: $e';
      });
    }
  }

  Future<void> _loadEvents(String hubId) async {
    final snap = await _db
        .collection(kSharedHubsCollection)
        .doc(hubId)
        .collection('events')
        .orderBy('start')
        .get();
    final events = sanitizeEventMaps(
      snap.docs.map((d) => {'id': d.id, ...d.data()}),
    );
    if (!mounted) return;
    setState(() => _events = events);
  }

  _SharedHubInfo? get _selected {
    for (final hub in _hubs) {
      if (hub.id == _selectedId) return hub;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected?.name ?? 'New data hubs'),
        backgroundColor: Colors.pink.shade400,
        foregroundColor: Colors.white,
        bottom: _selected == null
            ? null
            : TabBar(
                controller: _tabs,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'LOOK AHEAD'),
                  Tab(text: 'Events'),
                ],
              ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_hubs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'There are no hubs in the new database for your account yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_selected == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('These hubs are pulled from the new sharedHubs data.'),
          ),
          for (final hub in _hubs)
            Card(
              child: ListTile(
                title: Text(hub.name),
                subtitle: Text(
                  hub.eventCount == null
                      ? '${hub.members.length} members'
                      : '${hub.eventCount} events',
                ),
                onTap: () async {
                  setState(() => _selectedId = hub.id);
                  await _loadEvents(hub.id);
                },
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HubHeader(hub: _selected!, eventCount: _events.length),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LookAheadPane(events: _events, members: _selected!.memberMaps),
              _EventsList(events: _events),
            ],
          ),
        ),
      ],
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.hub, required this.eventCount});

  final _SharedHubInfo hub;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final member in hub.memberMaps) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: MemberAvatar(
                    photoURL: member['photoURL'] as String?,
                    name: (member['displayName'] as String?) ?? 'Member',
                    radius: 18,
                    backgroundColor: Colors.pink.shade100,
                    foregroundColor: Colors.pink.shade800,
                    icon: isUsablePhotoUrl(member['photoURL'] as String?)
                        ? null
                        : Icons.person,
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  hub.memberMaps
                      .map((m) => (m['displayName'] as String?) ?? '')
                      .where((n) => n.isNotEmpty)
                      .join(' and '),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$eventCount events from the new database. '
            'Quotes, recipes, and photos were not copied across yet.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _LookAheadPane extends StatelessWidget {
  const _LookAheadPane({required this.events, required this.members});

  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return DashboardCalendarOverviewSlide(
          metrics: DashboardMetrics(
            Size(constraints.maxWidth, constraints.maxHeight),
          ),
          events: events,
          now: DateTime.now(),
          members: members,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          showHeader: false,
          infiniteForward: true,
          infiniteBackward: true,
        );
      },
    );
  }
}

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List<Map<String, dynamic>> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('No events in the new copy.'));
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = <Map<String, dynamic>>[];
    final past = <Map<String, dynamic>>[];
    for (final event in events) {
      final start = _startOf(event);
      if (start == null) continue;
      if (start.isBefore(today)) {
        past.add(event);
      } else {
        upcoming.add(event);
      }
    }
    past.sort((a, b) => _startOf(b)!.compareTo(_startOf(a)!));

    final children = <Widget>[];
    if (upcoming.isNotEmpty) {
      children.add(const _SectionLabel('Upcoming'));
      String? lastKey;
      for (final event in upcoming) {
        final key = DateFormat('EEE d MMM y').format(_startOf(event)!);
        if (key != lastKey) {
          children.add(_DayLabel(key));
          lastKey = key;
        }
        children.add(_EventTile(event: event));
      }
    }
    if (past.isNotEmpty) {
      children.add(const _SectionLabel('Past'));
      String? lastKey;
      for (final event in past) {
        final key = DateFormat('EEE d MMM y').format(_startOf(event)!);
        if (key != lastKey) {
          children.add(_DayLabel(key));
          lastKey = key;
        }
        children.add(_EventTile(event: event));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: children,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final start = _startOf(event);
    final end = _asDate(event['end']);
    final allDay = event['allDay'] == true;
    final summary = (event['summary'] as String?)?.trim().isNotEmpty == true
        ? (event['summary'] as String).trim()
        : 'Event';
    final category = (event['category'] as String?) ?? '';
    final time = allDay || start == null
        ? 'All day'
        : end != null
        ? '${DateFormat.Hm().format(start)}–${DateFormat.Hm().format(end)}'
        : DateFormat.Hm().format(start);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(summary),
      subtitle: Text([time, if (category.isNotEmpty) category].join(' · ')),
    );
  }
}

class _SharedHubInfo {
  const _SharedHubInfo({
    required this.id,
    required this.name,
    required this.members,
    required this.memberProfiles,
    this.eventCount,
  });

  final String id;
  final String name;
  final List<String> members;
  final Map<String, dynamic> memberProfiles;
  final int? eventCount;

  List<Map<String, dynamic>> get memberMaps {
    return members.map((uid) {
      final profile = memberProfiles[uid] is Map
          ? Map<String, dynamic>.from(memberProfiles[uid] as Map)
          : <String, dynamic>{};
      final name = (profile['displayName'] as String?) ?? '';
      return {
        'uid': uid,
        'name': name,
        'displayName': name,
        'photoURL': profile['photoURL'] ?? '',
      };
    }).toList();
  }
}

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

DateTime? _startOf(Map<String, dynamic> event) => _asDate(event['start']);
