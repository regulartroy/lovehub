/// Pure logic for the Home feed: icons, columns, the hero "Now" card and
/// card ranking. No Firebase here so it is easy to test and to drive from
/// the gallery.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/dashboard/dashboard_calendar_overview.dart'
    show dashboardEventOverlapsDay, dashboardEventDateTime;

// ---------------------------------------------------------------------------
// Responsive columns
// ---------------------------------------------------------------------------

/// Card columns for the Home grid at [width] logical pixels.
/// Phone portrait gets 2, landscape/small tablet 3, big tablet 4.
int homeFeedColumns(double width) {
  if (width < 600) return 2;
  if (width < 1000) return 3;
  return 4;
}

// ---------------------------------------------------------------------------
// Keyword icons
// ---------------------------------------------------------------------------

typedef _Rule = (List<String> words, IconData icon);

IconData _match(String text, List<_Rule> rules, IconData fallback) {
  final t = ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} ';
  for (final (words, icon) in rules) {
    for (final w in words) {
      if (t.contains(' $w')) return icon;
    }
  }
  return fallback;
}

const List<_Rule> _choreRules = [
  (['bathroom', 'bath', 'shower', 'toilet', 'loo'], Icons.bathtub_rounded),
  (['hoover', 'vacuum', 'hover'], Icons.cleaning_services_rounded),
  (['dust'], Icons.auto_awesome_rounded),
  (['fridge', 'freezer', 'oven', 'kitchen', 'hob'], Icons.kitchen_rounded),
  (['bedding', 'bed ', 'bed', 'sheets', 'duvet'], Icons.bed_rounded),
  (['litter', 'cat', 'dog', 'enzo', 'pet', 'poo'], Icons.pets_rounded),
  (['water plant', 'plant', 'garden', 'flowers'], Icons.local_florist_rounded),
  (['lawn', 'mow', 'grass', 'weed'], Icons.grass_rounded),
  (['bin', 'rubbish', 'trash'], Icons.delete_rounded),
  (['recycl'], Icons.recycling_rounded),
  (['laundry', 'washing', 'wash clothes'], Icons.local_laundry_service_rounded),
  (['iron'], Icons.iron_rounded),
  (['dish', 'washing up', 'dishwasher'], Icons.wash_rounded),
  (['window', 'glass', 'mirror'], Icons.window_rounded),
  (['mop', 'floor'], Icons.water_drop_rounded),
  (['surface', 'worktop', 'counter', 'wipe'], Icons.countertops_rounded),
  (['tidy', 'declutter', 'wardrobe', 'clothes'], Icons.checkroom_rounded),
  (['microwave'], Icons.microwave_rounded),
];

/// Icon for a chore title, e.g. "Clean Bathroom" -> bathtub.
IconData choreIconFor(String title) =>
    _match(title, _choreRules, Icons.auto_awesome_outlined);

const List<_Rule> _taskRules = [
  (['vet', 'enzo', 'dog', 'cat', 'pet'], Icons.pets_rounded),
  (
    ['pay', 'bill', 'invoice', 'rent', 'tax', 'council', 'refund', 'bank'],
    Icons.currency_pound_rounded,
  ),
  (['call', 'phone', 'ring'], Icons.phone_rounded),
  (['book', 'appointment', 'reserve', 'schedule'], Icons.event_rounded),
  (['gift', 'present', 'birthday', 'card for'], Icons.card_giftcard_rounded),
  (['buy', 'order', 'pick up', 'collect', 'shop'], Icons.shopping_bag_rounded),
  (['fix', 'repair', 'mend', 'build', 'assemble', 'diy'], Icons.build_rounded),
  (['car', 'mot', 'tyre', 'petrol', 'insurance'], Icons.directions_car_rounded),
  (
    ['doctor', 'gp', 'dentist', 'prescription', 'pharmacy'],
    Icons.medical_services_rounded,
  ),
  (['post', 'parcel', 'return', 'send'], Icons.local_post_office_rounded),
  (['email', 'mail', 'reply'], Icons.mail_rounded),
  (['haircut', 'hair', 'barber'], Icons.content_cut_rounded),
  (['gym', 'run', 'workout'], Icons.fitness_center_rounded),
  (['clean', 'tidy', 'hoover'], Icons.cleaning_services_rounded),
  (['cook', 'dinner', 'recipe', 'meal'], Icons.restaurant_rounded),
];

/// Icon for a task, e.g. "Pay council tax" -> pound sign.
IconData taskIconFor(String text) =>
    _match(text, _taskRules, Icons.task_alt_rounded);

// ---------------------------------------------------------------------------
// Data model the feed renders
// ---------------------------------------------------------------------------

class FeedChore {
  const FeedChore({
    required this.id,
    required this.title,
    required this.assignedTo,
    this.minutes,
    this.done = false,
  });
  final String id;
  final String title;
  final String assignedTo;
  final int? minutes;
  final bool done;

  FeedChore copyWith({bool? done}) => FeedChore(
    id: id,
    title: title,
    assignedTo: assignedTo,
    minutes: minutes,
    done: done ?? this.done,
  );
}

class FeedTask {
  const FeedTask({
    required this.id,
    required this.text,
    this.listName = 'General',
    this.urgent = false,
    this.due,
    this.assignedTo = 'shared',
    this.done = false,
  });
  final String id;
  final String text;
  final String listName;
  final bool urgent;
  final DateTime? due;
  final String assignedTo;
  final bool done;

  bool get isShopping => listName == 'Shopping';
}

class FeedWeather {
  const FeedWeather({
    required this.city,
    this.tempNow,
    this.todayMax,
    this.todayMin,
    this.rainChance = 0,
    this.rainFrom,
  });
  final String city;
  final double? tempNow;
  final double? todayMax;
  final double? todayMin;

  /// Highest precipitation probability (%) in the next 12 hours.
  final int rainChance;

  /// First hour in the next 12 with >= 50% chance of rain.
  final DateTime? rainFrom;

  bool get rainLikely => rainChance >= 50;
  bool get notableTemp =>
      (todayMax != null && todayMax! >= 25) ||
      (todayMin != null && todayMin! <= 2);
  bool get isNotable => rainLikely || notableTemp;
}

class HomeFeedData {
  const HomeFeedData({
    required this.now,
    required this.myUid,
    this.names = const {},
    this.events = const [],
    this.chores = const [],
    this.tasks = const [],
    this.weather,
    this.quote,
    this.quoteAuthor,
  });

  final DateTime now;
  final String myUid;

  /// uid -> first name.
  final Map<String, String> names;

  /// Calendar event maps (start/end as DateTime or Timestamp), birthdays
  /// projected in with category 'birthday'.
  final List<Map<String, dynamic>> events;
  final List<FeedChore> chores;
  final List<FeedTask> tasks;
  final FeedWeather? weather;
  final String? quote;
  final String? quoteAuthor;

  String nameOf(String uid) =>
      uid == 'shared' ? 'Both of you' : (names[uid] ?? 'Partner');

  String? get partnerUid {
    for (final uid in names.keys) {
      if (uid != myUid) return uid;
    }
    return null;
  }

  List<FeedTask> get openTasks =>
      tasks.where((t) => !t.done && !t.isShopping).toList();
  List<FeedTask> get shopping =>
      tasks.where((t) => !t.done && t.isShopping).toList();
}

// ---------------------------------------------------------------------------
// Event helpers (overnight rule shared with the dashboard)
// ---------------------------------------------------------------------------

DateTime? feedStart(Map<String, dynamic> e) =>
    dashboardEventDateTime(e['start']);
DateTime feedEnd(Map<String, dynamic> e) =>
    dashboardEventDateTime(e['end']) ?? feedStart(e)!;
bool feedAllDay(Map<String, dynamic> e) => e['allDay'] == true;
bool feedTentative(Map<String, dynamic> e) => e['status'] == 'tentative';
String feedTitle(Map<String, dynamic> e) =>
    (e['summary'] ?? 'Event').toString();

/// Events that belong on [day]. Uses the same overnight rule as the
/// dashboard and Calendar views: a timed event ending before 06:00 the next
/// morning stays on its start day only.
List<Map<String, dynamic>> feedEventsOnDay(
  List<Map<String, dynamic>> events,
  DateTime day,
) {
  final list = events
      .where((e) => feedStart(e) != null && dashboardEventOverlapsDay(e, day))
      .toList();
  list.sort((a, b) {
    final ad = feedAllDay(a), bd = feedAllDay(b);
    if (ad != bd) return ad ? -1 : 1;
    return feedStart(a)!.compareTo(feedStart(b)!);
  });
  return list;
}

String feedTimeRange(Map<String, dynamic> e) {
  if (feedAllDay(e)) return 'All day';
  final s = feedStart(e)!;
  final en = feedEnd(e);
  final f = DateFormat('HH:mm');
  if (!en.isAfter(s)) return f.format(s);
  return '${f.format(s)}–${f.format(en)}';
}

/// "2h 15m", "45m", "1d 3h".
String feedCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
}

// ---------------------------------------------------------------------------
// The hero "Now" card
// ---------------------------------------------------------------------------

enum FeedMoment { morning, afternoon, evening, night }

FeedMoment feedMomentFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return FeedMoment.morning;
  if (h >= 12 && h < 17) return FeedMoment.afternoon;
  if (h >= 17 && h < 22) return FeedMoment.evening;
  return FeedMoment.night;
}

class HeroNow {
  const HeroNow({
    required this.moment,
    required this.eyebrow,
    required this.headline,
    this.countdown,
    this.lines = const [],
    this.focusEvent,
  });
  final FeedMoment moment;
  final String eyebrow;
  final String headline;
  final String? countdown;
  final List<String> lines;
  final Map<String, dynamic>? focusEvent;
}

bool _isMine(Map<String, dynamic> e, String uid) =>
    e['assignedTo'] == uid || e['assignedTo'] == 'shared';

/// A work event for [uid] that runs into this evening/tonight (skipping
/// [except], e.g. the one already shown as the hero focus).
Map<String, dynamic>? feedTonightShift(
  HomeFeedData d,
  String uid, {
  Map<String, dynamic>? except,
}) {
  final today = DateUtils.dateOnly(d.now);
  for (final e in feedEventsOnDay(d.events, today)) {
    if (e['category'] != 'work' || e['assignedTo'] != uid) continue;
    if (identical(e, except)) continue;
    if (feedAllDay(e)) continue;
    final s = feedStart(e)!;
    final en = feedEnd(e);
    if (en.isBefore(d.now)) continue;
    if (en.hour >= 18 || !DateUtils.isSameDay(en, s) || s.hour >= 15) {
      return e;
    }
  }
  return null;
}

/// "Free tonight" / "Busy 22:00–04:30" for [uid] from 17:00 today.
String feedTonightStatus(HomeFeedData d, String uid) {
  final today = DateUtils.dateOnly(d.now);
  final evening = DateTime(today.year, today.month, today.day, 17);
  final busy = feedEventsOnDay(d.events, today).where((e) {
    if (feedAllDay(e) ||
        e['category'] == 'birthday' ||
        e['category'] == 'meal') {
      return false;
    }
    if (e['assignedTo'] != uid && e['assignedTo'] != 'shared') return false;
    return feedEnd(e).isAfter(evening) && feedEnd(e).isAfter(d.now);
  }).toList();
  if (busy.isEmpty) return 'free tonight';
  return 'busy ${feedTimeRange(busy.first)}';
}

HeroNow buildHeroNow(HomeFeedData d) {
  final now = d.now;
  final moment = feedMomentFor(now);
  final today = DateUtils.dateOnly(now);
  final tomorrow = today.add(const Duration(days: 1));
  final mine = d.events.where((e) => _isMine(e, d.myUid)).toList();
  final todays = feedEventsOnDay(mine, today);
  final timedToday = todays.where((e) => !feedAllDay(e)).toList();

  // 1. Something on right now.
  final current = timedToday.where(
    (e) => !feedStart(e)!.isAfter(now) && feedEnd(e).isAfter(now),
  );
  // Overnight continuation from yesterday (e.g. a club shift at 01:00).
  final yesterday = today.subtract(const Duration(days: 1));
  final carried = feedEventsOnDay(mine, yesterday).where(
    (e) =>
        !feedAllDay(e) &&
        !feedStart(e)!.isAfter(now) &&
        feedEnd(e).isAfter(now),
  );
  final nowEvent = current.isNotEmpty
      ? current.first
      : (carried.isNotEmpty ? carried.first : null);

  // 2. The next timed event today/tonight.
  final upcoming =
      [
          ...timedToday,
          ...feedEventsOnDay(mine, tomorrow),
        ].where((e) => !feedAllDay(e) && feedStart(e)!.isAfter(now)).toList()
        ..sort((a, b) => feedStart(a)!.compareTo(feedStart(b)!));
  final next = upcoming.isEmpty ? null : upcoming.first;

  final lines = <String>[];
  final myChoresLeft = d.chores
      .where((c) => !c.done && c.assignedTo == d.myUid)
      .length;
  final overdue = d.openTasks
      .where((t) => t.due != null && DateUtils.dateOnly(t.due!).isBefore(today))
      .length;
  final dueToday = d.openTasks
      .where((t) => t.due != null && DateUtils.isSameDay(t.due!, today))
      .length;
  final partner = d.partnerUid;

  String eventLine(Map<String, dynamic> e) =>
      '${feedTimeRange(e)}  ${feedTitle(e)}${feedTentative(e) ? ' (?)' : ''}';

  String eyebrow;
  String headline;
  String? countdown;
  Map<String, dynamic>? focus;

  if (nowEvent != null) {
    eyebrow = 'HAPPENING NOW';
    headline = feedTitle(nowEvent);
    countdown = 'ends in ${feedCountdown(feedEnd(nowEvent).difference(now))}';
    focus = nowEvent;
  } else if (next != null &&
      feedStart(next)!.difference(now) <= const Duration(hours: 3)) {
    eyebrow = 'UP NEXT';
    headline = feedTitle(next);
    countdown = 'in ${feedCountdown(feedStart(next)!.difference(now))}';
    focus = next;
  } else {
    switch (moment) {
      case FeedMoment.morning:
        eyebrow = 'GOOD MORNING';
        headline = todays.isEmpty
            ? 'A clear day ahead'
            : '${todays.length} thing${todays.length == 1 ? '' : 's'} on today';
      case FeedMoment.afternoon:
        eyebrow = 'THIS AFTERNOON';
        headline = next != null && DateUtils.isSameDay(feedStart(next), today)
            ? 'Next: ${feedTitle(next)}'
            : 'Rest of today is free';
        if (next != null && DateUtils.isSameDay(feedStart(next), today)) {
          countdown = 'in ${feedCountdown(feedStart(next)!.difference(now))}';
          focus = next;
        }
      case FeedMoment.evening:
        eyebrow = 'THIS EVENING';
        headline = 'Tonight & tomorrow';
      case FeedMoment.night:
        eyebrow = 'LATE NIGHT';
        headline = 'Tomorrow at a glance';
    }
  }

  switch (moment) {
    case FeedMoment.morning:
    case FeedMoment.afternoon:
      final ahead = todays.where(
        (e) => e != focus && (feedAllDay(e) || feedEnd(e).isAfter(now)),
      );
      for (final e in ahead.take(3)) {
        lines.add(eventLine(e));
      }
      if (myChoresLeft > 0) {
        lines.add(
          '$myChoresLeft chore${myChoresLeft == 1 ? '' : 's'} left for you this week',
        );
      }
      if (dueToday > 0) {
        lines.add('$dueToday task${dueToday == 1 ? '' : 's'} due today');
      }
    case FeedMoment.evening:
    case FeedMoment.night:
      final shift = feedTonightShift(d, d.myUid, except: focus);
      if (shift != null) {
        lines.add(
          'You work tonight ${feedTimeRange(shift)} · ${feedTitle(shift)}'
          '${feedTentative(shift) ? ' (?)' : ''}',
        );
      }
      if (partner != null && moment == FeedMoment.evening) {
        lines.add('${d.nameOf(partner)} is ${feedTonightStatus(d, partner)}');
      }
      final tmr = feedEventsOnDay(mine, tomorrow);
      if (tmr.isEmpty) {
        lines.add('Tomorrow: nothing planned');
      } else {
        lines.add(
          'Tomorrow: ${tmr.take(2).map(eventLine).join(' · ')}'
          '${tmr.length > 2 ? ' +${tmr.length - 2}' : ''}',
        );
      }
  }
  if (overdue > 0) {
    lines.add('$overdue overdue task${overdue == 1 ? '' : 's'}');
  }
  if (d.weather?.rainLikely == true &&
      (moment == FeedMoment.morning || moment == FeedMoment.afternoon)) {
    final from = d.weather!.rainFrom;
    lines.add(
      'Rain likely${from != null ? ' from ${DateFormat('HH:mm').format(from)}' : ''} '
      '(${d.weather!.rainChance}%)',
    );
  }

  return HeroNow(
    moment: moment,
    eyebrow: eyebrow,
    headline: headline,
    countdown: countdown,
    lines: lines,
    focusEvent: focus,
  );
}

// ---------------------------------------------------------------------------
// Card ranking
// ---------------------------------------------------------------------------

enum FeedCardKind {
  chores,
  tasks,
  birthdays,
  upcoming,
  dinner,
  shopping,
  weather,
  quote,
}

class FeedCardSpec {
  const FeedCardSpec(this.kind, this.score, {this.fullWidth = false});
  final FeedCardKind kind;
  final double score;
  final bool fullWidth;
  @override
  String toString() => '$kind(${score.toStringAsFixed(0)})';
}

/// Birthdays from today to 7 days ahead, soonest first.
List<(Map<String, dynamic>, int)> feedBirthdaysSoon(HomeFeedData d) {
  final today = DateUtils.dateOnly(d.now);
  final out = <(Map<String, dynamic>, int)>[];
  for (final e in d.events) {
    if (e['category'] != 'birthday') continue;
    final s = feedStart(e);
    if (s == null) continue;
    final days = DateUtils.dateOnly(s).difference(today).inDays;
    if (days >= 0 && days <= 7) out.add((e, days));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// My/shared events from now to 48h ahead (not birthdays or meals).
List<Map<String, dynamic>> feedUpcoming48h(HomeFeedData d) {
  final limit = d.now.add(const Duration(hours: 48));
  final list = d.events.where((e) {
    if (!_isMine(e, d.myUid)) return false;
    if (e['category'] == 'birthday' || e['category'] == 'meal') return false;
    final s = feedStart(e);
    if (s == null) return false;
    if (feedAllDay(e)) {
      final day = DateUtils.dateOnly(s);
      return !day.isBefore(DateUtils.dateOnly(d.now)) && day.isBefore(limit);
    }
    return feedEnd(e).isAfter(d.now) && s.isBefore(limit);
  }).toList();
  list.sort((a, b) => feedStart(a)!.compareTo(feedStart(b)!));
  return list;
}

List<Map<String, dynamic>> feedMealsToday(HomeFeedData d) => feedEventsOnDay(
  d.events.where((e) => e['category'] == 'meal').toList(),
  d.now,
);

/// Tasks sorted overdue -> due today -> urgent -> due later -> rest.
List<FeedTask> feedRankedTasks(HomeFeedData d) {
  final today = DateUtils.dateOnly(d.now);
  int bucket(FeedTask t) {
    if (t.due != null) {
      final due = DateUtils.dateOnly(t.due!);
      if (due.isBefore(today)) return 0;
      if (due == today) return 1;
    }
    if (t.urgent) return 2;
    if (t.due != null) return 3;
    return 4;
  }

  final list = d.openTasks
      .where((t) => t.assignedTo == d.myUid || t.assignedTo == 'shared')
      .toList();
  list.sort((a, b) {
    final c = bucket(a).compareTo(bucket(b));
    if (c != 0) return c;
    if (a.due != null && b.due != null) return a.due!.compareTo(b.due!);
    return 0;
  });
  return list;
}

/// Which cards to show, most relevant first. Empty cards are left out.
List<FeedCardSpec> rankFeedCards(HomeFeedData d) {
  final today = DateUtils.dateOnly(d.now);
  final moment = feedMomentFor(d.now);
  final cards = <FeedCardSpec>[];

  // Chores: more pressing the more of mine are left and the later in the
  // week it is (rota weeks end on Sunday).
  if (d.chores.isNotEmpty) {
    final mineLeft = d.chores
        .where((c) => !c.done && c.assignedTo == d.myUid)
        .length;
    final allDone = d.chores.every((c) => c.done);
    final weekday = d.now.weekday; // Mon 1 .. Sun 7
    double score = allDone ? 20.0 : 45.0 + mineLeft * 4 + weekday * 3;
    if (moment == FeedMoment.morning && mineLeft > 0) score += 8;
    cards.add(FeedCardSpec(FeedCardKind.chores, score, fullWidth: true));
  }

  final tasks = feedRankedTasks(d);
  if (tasks.isNotEmpty) {
    final overdue = tasks.any(
      (t) => t.due != null && DateUtils.dateOnly(t.due!).isBefore(today),
    );
    final dueToday = tasks.any(
      (t) => t.due != null && DateUtils.isSameDay(t.due!, today),
    );
    final urgent = tasks.any((t) => t.urgent);
    cards.add(
      FeedCardSpec(
        FeedCardKind.tasks,
        overdue
            ? 95
            : dueToday
            ? 85
            : urgent
            ? 72
            : 40,
      ),
    );
  }

  final bdays = feedBirthdaysSoon(d);
  if (bdays.isNotEmpty) {
    cards.add(FeedCardSpec(FeedCardKind.birthdays, 98 - bdays.first.$2 * 8.0));
  }

  final upcoming = feedUpcoming48h(d);
  if (upcoming.isNotEmpty) {
    cards.add(FeedCardSpec(FeedCardKind.upcoming, 70, fullWidth: true));
  }

  final meals = feedMealsToday(d);
  if (meals.isNotEmpty) {
    cards.add(
      FeedCardSpec(
        FeedCardKind.dinner,
        moment == FeedMoment.afternoon || moment == FeedMoment.evening
            ? 68
            : 42,
      ),
    );
  }

  final shop = d.shopping.length;
  if (shop > 0) {
    cards.add(
      FeedCardSpec(FeedCardKind.shopping, 30.0 + shop.clamp(0, 20).toDouble()),
    );
  }

  final w = d.weather;
  if (w != null && w.isNotable) {
    cards.add(FeedCardSpec(FeedCardKind.weather, w.rainLikely ? 80 : 55));
  }

  if ((d.quote ?? '').trim().isNotEmpty) {
    cards.add(const FeedCardSpec(FeedCardKind.quote, 10));
  }

  cards.sort((a, b) => b.score.compareTo(a.score));
  return cards;
}

/// Due chip label: "Overdue 2d", "Today", "Tomorrow", "Mon 20".
String feedDueLabel(DateTime due, DateTime now) {
  final days = DateUtils.dateOnly(
    due,
  ).difference(DateUtils.dateOnly(now)).inDays;
  if (days < 0) return days == -1 ? 'Overdue 1d' : 'Overdue ${-days}d';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 7) return DateFormat('EEE d').format(due);
  return DateFormat('d MMM').format(due);
}

/// Header greeting from the same clock as the Now card:
/// 05–12 morning, 12–17 afternoon, 17–22 evening, otherwise "Still up?".
String feedGreeting(DateTime now, [String? firstName]) {
  final name = (firstName ?? '').trim();
  switch (feedMomentFor(now)) {
    case FeedMoment.morning:
      return name.isEmpty ? 'Good morning' : 'Good morning, $name';
    case FeedMoment.afternoon:
      return name.isEmpty ? 'Good afternoon' : 'Good afternoon, $name';
    case FeedMoment.evening:
      return name.isEmpty ? 'Good evening' : 'Good evening, $name';
    case FeedMoment.night:
      return name.isEmpty ? 'Still up?' : 'Still up, $name?';
  }
}
