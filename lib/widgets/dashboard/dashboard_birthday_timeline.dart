import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dashboard_calendar_overview.dart';
import 'dashboard_chrome.dart';
import 'dashboard_theme.dart';

/// Birthday purple family, carried over from the old glass-tile timeline.
class BirthdayTimelineColors {
  static const Color magenta = Color(0xFFE254FF);
  static const Color purple = Color(0xFF8B5BB5); // CalendarColors.birthday
  static const Color lilac = Color(0xFFD9B8FF);
  static const Color canvas = Color(0xFF030206);
}

/// Monday–Sunday rows on the BIRTHDAYS dashboard slide: this week plus the
/// next three. Late in the week that is a little under 28 days ahead; the
/// board stays a stable four-row grid on the wall tablet.
const int dashboardBirthdayLookAheadWeekCount = 4;

/// One upcoming (or earlier-this-week) birthday on the dashboard board.
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

  /// Date of this occurrence (date only, local).
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

/// First name for a narrow day cell. Full single-word names ("Dad") stay as is.
String dashboardBirthdayShortName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.split(RegExp(r'\s+')).first;
}

String? _memberPhotoFor(String name, List<Map<String, dynamic>> members) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return null;
  final first = dashboardBirthdayShortName(name).toLowerCase();
  final singleWord = !lower.contains(' ');
  for (final m in members) {
    final memberName = (m['name'] ?? m['displayName'] ?? '').toString().trim();
    final photo = (m['photoURL'] ?? '').toString().trim();
    if (memberName.isEmpty || photo.isEmpty) continue;
    final memberLower = memberName.toLowerCase();
    if (memberLower == lower ||
        ((singleWord || !memberLower.contains(' ')) &&
            dashboardBirthdayShortName(memberName).toLowerCase() == first)) {
      return photo;
    }
  }
  return null;
}

/// Unique birthdays from the dashboard event list (`category: birthday`,
/// including the projected hub birthdays), soonest first.
///
/// [minDays] / [maxDays] are inclusive offsets from [now]'s calendar day.
/// Leave either null for an open end. The same name on the same day is kept
/// once, even if a Google copy and a projected row both exist.
List<DashboardBirthday> dashboardBirthdaysFromEvents(
  List<Map<String, dynamic>> events, {
  required DateTime now,
  List<Map<String, dynamic>> members = const [],
  int? minDays,
  int? maxDays,
}) {
  final today = DateUtils.dateOnly(now);
  final seen = <String>{};
  final all = <DashboardBirthday>[];
  for (final e in events) {
    if ((e['category'] ?? '') != 'birthday') continue;
    final start = dashboardEventDateTime(e['start']);
    if (start == null) continue;
    final date = DateUtils.dateOnly(start);
    final days = _dayNumber(date) - _dayNumber(today);
    if (minDays != null && days < minDays) continue;
    if (maxDays != null && days > maxDays) continue;
    final split = dashboardSplitBirthdayTitle((e['summary'] ?? '').toString());
    final name = (e['birthdayName'] ?? split.name).toString().trim();
    if (name.isEmpty) continue;
    final key = '${name.toLowerCase()}|${_dayNumber(date)}';
    if (!seen.add(key)) continue;
    final turningRaw = e['turning'];
    all.add(
      DashboardBirthday(
        id: (e['id'] ?? '').toString().isEmpty
            ? key
            : (e['id'] ?? '').toString(),
        name: name,
        date: date,
        turning: turningRaw is int ? turningRaw : split.turning,
        photoUrl: _memberPhotoFor(name, members),
      ),
    );
  }
  all.sort((a, b) => a.date.compareTo(b.date));
  return all;
}

/// Upcoming birthdays, soonest first.
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
  final all = dashboardBirthdaysFromEvents(
    events,
    now: now,
    members: members,
    minDays: 0,
    maxDays: 365,
  );
  final today = DateUtils.dateOnly(now);
  final within = all.where((b) => b.daysFrom(today) <= horizonDays).length;
  final count = math.min(
    maxCount,
    math.max(within, math.min(minCount, all.length)),
  );
  return all.take(count).toList();
}

/// Birthdays that land on the BIRTHDAYS look-ahead board, including days
/// earlier in the current week (those cells stay visible, greyed).
List<DashboardBirthday> dashboardBirthdaysInLookAhead(
  List<Map<String, dynamic>> events, {
  required DateTime now,
  List<Map<String, dynamic>> members = const [],
  int weekCount = dashboardBirthdayLookAheadWeekCount,
}) {
  final weeks = dashboardLookAheadWeeks(now, weekCount: weekCount);
  if (weeks.isEmpty) return const [];
  final today = DateUtils.dateOnly(now);
  final start = DateUtils.dateOnly(weeks.first.first);
  final end = DateUtils.dateOnly(weeks.last.last);
  return dashboardBirthdaysFromEvents(
    events,
    now: now,
    members: members,
    minDays: _dayNumber(start) - _dayNumber(today),
    maxDays: _dayNumber(end) - _dayNumber(today),
  );
}

String dashboardBirthdayDayKey(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return 'birthday-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String dashboardBirthdayPastDimKey(DateTime day) =>
    'birthday-past-dim-${day.year}-${day.month}-${day.day}';

String dashboardBirthdayMonthKey(DateTime month) {
  final date = dashboardLookAheadMonthOf(month);
  return 'birthday-month-${date.year}-${date.month.toString().padLeft(2, '0')}';
}

/// The BIRTHDAYS dashboard slide: a roughly four-week LOOK AHEAD board
/// populated only with birthday cakes.
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
    final date = DateUtils.dateOnly(today);
    final weeks = dashboardLookAheadWeeks(
      date,
      weekCount: dashboardBirthdayLookAheadWeekCount,
    );
    final horizonEnd = weeks.last.last;
    final rangeLabel = dashboardCompactDayRange(date, horizonEnd);
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
            trailing: _BirthdayRangeChip(label: rangeLabel),
          ),
          SizedBox(height: metrics.isCompact ? 8 : 12),
          Expanded(
            child: _BirthdayLookAheadBoard(
              metrics: metrics,
              weeks: weeks,
              birthdays: birthdays,
              today: date,
              rangeLabel: rangeLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayRangeChip extends StatelessWidget {
  const _BirthdayRangeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: DashboardTheme.fade(Colors.white, 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: DashboardTheme.inkMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _BirthdayLookAheadBoard extends StatelessWidget {
  const _BirthdayLookAheadBoard({
    required this.metrics,
    required this.weeks,
    required this.birthdays,
    required this.today,
    required this.rangeLabel,
  });

  final DashboardMetrics metrics;
  final List<List<DateTime>> weeks;
  final List<DashboardBirthday> birthdays;
  final DateTime today;
  final String rangeLabel;

  Map<String, List<DashboardBirthday>> _byDay() {
    final map = <String, List<DashboardBirthday>>{};
    for (final birthday in birthdays) {
      map
          .putIfAbsent(dashboardBirthdayDayKey(birthday.date), () => [])
          .add(birthday);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final compact = metrics.isCompact;
    final rowGap = compact ? 8.0 : 10.0;
    final monthGap = compact ? 16.0 : 22.0;
    final sections = dashboardLookAheadMonthSections(weeks, now: today);
    final byDay = _byDay();
    final hasAny = birthdays.any((b) {
      final day = DateUtils.dateOnly(b.date);
      return !day.isBefore(weeks.first.first) && !day.isAfter(weeks.last.last);
    });

    return DashboardGlassCard(
      tint: BirthdayTimelineColors.magenta,
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        key: const ValueKey('birthday-lookahead'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BirthdayBoardLabel(
            text: 'NEXT 4 WEEKS',
            trailing: compact ? null : rangeLabel,
          ),
          if (!hasAny) ...[
            SizedBox(height: compact ? 8 : 10),
            const Text(
              'No birthdays in the next four weeks',
              key: ValueKey('birthday-lookahead-empty'),
              style: TextStyle(
                color: DashboardTheme.inkFaint,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          SizedBox(height: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var sectionIndex = 0;
                  sectionIndex < sections.length;
                  sectionIndex++
                ) ...[
                  if (sectionIndex > 0) SizedBox(height: monthGap),
                  ..._sectionBody(
                    sections[sectionIndex],
                    byDay: byDay,
                    rowGap: rowGap,
                    weekBase: sections
                        .take(sectionIndex)
                        .fold<int>(0, (n, s) => n + s.weeks.length),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sectionBody(
    DashboardLookAheadMonthSection section, {
    required Map<String, List<DashboardBirthday>> byDay,
    required double rowGap,
    required int weekBase,
  }) {
    return [
      KeyedSubtree(
        key: ValueKey(dashboardBirthdayMonthKey(section.month)),
        child: _BirthdayMonthHeader(
          label: section.label,
          compact: metrics.isCompact,
        ),
      ),
      SizedBox(height: metrics.isCompact ? 8 : 10),
      for (var i = 0; i < section.weeks.length; i++) ...[
        if (i > 0) SizedBox(height: rowGap),
        Expanded(
          child: _BirthdayWeekRow(
            key: ValueKey('birthday-week-${weekBase + i}'),
            metrics: metrics,
            days: section.weeks[i],
            byDay: byDay,
            today: today,
          ),
        ),
      ],
    ];
  }
}

class _BirthdayBoardLabel extends StatelessWidget {
  const _BirthdayBoardLabel({required this.text, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8FB0C8),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: DashboardTheme.fade(Colors.white, 0.16),
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: DashboardTheme.inkFaint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }
}

class _BirthdayMonthHeader extends StatelessWidget {
  const _BirthdayMonthHeader({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF8FB0C8),
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: DashboardTheme.fade(Colors.white, 0.14),
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _BirthdayWeekRow extends StatelessWidget {
  const _BirthdayWeekRow({
    super.key,
    required this.metrics,
    required this.days,
    required this.byDay,
    required this.today,
  });

  final DashboardMetrics metrics;
  final List<DateTime> days;
  final Map<String, List<DashboardBirthday>> byDay;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) SizedBox(width: metrics.isCompact ? 6 : 8),
          Expanded(
            child: _BirthdayDayCell(
              key: ValueKey(dashboardBirthdayDayKey(days[i])),
              metrics: metrics,
              day: days[i],
              birthdays: byDay[dashboardBirthdayDayKey(days[i])] ?? const [],
              isToday: DateUtils.isSameDay(days[i], today),
              isPast: days[i].isBefore(today),
            ),
          ),
        ],
      ],
    );
  }
}

/// One day box. Chrome matches LOOK AHEAD (today green, past greyed);
/// the body is only cakes, not event chips.
class _BirthdayDayCell extends StatelessWidget {
  const _BirthdayDayCell({
    super.key,
    required this.metrics,
    required this.day,
    required this.birthdays,
    required this.isToday,
    required this.isPast,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<DashboardBirthday> birthdays;
  final bool isToday;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day).toUpperCase();
    final wash = isToday ? Colors.greenAccent : DashboardTheme.schedule;
    final labelColor = isToday
        ? Colors.greenAccent
        : isPast
        ? DashboardTheme.fade(DashboardTheme.inkFaint, 0.6)
        : const Color(0xFF8FB0C8);
    final dateColor = isToday
        ? Colors.greenAccent
        : isPast
        ? DashboardTheme.fade(DashboardTheme.inkFaint, 0.75)
        : DashboardTheme.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isPast
            ? Colors.black.withValues(alpha: 0.28)
            : DashboardTheme.fade(wash, isToday ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
        border: Border.all(
          color: isPast
              ? Colors.white.withValues(alpha: 0.05)
              : DashboardTheme.fade(wash, isToday ? 0.45 : 0.16),
          width: isToday ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.isCompact ? 5 : 8,
          metrics.isCompact ? 8 : 10,
          metrics.isCompact ? 5 : 8,
          metrics.isCompact ? 6 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isToday ? 'TODAY' : weekday,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: metrics.isCompact ? 10 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dateColor,
                fontSize: metrics.isCompact ? 20 : 24,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            SizedBox(height: metrics.isCompact ? 4 : 6),
            Expanded(
              child: ClipRect(
                child: _pastDim(
                  birthdays.isEmpty
                      ? const SizedBox.shrink()
                      : _BirthdayCakeStack(
                          birthdays: birthdays,
                          compact: metrics.isCompact,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pastDim(Widget child) {
    if (!isPast) return child;
    return Opacity(
      key: ValueKey(dashboardBirthdayPastDimKey(day)),
      opacity: dashboardLookAheadPastOpacity,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(
          dashboardSaturationMatrix(dashboardLookAheadPastSaturation),
        ),
        child: child,
      ),
    );
  }
}

class _BirthdayCakeStack extends StatelessWidget {
  const _BirthdayCakeStack({required this.birthdays, required this.compact});

  final List<DashboardBirthday> birthdays;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final birthday in birthdays)
              BirthdayCakeMarker(birthday: birthday, compact: compact),
          ],
        ),
      ),
    );
  }
}

/// Cake, first name, and age when known. Used by tests to find markers.
class BirthdayCakeMarker extends StatelessWidget {
  const BirthdayCakeMarker({
    super.key,
    required this.birthday,
    required this.compact,
  });

  final DashboardBirthday birthday;
  final bool compact;

  static String ageLabel(int turning, {required bool compact}) {
    return compact ? '$turning' : 'Turns $turning';
  }

  @override
  Widget build(BuildContext context) {
    final name = dashboardBirthdayShortName(birthday.name);
    final turning = birthday.turning;
    final cakeSize = compact ? 22.0 : 28.0;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 2 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cake_rounded,
            size: cakeSize,
            color: BirthdayTimelineColors.magenta,
          ),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: DashboardTheme.ink,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          if (turning != null)
            Text(
              ageLabel(turning, compact: compact),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: BirthdayTimelineColors.lilac,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
        ],
      ),
    );
  }
}
