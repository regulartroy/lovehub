import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
      final aStart = dashboardEventDateTime(a['start']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = dashboardEventDateTime(b['start']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });
}

Color dashboardGlanceColor(Map<String, dynamic> data) {
  final category = data['category'] ?? 'general';
  if (category == 'birthday') return Colors.purpleAccent;
  if (category == 'meal') return Colors.greenAccent;
  if ((data['assignedTo'] ?? 'shared') == 'shared') return DashboardTheme.accent;
  return DashboardTheme.schedule;
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

String dashboardMonthRangeLabel(DateTime start, DateTime end) {
  final startDay = DateUtils.dateOnly(start);
  final endDay = DateUtils.dateOnly(end);
  if (startDay.month == endDay.month && startDay.year == endDay.year) {
    return DateFormat('MMMM').format(startDay).toUpperCase();
  }
  if (startDay.year == endDay.year) {
    return '${DateFormat('MMM').format(startDay).toUpperCase()} – ${DateFormat('MMM').format(endDay).toUpperCase()}';
  }
  return '${DateFormat('MMM y').format(startDay).toUpperCase()} – ${DateFormat('MMM y').format(endDay).toUpperCase()}';
}

/// Second dashboard slide: a 7-day week strip plus a rolling ~month grid.
///
/// Week columns answer “what’s coming in the next few days?” at a glance.
/// The Monday-start 5-week heatmap underneath shows density for the next
/// month without forcing a tap into the calendar tab.
class DashboardCalendarOverviewSlide extends StatelessWidget {
  const DashboardCalendarOverviewSlide({
    super.key,
    required this.metrics,
    required this.events,
    required this.now,
    this.padding,
  });

  final DashboardMetrics metrics;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(now);
    final weekDays = List<DateTime>.generate(7, (i) => today.add(Duration(days: i)));
    final monthStart = dashboardMondayOf(today);
    final monthDays = List<DateTime>.generate(35, (i) => monthStart.add(Duration(days: i)));
    final weekEnd = weekDays.last;
    final monthEnd = monthDays.last;
    final hasUpcoming = monthDays.any((day) => dashboardEventsOnDay(events, day).isNotEmpty);

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
              label: dashboardCompactDayRange(today, monthEnd),
            ),
          ),
          SizedBox(height: metrics.isCompact ? 12 : 16),
          Expanded(
            flex: metrics.isCompact ? 5 : 5,
            child: _WeekStrip(
              metrics: metrics,
              days: weekDays,
              events: events,
              today: today,
              rangeLabel: dashboardCompactDayRange(today, weekEnd),
            ),
          ),
          SizedBox(height: metrics.isCompact ? 10 : 14),
          Expanded(
            flex: metrics.isCompact ? 6 : 7,
            child: _MonthHeatmap(
              metrics: metrics,
              days: monthDays,
              events: events,
              today: today,
              weekEnd: weekEnd,
              title: dashboardMonthRangeLabel(monthStart, monthEnd),
              emptyHint: hasUpcoming ? null : 'Quiet month — add plans from Calendar',
            ),
          ),
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
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF8FB0C8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: DashboardTheme.fade(Colors.white, 0.16), height: 1),
          ),
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: const TextStyle(
              color: DashboardTheme.inkFaint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.metrics,
    required this.days,
    required this.events,
    required this.today,
    required this.rangeLabel,
  });

  final DashboardMetrics metrics;
  final List<DateTime> days;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(metrics.isCompact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(text: 'NEXT 7 DAYS', trailing: rangeLabel),
          SizedBox(height: metrics.isCompact ? 8 : 12),
          Expanded(
            child: Row(
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

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.metrics,
    required this.day,
    required this.events,
    required this.isToday,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day).toUpperCase();
    return LayoutBuilder(
      builder: (context, constraints) {
        final eventAreaHeight = (constraints.maxHeight - (metrics.isCompact ? 52 : 64))
            .clamp(0.0, constraints.maxHeight);
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
                    color: isToday ? Colors.greenAccent : const Color(0xFF8FB0C8),
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
  const _EventChip({required this.event, required this.compact});

  final Map<String, dynamic> event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = dashboardGlanceColor(event);
    final title = dashboardGlanceTitle(event);
    final time = dashboardGlanceTimeLabel(event);
    final isBirthday = event['category'] == 'birthday';
    final isMeal = event['category'] == 'meal';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: DashboardTheme.fade(color, 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DashboardTheme.fade(color, 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            isBirthday
                ? Icons.cake_rounded
                : isMeal
                ? Icons.restaurant
                : Icons.circle,
            color: color,
            size: isBirthday || isMeal ? 11 : 6,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              compact || time.isEmpty || time == 'All day' ? title : '$time $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DashboardTheme.ink,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({
    required this.metrics,
    required this.days,
    required this.events,
    required this.today,
    required this.weekEnd,
    required this.title,
    this.emptyHint,
  });

  final DashboardMetrics metrics;
  final List<DateTime> days;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final DateTime weekEnd;
  final String title;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    const weekdayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final rows = <List<DateTime>>[
      for (var r = 0; r < 5; r++) days.sublist(r * 7, r * 7 + 7),
    ];

    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(metrics.isCompact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(text: title),
          SizedBox(height: metrics.isCompact ? 6 : 8),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DashboardTheme.inkFaint,
                      fontSize: metrics.isCompact ? 10 : 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: metrics.isCompact ? 4 : 6),
          Expanded(
            child: Column(
              children: [
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0) SizedBox(height: metrics.isCompact ? 4 : 6),
                  Expanded(
                    child: Row(
                      children: [
                        for (var c = 0; c < 7; c++) ...[
                          if (c > 0) SizedBox(width: metrics.isCompact ? 4 : 6),
                          Expanded(
                            child: _MonthDayCell(
                              metrics: metrics,
                              day: rows[r][c],
                              events: dashboardEventsOnDay(events, rows[r][c]),
                              today: today,
                              weekEnd: weekEnd,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
        ],
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.metrics,
    required this.day,
    required this.events,
    required this.today,
    required this.weekEnd,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final DateTime weekEnd;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(day, today);
    final isPast = day.isBefore(today);
    final inLookAheadWeek = !day.isBefore(today) && !day.isAfter(weekEnd);
    final density = events.length.clamp(0, 4);
    final fill = DashboardTheme.fade(
      DashboardTheme.schedule,
      isPast ? 0.03 : 0.05 + density * 0.06,
    );
    final borderColor = isToday
        ? Colors.greenAccent
        : inLookAheadWeek
        ? DashboardTheme.fade(DashboardTheme.schedule, 0.38)
        : DashboardTheme.fade(Colors.white, 0.08);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showDots = events.isNotEmpty && constraints.maxHeight >= 26;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: isToday ? DashboardTheme.fade(Colors.greenAccent, 0.12) : fill,
            borderRadius: BorderRadius.circular(DashboardTheme.radiusSm),
            border: Border.all(color: borderColor, width: isToday ? 1.4 : 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: isPast
                        ? DashboardTheme.inkFaint
                        : isToday
                        ? Colors.greenAccent
                        : DashboardTheme.ink,
                    fontSize: metrics.isCompact ? 11 : 12,
                    fontWeight: isToday || events.isNotEmpty
                        ? FontWeight.w700
                        : FontWeight.w500,
                    height: 1.0,
                  ),
                ),
                if (showDots) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final event in events.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: dashboardGlanceColor(event).withValues(
                              alpha: isPast ? 0.45 : 0.95,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
