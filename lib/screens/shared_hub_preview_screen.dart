import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/quote_model.dart';
import '../services/event_sanity.dart';
import '../services/member_profile.dart';
import '../widgets/dashboard/dashboard_calendar_overview.dart';
import '../widgets/dashboard/dashboard_theme.dart';
import '../widgets/hub_memory_image.dart';
import '../widgets/member_avatar.dart';
import '../widgets/recipe_picture.dart';
import '../services/hub_collection.dart';

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
  late final TabController _tabs = TabController(length: 7, vsync: this);

  List<_SharedHubInfo> _hubs = [];
  String? _selectedId;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _quotes = [];
  List<Map<String, dynamic>> _recipes = [];
  List<Map<String, dynamic>> _birthdays = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _photos = [];

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
          .collection(kHubsCollection)
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
      if (_selectedId != null) await _loadHubData(_selectedId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the new hub data: $e';
      });
    }
  }

  Future<void> _loadHubData(String hubId) async {
    final hub = _db.collection(kHubsCollection).doc(hubId);
    final results = await Future.wait([
      hub.collection('events').orderBy('start').get(),
      hub.collection('quotes').get(),
      hub.collection('recipes').get(),
      hub.collection('birthdays').get(),
      hub.collection('expenses').get(),
      hub.collection('photos').get(),
    ]);
    List<Map<String, dynamic>> maps(QuerySnapshot<Map<String, dynamic>> snap) {
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }

    final events = sanitizeEventMaps(maps(results[0]));
    final quotes = maps(results[1]);
    final recipes = maps(results[2]);
    final birthdays = maps(results[3]);
    final expenses = maps(results[4]);
    final photos = maps(results[5]);
    if (!mounted) return;
    setState(() {
      _events = events;
      _quotes = quotes;
      _recipes = recipes;
      _birthdays = birthdays;
      _expenses = expenses;
      _photos = photos;
    });
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
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'LOOK AHEAD'),
                  Tab(text: 'Events'),
                  Tab(text: 'Quotes'),
                  Tab(text: 'Recipes'),
                  Tab(text: 'Birthdays'),
                  Tab(text: 'Expenses'),
                  Tab(text: 'Photos'),
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
                  await _loadHubData(hub.id);
                },
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HubHeader(
          hub: _selected!,
          eventCount: _events.length,
          quoteCount: _quotes.length,
          recipeCount: _recipes.length,
          birthdayCount: _birthdays.length,
          expenseCount: _expenses.length,
          photoCount: _photos.length,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LookAheadPane(events: _events, members: _selected!.memberMaps),
              _EventsList(events: _events),
              _QuotesList(quotes: _quotes),
              _RecipesList(recipes: _recipes),
              _BirthdaysList(birthdays: _birthdays),
              _ExpensesList(expenses: _expenses, nameFor: _selected!.nameFor),
              _PhotosGrid(photos: _photos),
            ],
          ),
        ),
      ],
    );
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({
    required this.hub,
    required this.eventCount,
    required this.quoteCount,
    required this.recipeCount,
    required this.birthdayCount,
    required this.expenseCount,
    required this.photoCount,
  });

  final _SharedHubInfo hub;
  final int eventCount;
  final int quoteCount;
  final int recipeCount;
  final int birthdayCount;
  final int expenseCount;
  final int photoCount;

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
            '$eventCount events, $quoteCount quotes, $recipeCount recipes, '
            '$birthdayCount birthdays, $expenseCount expenses, $photoCount '
            'photos from the new database.',
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

class _QuotesList extends StatelessWidget {
  const _QuotesList({required this.quotes});

  final List<Map<String, dynamic>> quotes;

  @override
  Widget build(BuildContext context) {
    final models = sortQuotesNewestFirst(
      quotes.map((q) => QuoteModel.fromMap(q, id: q['id'] as String? ?? '')),
    );
    if (models.isEmpty) {
      return const Center(child: Text('No quotes in the new copy.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: models.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final quote = models[index];
        return Card(
          elevation: 0,
          color: Colors.pink.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“${quote.text}”',
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '— ${quote.author}',
                  style: TextStyle(
                    color: Colors.pink.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecipesList extends StatelessWidget {
  const _RecipesList({required this.recipes});

  final List<Map<String, dynamic>> recipes;

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return const Center(child: Text('No recipes in the new copy.'));
    }
    final sorted = [...recipes]
      ..sort((a, b) {
        final at = ((a['title'] as String?) ?? '').toLowerCase();
        final bt = ((b['title'] as String?) ?? '').toLowerCase();
        return at.compareTo(bt);
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final recipe = sorted[index];
        final title = ((recipe['title'] as String?) ?? '').trim().isNotEmpty
            ? (recipe['title'] as String).trim()
            : 'Recipe';
        final ingredients = _stringList(recipe['ingredients']);
        final imageUrl = (recipe['imageUrl'] as String?)?.trim();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showRecipe(context, recipe),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: RecipeImage(imageUrl: imageUrl, iconSize: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ingredients.isEmpty
                              ? 'No ingredients listed'
                              : ingredients.take(4).join(', ') +
                                    (ingredients.length > 4 ? '…' : ''),
                          style: const TextStyle(
                            color: Colors.black54,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRecipe(BuildContext context, Map<String, dynamic> recipe) {
    final title = ((recipe['title'] as String?) ?? '').trim().isNotEmpty
        ? (recipe['title'] as String).trim()
        : 'Recipe';
    final ingredients = _stringList(recipe['ingredients']);
    final method = ((recipe['method'] as String?) ?? '').trim();
    final sourceUrl = ((recipe['sourceUrl'] as String?) ?? '').trim();
    final imageUrl = (recipe['imageUrl'] as String?)?.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: RecipeImage(imageUrl: imageUrl, iconSize: 48),
                      ),
                    ),
                  ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sourceUrl.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    sourceUrl,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Ingredients',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (ingredients.isEmpty)
                  const Text('None listed.')
                else
                  for (final item in ingredients)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item'),
                    ),
                if (method.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Method',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(method, style: const TextStyle(height: 1.4)),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _BirthdaysList extends StatelessWidget {
  const _BirthdaysList({required this.birthdays});

  final List<Map<String, dynamic>> birthdays;

  @override
  Widget build(BuildContext context) {
    if (birthdays.isEmpty) {
      return const Center(child: Text('No birthdays in the new copy.'));
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = [...birthdays]
      ..sort((a, b) {
        return _nextBirthday(a, today).compareTo(_nextBirthday(b, today));
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = items[index];
        final name = ((row['name'] as String?) ?? '').trim().isNotEmpty
            ? (row['name'] as String).trim()
            : 'Birthday';
        final next = _nextBirthday(row, today);
        final year = _asInt(row['year']);
        final turning = year == null ? null : next.year - year;
        final when = DateFormat('EEE d MMMM').format(next);
        final subtitle = [
          when,
          if (turning != null && turning > 0) 'turns $turning',
        ].join(' · ');
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Colors.purple.shade50,
            foregroundColor: Colors.purple.shade700,
            child: const Icon(Icons.cake_outlined),
          ),
          title: Text(name),
          subtitle: Text(subtitle),
        );
      },
    );
  }
}

class _ExpensesList extends StatelessWidget {
  const _ExpensesList({required this.expenses, required this.nameFor});

  final List<Map<String, dynamic>> expenses;
  final String Function(String uid) nameFor;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return const Center(child: Text('No expenses in the new copy.'));
    }
    final sorted = [...expenses]
      ..sort((a, b) {
        final ad = _asDate(a['date']);
        final bd = _asDate(b['date']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = sorted[index];
        final description =
            ((row['description'] as String?) ?? '').trim().isNotEmpty
            ? (row['description'] as String).trim()
            : 'Expense';
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        final paidBy = nameFor((row['paidBy'] as String?) ?? '');
        final date = _asDate(row['date']);
        final dateLabel = date == null
            ? ''
            : DateFormat('d MMM y').format(date);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(description),
          subtitle: Text(
            [
              if (dateLabel.isNotEmpty) dateLabel,
              if (paidBy.isNotEmpty) 'Paid by $paidBy',
            ].join(' · '),
          ),
          trailing: Text(
            '£${amount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        );
      },
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.photos});

  final List<Map<String, dynamic>> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Center(child: Text('No photos in the new copy.'));
    }
    final sorted = [...photos]
      ..sort((a, b) {
        final ad = _asDate(a['createdAt']);
        final bd = _asDate(b['createdAt']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final row = sorted[index];
        final url = ((row['url'] as String?) ?? '').trim();
        final id = (row['id'] as String?) ?? '$index';
        if (url.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.broken_image, color: Colors.grey),
          );
        }
        return GestureDetector(
          onTap: () => _openPhoto(context, url, id),
          child: Hero(
            tag: 'preview-photo-$id',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: HubMemoryImage(
                url: url,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.photo, color: Colors.grey),
                    ),
                  );
                },
                errorBuilder: (ctx, error, stack) {
                  return Container(
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPhoto(BuildContext context, String url, String id) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Scaffold(
            backgroundColor: Colors.black.withValues(alpha: 0.92),
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: 'preview-photo-$id',
                      child: HubMemoryImage(url: url, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  String nameFor(String uid) {
    if (uid.isEmpty) return '';
    final profile = memberProfiles[uid];
    if (profile is Map) {
      final n = (profile['displayName'] as String?)?.trim() ?? '';
      if (n.isNotEmpty) return n;
    }
    return 'Member';
  }

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

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

int? _monthDay(Map<String, dynamic> row, String key) {
  final n = _asInt(row[key]);
  return n;
}

DateTime _nextBirthday(Map<String, dynamic> row, DateTime today) {
  final month = _monthDay(row, 'month') ?? 1;
  final day = _monthDay(row, 'day') ?? 1;
  var next = DateTime(today.year, month, day);
  if (next.isBefore(today)) {
    next = DateTime(today.year + 1, month, day);
  }
  return next;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
}
