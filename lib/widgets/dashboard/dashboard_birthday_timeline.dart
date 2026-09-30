import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../member_avatar.dart';
import 'dashboard_calendar_overview.dart' show dashboardEventDateTime;
import 'dashboard_chrome.dart';
import 'dashboard_theme.dart';

/// Birthday purple family for the glass-tile timeline.
class BirthdayTimelineColors {
  static const Color magenta = Color(0xFFE254FF);
  static const Color purple = Color(0xFF8B5BB5); // CalendarColors.birthday
  static const Color lilac = Color(0xFFD9B8FF);
  static const Color canvas = Color(0xFF030206);
}

/// One upcoming birthday on the dashboard timeline.
@immutable
class DashboardBirthday {
  const DashboardBirthday({
    required this.id,
    required this.name,
    required this.date,
    this.turning,
    this.photoUrl,
  });

  final String id;
  final String name;

  /// Date of the upcoming occurrence (date only, local).
  final DateTime date;

  /// Age they turn on [date], when the birth year is known.
  final int? turning;

  /// Hub member photo when the name matches a member.
  final String? photoUrl;

  /// Whole calendar days from [today] (DST-safe).
  int daysFrom(DateTime today) => _dayNumber(date) - _dayNumber(today);
}

int _dayNumber(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

final _ageSuffix = RegExp(r'^(.*?)\s*\((\d{1,3})\)\s*$');

/// Splits a projected birthday title like `Maria (35)` into name and age.
({String name, int? turning}) dashboardSplitBirthdayTitle(String summary) {
  final match = _ageSuffix.firstMatch(summary.trim());
  if (match == null) return (name: summary.trim(), turning: null);
  return (name: match.group(1)!.trim(), turning: int.tryParse(match.group(2)!));
}

String _firstToken(String s) =>
    s.trim().toLowerCase().split(RegExp(r'\s+')).first;

String? _memberPhotoFor(String name, List<Map<String, dynamic>> members) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return null;
  final first = _firstToken(name);
  final singleWord = !lower.contains(' ');
  for (final m in members) {
    final memberName = (m['name'] ?? m['displayName'] ?? '').toString().trim();
    final photo = (m['photoURL'] ?? '').toString().trim();
    if (memberName.isEmpty || photo.isEmpty) continue;
    final memberLower = memberName.toLowerCase();
    if (memberLower == lower ||
        ((singleWord || !memberLower.contains(' ')) &&
            _firstToken(memberName) == first)) {
      return photo;
    }
  }
  return null;
}

/// Upcoming birthdays from the dashboard event list (`category: birthday`,
/// including the projected hub birthdays), soonest first.
///
/// Keeps birthdays within [horizonDays], but always at least [minCount] if
/// there are that many in the next year, and never more than [maxCount].
List<DashboardBirthday> dashboardUpcomingBirthdays(
  List<Map<String, dynamic>> events, {
  required DateTime now,
  List<Map<String, dynamic>> members = const [],
  int maxCount = 8,
  int minCount = 3,
  int horizonDays = 92,
}) {
  final today = DateUtils.dateOnly(now);
  final seen = <String>{};
  final all = <DashboardBirthday>[];
  for (final e in events) {
    if ((e['category'] ?? '') != 'birthday') continue;
    final start = dashboardEventDateTime(e['start']);
    if (start == null) continue;
    final date = DateUtils.dateOnly(start);
    final b = DashboardBirthday(
      id: (e['id'] ?? '').toString(),
      name: '',
      date: date,
    );
    final days = b.daysFrom(today);
    if (days < 0 || days > 365) continue;
    final split = dashboardSplitBirthdayTitle((e['summary'] ?? '').toString());
    final name = (e['birthdayName'] ?? split.name).toString().trim();
    if (name.isEmpty) continue;
    final key = '${name.toLowerCase()}|${_dayNumber(date)}';
    if (!seen.add(key)) continue;
    final turningRaw = e['turning'];
    all.add(
      DashboardBirthday(
        id: b.id.isEmpty ? key : b.id,
        name: name,
        date: date,
        turning: turningRaw is int ? turningRaw : split.turning,
        photoUrl: _memberPhotoFor(name, members),
      ),
    );
  }
  all.sort((a, b) => a.date.compareTo(b.date));
  final within = all.where((b) => b.daysFrom(today) <= horizonDays).length;
  final count = math.min(
    maxCount,
    math.max(within, math.min(minCount, all.length)),
  );
  return all.take(count).toList();
}

/// Where one tile sits in the timeline, in slide-local pixels.
@immutable
class BirthdayTilePlacement {
  const BirthdayTilePlacement({
    required this.birthday,
    required this.center,
    required this.scale,
    required this.depth,
    required this.anchor,
  });

  final DashboardBirthday birthday;
  final Offset center;

  /// Multiplier on the base tile size (1 = front).
  final double scale;

  /// 0 = today / front, 1 = far end of the timeline.
  final double depth;

  /// True date position on the timeline line.
  final Offset anchor;
}

@immutable
class BirthdayTimelineTick {
  const BirthdayTimelineTick({
    required this.position,
    required this.depth,
    required this.scale,
    this.label,
    this.major = false,
  });

  final Offset position;
  final double depth;
  final double scale;
  final String? label;
  final bool major;
}

/// Pure geometry for [DashboardBirthdayTimeline]. Tested without widgets.
class BirthdayTimelineLayout {
  BirthdayTimelineLayout._({
    required this.size,
    required this.baseTile,
    required this.tickDays,
    required this.spanDays,
    required this.tiles,
    required this.ticks,
    required this.line,
  });

  final Size size;
  final double baseTile;

  /// Days between timeline ticks (7 or 14).
  final int tickDays;
  final int spanDays;

  /// Far to near, so painting in order puts the next birthday in front.
  final List<BirthdayTilePlacement> tiles;
  final List<BirthdayTimelineTick> ticks;
  final List<Offset> line;

  /// How far left of a tile's centre the timeline runs, as a share of the
  /// tile width.
  static const double kLineInset = 0.28;

  /// Perspective strength: the far end is drawn at 1 / (1 + k) scale.
  static const double k = 1.7;

  static double scaleAt(double t) => 1 / (1 + k * t);

  /// Screen progress along the curve. Near weeks spread out, far weeks bunch
  /// up, the way equal steps recede in perspective.
  static double curveAt(double t) => t * (1 + k) / (1 + k * t);

  factory BirthdayTimelineLayout.compute({
    required Size size,
    required List<DashboardBirthday> birthdays,
    required DateTime today,
    required bool compact,
  }) {
    final w = size.width;
    final h = size.height;
    final baseTile = compact
        ? math.min(w * 0.64, h * 0.46)
        : math.min(h * 0.46, w * 0.25);
    final lastDays = birthdays.isEmpty
        ? 28
        : math.max(28, birthdays.last.daysFrom(today));
    final tickDays = lastDays <= 63 ? 7 : 14;
    final spanDays =
        ((lastDays * 1.1 + tickDays / 2) / tickDays).ceil() * tickDays;

    // Tile-centre curve: front tile bottom-left, receding up and right,
    // bending upward toward the back.
    final farScale = scaleAt(1);
    final topReserve = compact ? 34.0 : 40.0;
    final p0 = Offset(baseTile / 2 + 2, h - baseTile / 2 - 4);
    final p2 = Offset(
      compact
          ? w - baseTile * farScale / 2 - 4
          : math.min(w * 0.86, w - baseTile * farScale / 2 - 16),
      topReserve + baseTile * farScale / 2 + 14,
    );
    // Rises steadily near the front (so each card's top edge, with the
    // name, shows above the one in front) and bends up toward the back.
    final p1 = compact
        ? Offset(w * 0.80, p0.dy - (p0.dy - p2.dy) * 0.30)
        : Offset(w * 0.50, p0.dy - (p0.dy - p2.dy) * 0.45);

    Offset centerAt(double t) {
      final u = curveAt(t);
      final a = (1 - u) * (1 - u);
      final b = 2 * (1 - u) * u;
      final c = u * u;
      return Offset(
        a * p0.dx + b * p1.dx + c * p2.dx,
        a * p0.dy + b * p1.dy + c * p2.dy,
      );
    }

    // The fine timeline runs just above the tiles' top-left corners, which
    // stay exposed as the deck steps up and right.
    Offset lineAt(double t) {
      final s = scaleAt(t);
      return centerAt(t) -
          Offset(baseTile * s * kLineInset, baseTile * s / 2 + 22 * s);
    }

    final line = <Offset>[for (var i = 0; i <= 64; i++) lineAt(i / 64)];

    final ticks = <BirthdayTimelineTick>[];
    for (var d = 0; d <= spanDays; d += tickDays) {
      final t = d / spanDays;
      final date = DateTime(today.year, today.month, today.day + d);
      ticks.add(
        BirthdayTimelineTick(
          position: lineAt(t),
          depth: t,
          scale: scaleAt(t),
          major: d == 0,
          label: d == 0 ? 'TODAY' : null,
        ),
      );
      if (d > 0) {
        // Month starts inside this tick period get a small label.
        final prev = DateTime(
          today.year,
          today.month,
          today.day + d - tickDays,
        );
        if (prev.month != date.month) {
          final first = DateTime(date.year, date.month, 1);
          final fd = DateTime.utc(
            first.year,
            first.month,
            first.day,
          ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
          final ft = fd / spanDays;
          ticks.add(
            BirthdayTimelineTick(
              position: lineAt(ft),
              depth: ft,
              scale: scaleAt(ft),
              major: true,
              label: DateFormat('MMM').format(first).toUpperCase(),
            ),
          );
        }
      }
    }

    // Tiles follow their date, nudged apart so a busy week still fans out:
    // a minimum step along the curve, and each card's top edge (name and
    // countdown) must clear the card in front by [minRise].
    double topAt(double t) => centerAt(t).dy - baseTile * scaleAt(t) / 2;
    List<double> spread(double minGap, double minRise) {
      final ts = <double>[];
      for (final b in birthdays) {
        var t = (b.daysFrom(today) / spanDays).clamp(0.0, 1.0);
        if (ts.isNotEmpty) {
          final prevT = ts.last;
          final u = math.max(curveAt(t), curveAt(prevT) + minGap);
          t = _inverseCurve(u.clamp(0.0, 1.0));
          final need = topAt(prevT) - minRise * scaleAt(prevT);
          while (t < 1 && topAt(t) > need) {
            t = math.min(1.0, t + 0.002);
          }
        }
        ts.add(t);
      }
      return ts;
    }

    // Loosen the spacing if a long list would pile up at the far end.
    var gap = compact ? 0.12 : 0.10;
    var rise = baseTile * (compact ? 0.17 : 0.20);
    var ts = spread(gap, rise);
    bool crowded(List<double> ts, double gap) {
      for (var i = 1; i < ts.length; i++) {
        if (curveAt(ts[i]) - curveAt(ts[i - 1]) < gap * 0.6) return true;
      }
      return false;
    }

    for (var i = 0; i < 6 && crowded(ts, gap); i++) {
      gap *= 0.8;
      rise *= 0.8;
      ts = spread(gap, rise);
    }
    final placements = <BirthdayTilePlacement>[];
    for (var i = 0; i < birthdays.length; i++) {
      final trueT = (birthdays[i].daysFrom(today) / spanDays).clamp(0.0, 1.0);
      placements.add(
        BirthdayTilePlacement(
          birthday: birthdays[i],
          center: centerAt(ts[i]),
          scale: scaleAt(ts[i]),
          depth: ts[i],
          anchor: lineAt(trueT),
        ),
      );
    }

    return BirthdayTimelineLayout._(
      size: size,
      baseTile: baseTile,
      tickDays: tickDays,
      spanDays: spanDays,
      tiles: placements.reversed.toList(),
      ticks: ticks,
      line: line,
    );
  }

  static double _inverseCurve(double u) => u / (1 + k - k * u);
}

/// The whole BIRTHDAYS dashboard slide: black canvas, small header, and
/// the glass-tile timeline filling the rest.
class DashboardBirthdaysSlide extends StatelessWidget {
  const DashboardBirthdaysSlide({
    super.key,
    required this.metrics,
    required this.birthdays,
    required this.today,
  });

  final DashboardMetrics metrics;
  final List<DashboardBirthday> birthdays;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return DashboardSlide(
      metrics: metrics,
      tint: BirthdayTimelineColors.magenta,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF07040C), BirthdayTimelineColors.canvas],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.cake_rounded,
            tint: BirthdayTimelineColors.magenta,
            title: 'BIRTHDAYS',
          ),
          SizedBox(height: metrics.isCompact ? 8 : 12),
          Expanded(
            child: DashboardBirthdayTimeline(
              birthdays: birthdays,
              today: today,
              metrics: metrics,
            ),
          ),
        ],
      ),
    );
  }
}

/// BIRTHDAYS slide body: frosted glass tiles fanned out along a receding
/// timeline. The next birthday is the big tile at the front left.
class DashboardBirthdayTimeline extends StatelessWidget {
  const DashboardBirthdayTimeline({
    super.key,
    required this.birthdays,
    required this.today,
    required this.metrics,
    this.blurredTiles = 3,
  });

  final List<DashboardBirthday> birthdays;
  final DateTime today;
  final DashboardMetrics metrics;

  /// Only the nearest tiles get a real backdrop blur (it is the costly
  /// part). Tiles further back use a denser translucent fill instead.
  final int blurredTiles;

  @override
  Widget build(BuildContext context) {
    if (birthdays.isEmpty) {
      return Center(
        key: const ValueKey('birthday-timeline-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cake_outlined,
              size: 48,
              color: BirthdayTimelineColors.lilac.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'No birthdays coming up',
              style: TextStyle(
                color: DashboardTheme.inkMuted,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final layout = BirthdayTimelineLayout.compute(
          size: size,
          birthdays: birthdays,
          today: DateUtils.dateOnly(today),
          compact: metrics.isCompact,
        );
        final count = layout.tiles.length;
        return Stack(
          key: const ValueKey('birthday-timeline'),
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _TimelinePainter(layout, compact: metrics.isCompact),
                ),
              ),
            ),
            for (var i = 0; i < count; i++)
              _placeTile(
                layout,
                layout.tiles[i],
                // tiles are far → near; index from the front:
                blur: count - 1 - i < blurredTiles,
              ),
          ],
        );
      },
    );
  }

  Widget _placeTile(
    BirthdayTimelineLayout layout,
    BirthdayTilePlacement p, {
    required bool blur,
  }) {
    final base = layout.baseTile;
    // Slight turn toward the viewer's left, stronger further back, for a
    // fanned-deck feel. Perspective via the (3,2) entry.
    final turn = -0.10 - 0.22 * p.depth;
    final matrix = Matrix4.identity()
      ..translateByDouble(p.center.dx, p.center.dy, 0, 1)
      ..setEntry(3, 2, 0.0009)
      ..rotateY(turn)
      ..scaleByDouble(p.scale, p.scale, 1, 1)
      ..translateByDouble(-base / 2, -base / 2, 0, 1);
    return Positioned(
      left: 0,
      top: 0,
      width: base,
      height: base,
      child: Transform(
        transform: matrix,
        child: BirthdayGlassTile(
          birthday: p.birthday,
          today: today,
          size: base,
          depth: p.depth,
          blur: blur,
          compact: metrics.isCompact,
        ),
      ),
    );
  }
}

/// One frosted birthday card. Laid out at the front-tile size; the timeline
/// scales it down with depth.
class BirthdayGlassTile extends StatelessWidget {
  const BirthdayGlassTile({
    super.key,
    required this.birthday,
    required this.today,
    required this.size,
    this.depth = 0,
    this.blur = true,
    this.compact = false,
  });

  final DashboardBirthday birthday;
  final DateTime today;
  final double size;
  final double depth;
  final bool blur;
  final bool compact;

  static String daysLabel(int days) => switch (days) {
    0 => 'TODAY',
    1 => 'TOMORROW',
    _ => 'IN $days DAYS',
  };

  @override
  Widget build(BuildContext context) {
    final days = birthday.daysFrom(DateUtils.dateOnly(today));
    final isToday = days == 0;
    // Fade with distance by lowering alpha rather than an Opacity layer.
    final fade = 1 - 0.55 * depth;
    final radius = BorderRadius.circular(size * 0.085);
    final pad = size * 0.075;
    final nameSize = size * (compact ? 0.13 : 0.12);
    final ink = Colors.white.withValues(alpha: 0.96 * fade);
    final inkSoft = BirthdayTimelineColors.lilac.withValues(alpha: 0.85 * fade);

    final turning = birthday.turning;
    final content = Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and countdown sit on the top edge: that strip stays visible
          // when the nearer card overlaps the rest.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  birthday.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: nameSize,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SizedBox(width: size * 0.03),
              Container(
                margin: EdgeInsets.only(top: size * 0.012),
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.035,
                  vertical: size * 0.016,
                ),
                decoration: BoxDecoration(
                  color: isToday
                      ? BirthdayTimelineColors.magenta.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.10 * fade),
                  borderRadius: BorderRadius.circular(size),
                  border: Border.all(
                    color: BirthdayTimelineColors.magenta.withValues(
                      alpha: 0.55 * fade,
                    ),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  daysLabel(days),
                  style: TextStyle(
                    color: ink,
                    fontSize: size * 0.042,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: size * 0.025),
          Row(
            children: [
              Icon(
                Icons.cake_rounded,
                size: size * 0.055,
                color: BirthdayTimelineColors.magenta.withValues(
                  alpha: 0.9 * fade,
                ),
              ),
              SizedBox(width: size * 0.02),
              Flexible(
                child: Text(
                  [
                    DateFormat('EEE d MMM').format(birthday.date),
                    if (turning != null) 'Turns $turning',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: inkSoft,
                    fontSize: size * 0.052,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MemberAvatar(
                photoURL: birthday.photoUrl,
                name: birthday.name,
                radius: size * 0.09,
                backgroundColor: BirthdayTimelineColors.purple.withValues(
                  alpha: 0.85 * fade,
                ),
                foregroundColor: ink,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35 * fade),
                  width: 1,
                ),
              ),
              const Spacer(),
              // Big faint age numeral, like a watermark in the glass.
              if (turning != null)
                Text(
                  '$turning',
                  style: TextStyle(
                    color: BirthdayTimelineColors.lilac.withValues(
                      alpha: 0.22 * fade,
                    ),
                    fontSize: size * 0.30,
                    height: 0.9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                  ),
                )
              else
                Icon(
                  Icons.cake_outlined,
                  size: size * 0.22,
                  color: BirthdayTimelineColors.lilac.withValues(
                    alpha: 0.18 * fade,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final glass = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (blur ? 0.16 : 0.12) * fade),
            BirthdayTimelineColors.purple.withValues(
              alpha: (blur ? 0.20 : 0.34) * fade,
            ),
            BirthdayTimelineColors.canvas.withValues(alpha: blur ? 0.30 : 0.72),
          ],
          stops: const [0, 0.45, 1],
        ),
        border: Border.all(
          color:
              (isToday
                      ? BirthdayTimelineColors.magenta
                      : Color.lerp(
                          BirthdayTimelineColors.magenta,
                          BirthdayTimelineColors.lilac,
                          0.35,
                        )!)
                  .withValues(alpha: (isToday ? 0.95 : 0.7) * fade),
          width: isToday ? 2.2 : 1.4,
        ),
      ),
      child: content,
    );

    return DecoratedBox(
      key: ValueKey('birthday-tile-${birthday.id}'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: BirthdayTimelineColors.magenta.withValues(
              alpha: (isToday ? 0.45 : 0.18) * fade,
            ),
            blurRadius: size * 0.12,
            spreadRadius: -size * 0.02,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: blur
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: glass,
              )
            : glass,
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.layout, {required this.compact});

  final BirthdayTimelineLayout layout;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft glows so the frosted tiles have something to blur.
    final w = size.width;
    final h = size.height;
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(
      Offset(w * 0.82, h * 0.22),
      math.max(w, h) * 0.38,
      BirthdayTimelineColors.magenta.withValues(alpha: 0.16),
    );
    glow(
      Offset(w * 0.18, h * 0.80),
      math.max(w, h) * 0.34,
      BirthdayTimelineColors.purple.withValues(alpha: 0.22),
    );

    // The fine timeline itself, fading into the distance.
    final pts = layout.line;
    for (var i = 1; i < pts.length; i++) {
      final t = i / (pts.length - 1);
      canvas.drawLine(
        pts[i - 1],
        pts[i],
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55 * (1 - 0.6 * t))
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
    }

    for (final tick in layout.ticks) {
      final len = (tick.major ? 18.0 : 10.0) * tick.scale;
      final alpha = (tick.major ? 0.85 : 0.6) * (1 - 0.6 * tick.depth);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = tick.major ? 1.2 : 0.8;
      canvas.drawLine(
        tick.position.translate(0, -len),
        tick.position.translate(0, len * 0.35),
        paint,
      );
      final label = tick.label;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: alpha * 0.9),
              fontSize: math.max(
                8.5,
                (compact ? 10 : 12) * math.sqrt(tick.scale),
              ),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          tick.position.translate(-tp.width / 2, -len - tp.height - 3),
        );
      }
    }

    // Date pins: a hairline from each birthday's true date down to its tile.
    for (final p in layout.tiles) {
      final top = p.center.translate(
        -layout.baseTile * p.scale * BirthdayTimelineLayout.kLineInset,
        -layout.baseTile * p.scale / 2,
      );
      final alpha = 0.5 * (1 - 0.6 * p.depth);
      canvas.drawLine(
        p.anchor,
        top,
        Paint()
          ..color = BirthdayTimelineColors.lilac.withValues(alpha: alpha)
          ..strokeWidth = 0.8,
      );
      canvas.drawCircle(
        p.anchor,
        3.2 * math.sqrt(p.scale),
        Paint()
          ..color = BirthdayTimelineColors.magenta.withValues(
            alpha: 0.95 * (1 - 0.5 * p.depth),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}
