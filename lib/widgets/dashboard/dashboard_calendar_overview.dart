import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';
import 'dashboard_chrome.dart';
import 'dashboard_theme.dart';

/// Monday-based week start so the kitchen tablet matches a UK household week.
DateTime dashboardMondayOf(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime? dashboardEventDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  return null;
}

/// Same inclusive day-span rule as the schedule slide.
bool dashboardEventOverlapsDay(Map<String, dynamic> data, DateTime day) {
  final startRaw = dashboardEventDateTime(data['start']);
  if (startRaw == null) return false;
  final endRaw = dashboardEventDateTime(data['end']) ?? startRaw;
  final checkDay = DateUtils.dateOnly(day);
  final dayStart = DateUtils.dateOnly(startRaw);
  final dayEnd = DateUtils.dateOnly(endRaw);
  return !checkDay.isBefore(dayStart) && !checkDay.isAfter(dayEnd);
}

List<Map<String, dynamic>> dashboardEventsOnDay(
  List<Map<String, dynamic>> events,
  DateTime day,
) {
  return events.where((event) => dashboardEventOverlapsDay(event, day)).toList()
    ..sort((a, b) {
      final aStart =
          dashboardEventDateTime(a['start']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bStart =
          dashboardEventDateTime(b['start']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });
}

/// Category colour for glance markers. List / week chips use a split pill.
Color dashboardGlanceColor(
  Map<String, dynamic> data, {
  HubMemberPalette? palette,
}) {
  return CalendarColors.fromMap(data, palette: palette).glanceDot;
}

String dashboardGlanceTitle(Map<String, dynamic> data) =>
    (data['summary'] ?? 'Event').toString();

String dashboardGlanceTimeLabel(Map<String, dynamic> data) {
  if (data['allDay'] == true) return 'All day';
  final start = dashboardEventDateTime(data['start']);
  if (start == null) return '';
  return DateFormat('HH:mm').format(start);
}

String dashboardCompactDayRange(DateTime start, DateTime end) {
  final startDay = DateUtils.dateOnly(start);
  final endDay = DateUtils.dateOnly(end);
  if (startDay.month == endDay.month && startDay.year == endDay.year) {
    return '${startDay.day}–${endDay.day} ${DateFormat('MMM').format(endDay).toUpperCase()}';
  }
  return '${startDay.day} ${DateFormat('MMM').format(startDay).toUpperCase()} – ${endDay.day} ${DateFormat('MMM').format(endDay).toUpperCase()}';
}

/// Four rolling 7-day strips starting today — the next ~4 weeks at a glance.
const int dashboardLookAheadWeekCount = 4;

List<List<DateTime>> dashboardLookAheadWeeks(
  DateTime now, {
  int weekCount = dashboardLookAheadWeekCount,
}) {
  final today = DateUtils.dateOnly(now);
  return List<List<DateTime>>.generate(weekCount, (week) {
    return List<DateTime>.generate(
      7,
      (day) => today.add(Duration(days: week * 7 + day)),
    );
  });
}

/// Second dashboard slide: four copies of the compact 7-day week strip.
///
/// Each row reuses the same day-column chips as the original look-ahead
/// top row so the next ~4 weeks stay readable without a mini-month grid.
class DashboardCalendarOverviewSlide extends StatelessWidget {
  const DashboardCalendarOverviewSlide({
    super.key,
    required this.metrics,
    required this.events,
    required this.now,
    this.members = const [],
    this.palette,
    this.padding,
  });

  final DashboardMetrics metrics;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final List<Map<String, dynamic>> members;
  final HubMemberPalette? palette;
  final EdgeInsets? padding;

  HubMemberPalette get resolvedPalette =>
      palette ?? HubMemberPalette.fromMembers(members);

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(now);
    final weeks = dashboardLookAheadWeeks(today);
    final horizonEnd = weeks.last.last;
    final hasUpcoming = weeks.any(
      (week) => week.any((day) => dashboardEventsOnDay(events, day).isNotEmpty),
    );
    final whoPalette = resolvedPalette;

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.schedule,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.calendar_view_week_rounded,
            tint: DashboardTheme.schedule,
            title: 'LOOK AHEAD',
            trailing: _RangeChip(
              label: dashboardCompactDayRange(today, horizonEnd),
            ),
          ),
          SizedBox(height: metrics.isCompact ? 12 : 16),
          Expanded(
            child: _FourWeekBoard(
              metrics: metrics,
              weeks: weeks,
              events: events,
              today: today,
              rangeLabel: dashboardCompactDayRange(today, horizonEnd),
              emptyHint: hasUpcoming
                  ? null
                  : 'Quiet stretch — add plans from Calendar',
              palette: whoPalette,
            ),
          ),
          SizedBox(height: metrics.isCompact ? 8 : 10),
          CalendarGlanceLegend(palette: whoPalette, compact: metrics.isCompact),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label});

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

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.text, this.trailing});

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

class _FourWeekBoard extends StatelessWidget {
  const _FourWeekBoard({
    required this.metrics,
    required this.weeks,
    required this.events,
    required this.today,
    required this.rangeLabel,
    required this.palette,
    this.emptyHint,
  });

  final DashboardMetrics metrics;
  final List<List<DateTime>> weeks;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final String rangeLabel;
  final HubMemberPalette palette;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(metrics.isCompact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(
            text: 'NEXT 4 WEEKS',
            trailing: metrics.isCompact ? null : rangeLabel,
          ),
          SizedBox(height: metrics.isCompact ? 8 : 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rowGap = metrics.isCompact ? 8.0 : 10.0;
                final emptyH = emptyHint == null ? 0.0 : 36.0;
                // Keep day boxes tall enough for the weekday, date, and one
                // chip. Shorter than this and we scroll instead of crushing.
                final minRow = metrics.isCompact ? 108.0 : 96.0;
                final gaps = rowGap * (weeks.length - 1);
                final fits =
                    constraints.maxHeight >=
                    weeks.length * minRow + gaps + emptyH;

                Widget weekSlot(int index) {
                  final row = _WeekDayRow(
                    key: ValueKey('look-ahead-week-$index'),
                    metrics: metrics,
                    days: weeks[index],
                    events: events,
                    today: today,
                    palette: palette,
                  );
                  if (fits) return Expanded(child: row);
                  return SizedBox(height: minRow, child: row);
                }

                final children = <Widget>[
                  for (var i = 0; i < weeks.length; i++) ...[
                    if (i > 0) SizedBox(height: rowGap),
                    weekSlot(i),
                  ],
                  if (emptyHint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      emptyHint!,
                      style: const TextStyle(
                        color: DashboardTheme.inkFaint,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ];

                if (fits) {
                  return Column(children: children);
                }
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  const _WeekDayRow({
    super.key,
    required this.metrics,
    required this.days,
    required this.events,
    required this.today,
    required this.palette,
  });

  final DashboardMetrics metrics;
  final List<DateTime> days;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final HubMemberPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) SizedBox(width: metrics.isCompact ? 6 : 8),
          Expanded(
            child: _WeekDayColumn(
              metrics: metrics,
              day: days[i],
              events: dashboardEventsOnDay(events, days[i]),
              isToday: DateUtils.isSameDay(days[i], today),
              palette: palette,
            ),
          ),
        ],
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.metrics,
    required this.day,
    required this.events,
    required this.isToday,
    required this.palette,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final bool isToday;
  final HubMemberPalette palette;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day).toUpperCase();
    return LayoutBuilder(
      builder: (context, constraints) {
        final eventAreaHeight =
            (constraints.maxHeight - (metrics.isCompact ? 52 : 64)).clamp(
              0.0,
              constraints.maxHeight,
            );
        final chipBudget = eventAreaHeight < 26
            ? 0
            : eventAreaHeight < 54
            ? 1
            : eventAreaHeight < 82
            ? 2
            : 3;
        final visible = events.take(chipBudget).toList();
        final overflow = events.length - visible.length;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: DashboardTheme.fade(
              isToday ? Colors.greenAccent : DashboardTheme.schedule,
              isToday ? 0.12 : 0.05,
            ),
            borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
            border: Border.all(
              color: DashboardTheme.fade(
                isToday ? Colors.greenAccent : DashboardTheme.schedule,
                isToday ? 0.45 : 0.16,
              ),
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
                    color: isToday
                        ? Colors.greenAccent
                        : const Color(0xFF8FB0C8),
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
                    color: isToday ? Colors.greenAccent : DashboardTheme.ink,
                    fontSize: metrics.isCompact ? 20 : 24,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: metrics.isCompact ? 6 : 8),
                Expanded(
                  child: ClipRect(
                    child: events.isEmpty
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              'Free',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: DashboardTheme.inkFaint,
                                fontSize: metrics.isCompact ? 11 : 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : chipBudget == 0
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              events.length == 1
                                  ? '1 plan'
                                  : '${events.length} plans',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: DashboardTheme.inkMuted,
                                fontSize: metrics.isCompact ? 10 : 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final event in visible)
                                _EventChip(
                                  event: event,
                                  compact: metrics.isCompact,
                                  palette: palette,
                                ),
                              if (overflow > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '+$overflow more',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: DashboardTheme.inkMuted,
                                      fontSize: metrics.isCompact ? 10 : 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

class _EventChip extends StatelessWidget {
  const _EventChip({
    required this.event,
    required this.compact,
    required this.palette,
  });

  final Map<String, dynamic> event;
  final bool compact;
  final HubMemberPalette palette;

  @override
  Widget build(BuildContext context) {
    final style = CalendarColors.fromMap(event, palette: palette);
    final title = dashboardGlanceTitle(event);
    final time = dashboardGlanceTimeLabel(event);
    final isBirthday = event['category'] == 'birthday';
    final isMeal = event['category'] == 'meal';
    final isWork = event['category'] == 'work';

    return CalendarSplitPill(
      style: style,
      title: compact || time.isEmpty || time == 'All day'
          ? title
          : '$time $title',
      density: CalendarSplitPillDensity.compact,
      margin: const EdgeInsets.only(bottom: 4),
      trailing: compact
          ? null
          : Icon(
              isBirthday
                  ? Icons.cake_rounded
                  : isMeal
                  ? Icons.restaurant
                  : isWork
                  ? Icons.work_outline
                  : Icons.circle,
              size: isBirthday || isMeal || isWork ? 11 : 6,
            ),
    );
  }
}

/// Compact who + kind key for kitchen-tablet glances.
class CalendarGlanceLegend extends StatelessWidget {
  const CalendarGlanceLegend({
    super.key,
    required this.palette,
    this.compact = false,
    this.dark = true,
  });

  final HubMemberPalette palette;
  final bool compact;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? DashboardTheme.inkMuted : const Color(0xFF5A564E);
    final swatches = [...palette.whoLegend(), ...palette.kindLegend()];

    return Wrap(
      spacing: compact ? 8 : 12,
      runSpacing: 4,
      children: [
        for (final swatch in swatches)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: swatch.color,
                  shape: swatch.category ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: swatch.category
                      ? BorderRadius.circular(2)
                      : null,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                swatch.label,
                style: TextStyle(
                  color: ink,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
