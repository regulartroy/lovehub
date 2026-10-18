import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/home_feed_logic.dart';
import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';

/// Bottom-tab indices the feed cards open (see main.dart TabBar).
class HomeFeedTabs {
  static const calendar = 1;
  static const tasks = 2;
  static const food = 3;
  static const rota = 4;
}

typedef ChoreToggle = void Function(FeedChore chore, bool done);

/// The adaptive Home feed: a hero "Now" card and a responsive grid of
/// ranked cards. Pure presentation; the screen supplies [data].
class HomeFeedView extends StatelessWidget {
  const HomeFeedView({
    super.key,
    required this.data,
    required this.palette,
    this.onOpenTab,
    this.onToggleChore,
    this.onCompleteTask,
    this.onPrepMeal,
  });

  final HomeFeedData data;
  final HubMemberPalette palette;
  final ValueChanged<int>? onOpenTab;
  final ChoreToggle? onToggleChore;
  final ValueChanged<FeedTask>? onCompleteTask;
  final ValueChanged<Map<String, dynamic>>? onPrepMeal;

  static const heroKey = ValueKey('home-feed-hero');
  static ValueKey<String> cardKey(FeedCardKind k) =>
      ValueKey('home-feed-card-${k.name}');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = homeFeedColumns(width);
        final hero = buildHeroNow(data);
        final specs = rankFeedCards(data);
        final items = <FeedGridItem>[
          FeedGridItem(
            fullWidth: true,
            weight: 3,
            child: _HeroCard(
              key: heroKey,
              hero: hero,
              palette: palette,
              onTap: () => onOpenTab?.call(HomeFeedTabs.calendar),
            ),
          ),
          for (final s in specs)
            FeedGridItem(
              fullWidth: s.fullWidth,
              weight: _weightOf(s.kind),
              child: KeyedSubtree(
                key: cardKey(s.kind),
                child: _card(context, s.kind, columns),
              ),
            ),
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FeedMasonryGrid(columns: columns, spacing: 10, items: items),
        );
      },
    );
  }

  double _weightOf(FeedCardKind k) => switch (k) {
    FeedCardKind.tasks => 3,
    FeedCardKind.birthdays => 1.6,
    FeedCardKind.shopping => 1.6,
    FeedCardKind.dinner => 1.4,
    FeedCardKind.weather => 1.2,
    FeedCardKind.quote => 1.4,
    _ => 2,
  };

  Widget _card(BuildContext context, FeedCardKind kind, int columns) {
    switch (kind) {
      case FeedCardKind.chores:
        return ChoresCard(
          chores: data.chores,
          myUid: data.myUid,
          palette: palette,
          columns: columns,
          names: data.names,
          onToggle: onToggleChore,
          onOpen: () => onOpenTab?.call(HomeFeedTabs.rota),
        );
      case FeedCardKind.tasks:
        return TasksCard(
          tasks: feedRankedTasks(data),
          now: data.now,
          onComplete: onCompleteTask,
          onOpen: () => onOpenTab?.call(HomeFeedTabs.tasks),
        );
      case FeedCardKind.birthdays:
        return _BirthdaysCard(
          birthdays: feedBirthdaysSoon(data),
          onOpen: () => onOpenTab?.call(HomeFeedTabs.calendar),
        );
      case FeedCardKind.upcoming:
        return _UpcomingCard(
          events: feedUpcoming48h(data),
          now: data.now,
          palette: palette,
          onOpen: () => onOpenTab?.call(HomeFeedTabs.calendar),
        );
      case FeedCardKind.dinner:
        return _DinnerCard(
          meals: feedMealsToday(data),
          onPrep: onPrepMeal,
          onOpen: () => onOpenTab?.call(HomeFeedTabs.food),
        );
      case FeedCardKind.shopping:
        return _ShoppingCard(
          items: data.shopping,
          onOpen: () => onOpenTab?.call(HomeFeedTabs.tasks),
        );
      case FeedCardKind.weather:
        return _WeatherCard(weather: data.weather!);
      case FeedCardKind.quote:
        return _QuoteCard(text: data.quote!, author: data.quoteAuthor);
    }
  }
}

// ---------------------------------------------------------------------------
// Masonry grid with full-width spans
// ---------------------------------------------------------------------------

class FeedGridItem {
  const FeedGridItem({
    required this.child,
    this.fullWidth = false,
    this.weight = 1,
  });
  final Widget child;
  final bool fullWidth;

  /// Rough height estimate used to balance columns.
  final double weight;
}

/// Lays [items] out in [columns] columns. Full-width items take a row of
/// their own; runs of normal items between them are balanced masonry-style
/// into the shortest column. With one column everything stacks.
class FeedMasonryGrid extends StatelessWidget {
  const FeedMasonryGrid({
    super.key,
    required this.columns,
    required this.items,
    this.spacing = 10,
  });

  final int columns;
  final List<FeedGridItem> items;
  final double spacing;

  /// Splits [weights] into [columns] buckets (indices), shortest-first.
  static List<List<int>> distribute(List<double> weights, int columns) {
    final buckets = List.generate(columns, (_) => <int>[]);
    final heights = List<double>.filled(columns, 0);
    for (var i = 0; i < weights.length; i++) {
      var best = 0;
      for (var c = 1; c < columns; c++) {
        if (heights[c] < heights[best] - 0.01) best = c;
      }
      buckets[best].add(i);
      heights[best] += weights[i];
    }
    return buckets;
  }

  /// Keeps rank order, but pulls a later half-width card forward when a
  /// full-width card would otherwise leave a gap in the row above it.
  static List<T> packOrder<T>(
    List<T> items,
    bool Function(T) isFull,
    int columns,
  ) {
    final rest = [...items];
    final out = <T>[];
    var runLen = 0;
    while (rest.isNotEmpty) {
      final next = rest.first;
      if (isFull(next) && runLen % columns != 0 && columns > 1) {
        final i = rest.indexWhere((x) => !isFull(x));
        if (i > 0) {
          out.add(rest.removeAt(i));
          runLen++;
          continue;
        }
      }
      rest.removeAt(0);
      out.add(next);
      runLen = isFull(next) ? 0 : runLen + 1;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var run = <FeedGridItem>[];

    void flush() {
      if (run.isEmpty) return;
      final cols = math.max(1, math.min(columns, run.length));
      final buckets = distribute([for (final r in run) r.weight], columns);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: Column(
                  children: [
                    for (final i in buckets[c]) ...[
                      run[i].child,
                      SizedBox(height: spacing),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
      assert(cols >= 1);
      run = [];
    }

    for (final item in packOrder(items, (i) => i.fullWidth, columns)) {
      if (item.fullWidth || columns == 1) {
        flush();
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: item.child,
          ),
        );
      } else {
        run.add(item);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card shell
// ---------------------------------------------------------------------------

class FeedCardShell extends StatelessWidget {
  const FeedCardShell({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.onOpen,
    this.trailing,
    this.background,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onOpen;
  final Widget? trailing;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          background ??
          Color.alphaBlend(color.withValues(alpha: 0.06), Colors.white),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  ?trailing,
                  if (onOpen != null && trailing == null)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: color.withValues(alpha: 0.6),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    super.key,
    required this.hero,
    required this.palette,
    this.onTap,
  });

  final HeroNow hero;
  final HubMemberPalette palette;
  final VoidCallback? onTap;

  static List<Color> gradientFor(FeedMoment m) => switch (m) {
    FeedMoment.morning => const [Color(0xFFFFB37B), Color(0xFFF06292)],
    FeedMoment.afternoon => const [Color(0xFF4FC3F7), Color(0xFF5C6BC0)],
    FeedMoment.evening => const [Color(0xFF7E57C2), Color(0xFF283593)],
    FeedMoment.night => const [Color(0xFF263238), Color(0xFF1A237E)],
  };

  static IconData iconFor(FeedMoment m) => switch (m) {
    FeedMoment.morning => Icons.wb_twilight_rounded,
    FeedMoment.afternoon => Icons.wb_sunny_rounded,
    FeedMoment.evening => Icons.nights_stay_rounded,
    FeedMoment.night => Icons.bedtime_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final focus = hero.focusEvent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientFor(hero.moment),
            ),
            boxShadow: [
              BoxShadow(
                color: gradientFor(hero.moment).last.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconFor(hero.moment), color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hero.eyebrow,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (hero.countdown != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          hero.countdown!,
                          key: const ValueKey('home-feed-hero-countdown'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  hero.headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                if (focus != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${feedTimeRange(focus)}${feedTentative(focus) ? '  ·  tentative' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
                if (hero.lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final l in hero.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chores
// ---------------------------------------------------------------------------

class ChoresCard extends StatelessWidget {
  const ChoresCard({
    super.key,
    required this.chores,
    required this.myUid,
    required this.palette,
    required this.columns,
    this.names = const {},
    this.onToggle,
    this.onOpen,
  });

  final List<FeedChore> chores;
  final String myUid;
  final HubMemberPalette palette;
  final int columns;
  final Map<String, String> names;
  final ChoreToggle? onToggle;
  final VoidCallback? onOpen;

  static ValueKey<String> tileKey(String id) => ValueKey('chore-tile-$id');
  static const ringKey = ValueKey('chores-progress-ring');

  /// Mine first, then shared, then partner's; done last.
  static List<FeedChore> order(List<FeedChore> chores, String myUid) {
    int who(FeedChore c) => c.assignedTo == myUid
        ? 0
        : c.assignedTo == 'shared'
        ? 1
        : 2;
    final list = [...chores];
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return who(a).compareTo(who(b));
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final done = chores.where((c) => c.done).length;
    final mine = chores.where((c) => c.assignedTo == myUid).toList();
    final mineDone = mine.where((c) => c.done).length;
    final accent = Colors.deepPurple.shade400;
    final tileCols = math.max(2, columns);
    final ordered = order(chores, myUid);
    return FeedCardShell(
      title: "THIS WEEK'S CHORES",
      icon: Icons.cleaning_services_rounded,
      color: accent,
      onOpen: onOpen,
      trailing: Text(
        '$done/${chores.length}',
        style: TextStyle(color: accent, fontWeight: FontWeight.w700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: TweenAnimationBuilder<double>(
                  key: ringKey,
                  tween: Tween(end: chores.isEmpty ? 0 : done / chores.length),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: v,
                        strokeWidth: 6,
                        strokeCap: StrokeCap.round,
                        backgroundColor: accent.withValues(alpha: 0.12),
                        color: accent,
                      ),
                      Center(
                        child: Text(
                          '${(v * 100).round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mine.isEmpty
                      ? 'Nothing on your list this week'
                      : mineDone == mine.length
                      ? 'All yours done. Nice one! 🎉'
                      : '${mine.length - mineDone} of yours left · '
                            '${mine.where((c) => !c.done).fold<int>(0, (a, c) => a + (c.minutes ?? 0))} mins',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final w = (c.maxWidth - gap * (tileCols - 1)) / tileCols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final chore in ordered)
                    SizedBox(
                      width: w,
                      child: ChoreTile(
                        key: tileKey(chore.id),
                        chore: chore,
                        isMine: chore.assignedTo == myUid,
                        color: palette.whoColor(chore.assignedTo),
                        ownerLabel: chore.assignedTo == myUid
                            ? 'You'
                            : chore.assignedTo == 'shared'
                            ? 'Shared'
                            : (names[chore.assignedTo] ?? 'Partner'),
                        onToggle: onToggle == null
                            ? null
                            : (v) => onToggle!(chore, v),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A chunky chore tile: icon, title, minutes, owner colour. Tap to
/// complete with a bounce and a check burst; tap again to undo.
class ChoreTile extends StatefulWidget {
  const ChoreTile({
    super.key,
    required this.chore,
    required this.isMine,
    required this.color,
    required this.ownerLabel,
    this.onToggle,
  });

  final FeedChore chore;
  final bool isMine;
  final Color color;
  final String ownerLabel;
  final ValueChanged<bool>? onToggle;

  static const burstKey = ValueKey('chore-burst');

  @override
  State<ChoreTile> createState() => _ChoreTileState();
}

class _ChoreTileState extends State<ChoreTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    final next = !widget.chore.done;
    if (next) _c.forward(from: 0);
    widget.onToggle?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final chore = widget.chore;
    final done = chore.done;
    final soft = !widget.isMine && widget.ownerLabel != 'Shared';
    final base = widget.color;
    final wash = Color.alphaBlend(
      base.withValues(alpha: done ? 0.06 : (soft ? 0.10 : 0.20)),
      Colors.white,
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // Bounce: 1 -> 0.92 -> 1.06 -> 1.
        final t = _c.value;
        final scale = t == 0
            ? 1.0
            : t < 0.25
            ? 1 - 0.08 * (t / 0.25)
            : t < 0.6
            ? 0.92 + 0.14 * ((t - 0.25) / 0.35)
            : 1.06 - 0.06 * ((t - 0.6) / 0.4);
        return Transform.scale(
          scale: scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child!,
              if (_c.isAnimating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: ChoreTile.burstKey,
                      painter: _BurstPainter(progress: t, color: base),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: Opacity(
        opacity: done ? 0.55 : (soft ? 0.75 : 1),
        child: Material(
          color: wash,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onToggle == null ? null : _tap,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: base.withValues(alpha: soft ? 0.25 : 0.55),
                  width: widget.isMine && !done ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: done
                              ? Colors.green.shade500
                              : base.withValues(alpha: soft ? 0.5 : 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          done
                              ? Icons.check_rounded
                              : choreIconFor(chore.title),
                          size: 19,
                          color: done
                              ? Colors.white
                              : CalendarColors.inkOn(base),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.ownerLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: soft
                              ? Colors.black38
                              : Color.lerp(base, Colors.black, 0.35),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chore.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: widget.isMine
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 13.5,
                      height: 1.2,
                      color: soft ? Colors.black54 : Colors.black87,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (chore.minutes != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${chore.minutes} mins',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(27, 27);
    final p = Curves.easeOut.transform(progress);
    final paint = Paint()
      ..color = Colors.green.shade400.withValues(alpha: (1 - p) * 0.9);
    final paint2 = Paint()..color = color.withValues(alpha: (1 - p) * 0.9);
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi * 2 / 10;
      final r = 10 + 34 * p;
      canvas.drawCircle(
        centre + Offset(math.cos(a), math.sin(a)) * r,
        3.2 * (1 - p) + 0.6,
        i.isEven ? paint : paint2,
      );
    }
    canvas.drawCircle(
      centre,
      18 + 22 * p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - p)
        ..color = Colors.green.withValues(alpha: (1 - p) * 0.6),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

class TasksCard extends StatelessWidget {
  const TasksCard({
    super.key,
    required this.tasks,
    required this.now,
    this.onComplete,
    this.onOpen,
    this.maxItems = 5,
  });

  final List<FeedTask> tasks;
  final DateTime now;
  final ValueChanged<FeedTask>? onComplete;
  final VoidCallback? onOpen;
  final int maxItems;

  static ValueKey<String> tileKey(String id) => ValueKey('task-tile-$id');

  @override
  Widget build(BuildContext context) {
    final shown = tasks.take(maxItems).toList();
    final accent = Colors.amber.shade800;
    return FeedCardShell(
      title: 'TASKS',
      icon: Icons.check_circle_outline,
      color: accent,
      onOpen: onOpen,
      child: Column(
        children: [
          for (final t in shown)
            TaskTile(
              key: tileKey(t.id),
              task: t,
              now: now,
              onComplete: onComplete == null ? null : () => onComplete!(t),
            ),
          if (tasks.length > shown.length)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '+${tasks.length - shown.length} more',
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.now,
    this.onComplete,
  });

  final FeedTask task;
  final DateTime now;
  final VoidCallback? onComplete;

  static const overdueKey = ValueKey('task-overdue');

  bool get overdue =>
      task.due != null &&
      DateUtils.dateOnly(task.due!).isBefore(DateUtils.dateOnly(now));

  @override
  Widget build(BuildContext context) {
    final red = Colors.red.shade400;
    final tone = overdue
        ? red
        : task.urgent
        ? Colors.deepOrange.shade400
        : Colors.amber.shade700;
    return Container(
      key: overdue ? overdueKey : null,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      decoration: BoxDecoration(
        color: overdue ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue ? red.withValues(alpha: 0.6) : Colors.black12,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onComplete,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                task.done ? Icons.check_rounded : taskIconFor(task.text),
                size: 17,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: task.urgent || overdue
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: task.done ? Colors.grey : Colors.black87,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task.due != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: overdue ? red : tone.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      feedDueLabel(task.due!, now),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: overdue ? Colors.white : tone,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small cards
// ---------------------------------------------------------------------------

class _BirthdaysCard extends StatelessWidget {
  const _BirthdaysCard({required this.birthdays, this.onOpen});
  final List<(Map<String, dynamic>, int)> birthdays;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    const color = CalendarColors.birthday;
    return FeedCardShell(
      title: 'BIRTHDAYS',
      icon: Icons.cake_rounded,
      color: color,
      onOpen: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (e, days) in birthdays.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: feedTitle(e),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    TextSpan(
                      text: days == 0
                          ? '  today! 🎂'
                          : days == 1
                          ? '  tomorrow'
                          : '  in $days days',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.events,
    required this.now,
    required this.palette,
    this.onOpen,
  });
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final HubMemberPalette palette;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(now);
    final groups = <DateTime, List<Map<String, dynamic>>>{};
    for (final e in events) {
      final s = feedStart(e)!;
      final day = DateUtils.dateOnly(s).isBefore(today)
          ? today
          : DateUtils.dateOnly(s);
      groups.putIfAbsent(day, () => []).add(e);
    }
    String label(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff == 0) return 'TODAY';
      if (diff == 1) return 'TOMORROW';
      return DateFormat('EEEE d MMM').format(d).toUpperCase();
    }

    return FeedCardShell(
      title: 'NEXT 48 HOURS',
      icon: Icons.event_rounded,
      color: Colors.blueGrey.shade600,
      onOpen: onOpen,
      child: LayoutBuilder(
        builder: (context, c) {
          final twoCol = c.maxWidth >= 640 && groups.length > 1;
          final blocks = [
            for (final entry in groups.entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 2),
                    child: Text(
                      label(entry.key),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.black45,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  for (final e in entry.value)
                    CalendarSplitPill(
                      style: CalendarColors.fromMap(e, palette: palette),
                      title: feedTitle(e),
                      subtitle: feedTimeRange(e),
                      leading: e['category'] == 'work'
                          ? Icon(
                              Icons.work,
                              size: 16,
                              color: CalendarColors.fromMap(
                                e,
                                palette: palette,
                              ).inkOnWho,
                            )
                          : null,
                      density: CalendarSplitPillDensity.regular,
                      margin: const EdgeInsets.only(bottom: 6),
                    ),
                ],
              ),
          ];
          if (!twoCol) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks,
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: blocks[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DinnerCard extends StatelessWidget {
  const _DinnerCard({required this.meals, this.onPrep, this.onOpen});
  final List<Map<String, dynamic>> meals;
  final ValueChanged<Map<String, dynamic>>? onPrep;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    const color = CalendarColors.meal;
    return FeedCardShell(
      title: "TODAY'S MENU",
      icon: Icons.restaurant_menu,
      color: color,
      onOpen: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      feedTitle(m),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (onPrep != null &&
                      m['ingredients'] is List &&
                      (m['ingredients'] as List).isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: color,
                      ),
                      onPressed: () => onPrep!(m),
                      child: const Text('Prep'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShoppingCard extends StatelessWidget {
  const _ShoppingCard({required this.items, this.onOpen});
  final List<FeedTask> items;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final color = Colors.green.shade700;
    return FeedCardShell(
      title: 'SHOPPING',
      icon: Icons.shopping_cart_rounded,
      color: color,
      onOpen: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${items.length}',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          Text(
            items.length == 1 ? 'item on the list' : 'items on the list',
            style: const TextStyle(color: Colors.black54, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            items.take(3).map((t) => t.text).join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});
  final FeedWeather weather;

  @override
  Widget build(BuildContext context) {
    final rain = weather.rainLikely;
    final hot = (weather.todayMax ?? 0) >= 25;
    final color = rain
        ? Colors.indigo.shade400
        : hot
        ? Colors.orange.shade700
        : Colors.lightBlue.shade700;
    final from = weather.rainFrom;
    return FeedCardShell(
      title: weather.city.toUpperCase(),
      icon: rain
          ? Icons.umbrella_rounded
          : hot
          ? Icons.wb_sunny_rounded
          : Icons.ac_unit_rounded,
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (weather.tempNow != null)
            Text(
              '${weather.tempNow!.round()}°',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            rain
                ? 'Rain likely${from != null ? ' from ${DateFormat('HH:mm').format(from)}' : ''} (${weather.rainChance}%). Take a coat!'
                : hot
                ? 'Warm one: up to ${weather.todayMax!.round()}°'
                : 'Cold: down to ${weather.todayMin!.round()}°',
            style: const TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.text, this.author});
  final String text;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final color = Colors.pink.shade400;
    return FeedCardShell(
      title: 'QUOTE',
      icon: Icons.format_quote_rounded,
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“$text”',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              height: 1.3,
              color: Colors.black87,
            ),
          ),
          if (author != null) ...[
            const SizedBox(height: 4),
            Text(
              '— $author',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
