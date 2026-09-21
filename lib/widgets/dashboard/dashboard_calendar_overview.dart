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

String dashboardLookAheadDayKey(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return 'look-ahead-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// About six months from today. Monday alignment often needs a partial last row.
const int dashboardLookAheadHorizonMonths = 6;

/// How many Monday–Sunday rows are needed to cover ~6 months from [now],
/// starting at the Monday of the current week.
int dashboardLookAheadWeekCount(DateTime now) {
  final today = DateUtils.dateOnly(now);
  final start = dashboardMondayOf(today);
  final coverUntil = DateTime(
    today.year,
    today.month + dashboardLookAheadHorizonMonths,
    today.day,
  );
  final lastMonday = dashboardMondayOf(coverUntil);
  return lastMonday.difference(start).inDays ~/ 7 + 1;
}

/// Real Monday–Sunday weeks: current week (containing today) plus following
/// weeks until ~6 months ahead is covered.
List<List<DateTime>> dashboardLookAheadWeeks(DateTime now, {int? weekCount}) {
  final today = DateUtils.dateOnly(now);
  final start = dashboardMondayOf(today);
  final count = weekCount ?? dashboardLookAheadWeekCount(today);
  return List<List<DateTime>>.generate(count, (week) {
    return List<DateTime>.generate(
      7,
      (day) => start.add(Duration(days: week * 7 + day)),
    );
  });
}

DateTime dashboardLookAheadMonthOf(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return DateTime(date.year, date.month);
}

String dashboardLookAheadMonthKey(DateTime month) {
  final date = dashboardLookAheadMonthOf(month);
  return 'look-ahead-month-${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String dashboardLookAheadMonthGapKey(DateTime month) {
  final date = dashboardLookAheadMonthOf(month);
  return 'look-ahead-month-gap-${date.year}-${date.month.toString().padLeft(2, '0')}';
}

/// Kitchen-tablet month label: "October", with a year when the month is not
/// in the same calendar year as [now] (the ~6 month board crosses New Year).
String dashboardLookAheadMonthLabel(DateTime month, DateTime now) {
  final date = dashboardLookAheadMonthOf(month);
  final today = DateUtils.dateOnly(now);
  final raw = date.year == today.year
      ? DateFormat('MMMM').format(date)
      : DateFormat('MMMM y').format(date);
  return raw.toUpperCase();
}

/// One labeled month in the LOOK AHEAD week list.
///
/// Boundary rule: the first week is always headed with the month of [now], so
/// TODAY sits under the current month. Each later week opens a new section as
/// soon as any day in that row belongs to a calendar month that has not yet
/// been labeled. A week that spans two months (Mon 28 Sep–Sun 4 Oct) is
/// therefore headed "October" because 1 Oct lands in the row.
///
/// If today is still in the old month on a spanning first week (e.g. 30 Dec
/// with 1 Jan in the same row), the first header stays on today's month and
/// the new month is labeled on the following week.
class DashboardLookAheadMonthSection {
  DashboardLookAheadMonthSection({
    required this.month,
    required this.label,
    required List<List<DateTime>> weeks,
  }) : weeks = List<List<DateTime>>.from(weeks);

  /// First day of the labeled calendar month.
  final DateTime month;
  final String label;
  final List<List<DateTime>> weeks;
}

int _lookAheadMonthId(DateTime day) {
  final month = dashboardLookAheadMonthOf(day);
  return month.year * 12 + month.month;
}

/// Groups Monday–Sunday [weeks] into month sections. See
/// [DashboardLookAheadMonthSection] for the spanning-week rule.
List<DashboardLookAheadMonthSection> dashboardLookAheadMonthSections(
  List<List<DateTime>> weeks, {
  required DateTime now,
}) {
  if (weeks.isEmpty) return const [];

  final today = DateUtils.dateOnly(now);
  final labeled = <int>{};
  final sections = <DashboardLookAheadMonthSection>[];

  for (var i = 0; i < weeks.length; i++) {
    final week = weeks[i];
    DateTime? headerMonth;
    if (i == 0) {
      headerMonth = dashboardLookAheadMonthOf(today);
    } else {
      for (final day in week) {
        final id = _lookAheadMonthId(day);
        if (!labeled.contains(id)) {
          headerMonth = dashboardLookAheadMonthOf(day);
          break;
        }
      }
    }

    if (headerMonth != null) {
      labeled.add(_lookAheadMonthId(headerMonth));
      sections.add(
        DashboardLookAheadMonthSection(
          month: headerMonth,
          label: dashboardLookAheadMonthLabel(headerMonth, today),
          weeks: [week],
        ),
      );
    } else {
      sections.last.weeks.add(week);
    }
  }

  return sections;
}

/// Second dashboard slide: Monday–Sunday week-strips for the next ~6 months.
///
/// Each row is a real calendar week (Mon→Sun). Tapping a day opens a detail
/// card listing that day's events. [onDayTap] is fired as well so the host
/// screen can keep showing play–pause controls on the same touch.
class DashboardCalendarOverviewSlide extends StatefulWidget {
  const DashboardCalendarOverviewSlide({
    super.key,
    required this.metrics,
    required this.events,
    required this.now,
    this.members = const [],
    this.palette,
    this.padding,
    this.onDayTap,
    this.onCloseDayDetail,
  });

  final DashboardMetrics metrics;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final List<Map<String, dynamic>> members;
  final HubMemberPalette? palette;
  final EdgeInsets? padding;

  /// Invoked when a day cell is tapped, in addition to opening day detail.
  final ValueChanged<DateTime>? onDayTap;

  /// Invoked when the day-detail card is dismissed.
  final VoidCallback? onCloseDayDetail;

  HubMemberPalette get resolvedPalette =>
      palette ?? HubMemberPalette.fromMembers(members);

  @override
  State<DashboardCalendarOverviewSlide> createState() =>
      _DashboardCalendarOverviewSlideState();
}

class _DashboardCalendarOverviewSlideState
    extends State<DashboardCalendarOverviewSlide> {
  DateTime? _selectedDay;

  void _handleDayTap(DateTime day) {
    final date = DateUtils.dateOnly(day);
    setState(() => _selectedDay = date);
    widget.onDayTap?.call(date);
  }

  void _closeDayDetail() {
    if (_selectedDay == null) return;
    setState(() => _selectedDay = null);
    widget.onCloseDayDetail?.call();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(widget.now);
    final weeks = dashboardLookAheadWeeks(today);
    final horizonEnd = weeks.last.last;
    final rangeStart = weeks.first.first;
    final hasUpcoming = widget.events.any((event) {
      final startRaw = dashboardEventDateTime(event['start']);
      if (startRaw == null) return false;
      final start = DateUtils.dateOnly(startRaw);
      final end = DateUtils.dateOnly(
        dashboardEventDateTime(event['end']) ?? startRaw,
      );
      return !end.isBefore(rangeStart) && !start.isAfter(horizonEnd);
    });
    final whoPalette = widget.resolvedPalette;
    final selectedEvents = _selectedDay == null
        ? const <Map<String, dynamic>>[]
        : dashboardEventsOnDay(widget.events, _selectedDay!);

    return DashboardSlide(
      metrics: widget.metrics,
      tint: DashboardTheme.schedule,
      padding: widget.padding,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(
                metrics: widget.metrics,
                icon: Icons.calendar_view_week_rounded,
                tint: DashboardTheme.schedule,
                title: 'LOOK AHEAD',
                trailing: _RangeChip(
                  label: dashboardCompactDayRange(today, horizonEnd),
                ),
              ),
              SizedBox(height: widget.metrics.isCompact ? 12 : 16),
              Expanded(
                child: _LookAheadWeekBoard(
                  metrics: widget.metrics,
                  weeks: weeks,
                  events: widget.events,
                  today: today,
                  selectedDay: _selectedDay,
                  rangeLabel: dashboardCompactDayRange(today, horizonEnd),
                  emptyHint: hasUpcoming
                      ? null
                      : 'Quiet stretch — add plans from Calendar',
                  palette: whoPalette,
                  onDayTap: _handleDayTap,
                ),
              ),
              SizedBox(height: widget.metrics.isCompact ? 8 : 10),
              CalendarGlanceLegend(
                palette: whoPalette,
                compact: widget.metrics.isCompact,
              ),
            ],
          ),
          if (_selectedDay != null)
            _LookAheadDayDetailLayer(
              metrics: widget.metrics,
              day: _selectedDay!,
              events: selectedEvents,
              palette: whoPalette,
              isToday: DateUtils.isSameDay(_selectedDay, today),
              onClose: _closeDayDetail,
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

class _MonthSectionHeader extends StatelessWidget {
  const _MonthSectionHeader({required this.label, required this.compact});

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

class _LookAheadWeekBoard extends StatelessWidget {
  const _LookAheadWeekBoard({
    required this.metrics,
    required this.weeks,
    required this.events,
    required this.today,
    required this.rangeLabel,
    required this.palette,
    required this.onDayTap,
    this.selectedDay,
    this.emptyHint,
  });

  final DashboardMetrics metrics;
  final List<List<DateTime>> weeks;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final DateTime? selectedDay;
  final String rangeLabel;
  final HubMemberPalette palette;
  final String? emptyHint;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final rowGap = metrics.isCompact ? 8.0 : 10.0;
    // Modest extra air between months so the board reads as sections, not one
    // continuous grid. Tight enough for a wall tablet.
    final monthGap = metrics.isCompact ? 16.0 : 22.0;
    // Keep day boxes tall enough for the weekday, date, and one chip.
    // Shorter than this and we scroll instead of crushing.
    final minRow = metrics.isCompact ? 108.0 : 96.0;
    final sections = dashboardLookAheadMonthSections(weeks, now: today);

    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(metrics.isCompact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(
            text: 'NEXT 6 MONTHS',
            trailing: metrics.isCompact ? null : rangeLabel,
          ),
          if (emptyHint != null) ...[
            SizedBox(height: metrics.isCompact ? 8 : 10),
            Text(
              emptyHint!,
              style: const TextStyle(
                color: DashboardTheme.inkFaint,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          SizedBox(height: metrics.isCompact ? 8 : 12),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('look-ahead-week-list'),
              physics: const BouncingScrollPhysics(),
              itemCount: sections.length,
              itemBuilder: (context, sectionIndex) {
                final section = sections[sectionIndex];
                var weekIndex = 0;
                for (var i = 0; i < sectionIndex; i++) {
                  weekIndex += sections[i].weeks.length;
                }
                return Column(
                  key: ValueKey(dashboardLookAheadMonthKey(section.month)),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sectionIndex > 0)
                      SizedBox(
                        key: ValueKey(
                          dashboardLookAheadMonthGapKey(section.month),
                        ),
                        height: monthGap,
                      ),
                    _MonthSectionHeader(
                      label: section.label,
                      compact: metrics.isCompact,
                    ),
                    SizedBox(height: metrics.isCompact ? 8 : 10),
                    for (var i = 0; i < section.weeks.length; i++) ...[
                      if (i > 0) SizedBox(height: rowGap),
                      SizedBox(
                        height: minRow,
                        child: _WeekDayRow(
                          key: ValueKey('look-ahead-week-${weekIndex + i}'),
                          metrics: metrics,
                          days: section.weeks[i],
                          events: events,
                          today: today,
                          selectedDay: selectedDay,
                          palette: palette,
                          onDayTap: onDayTap,
                        ),
                      ),
                    ],
                  ],
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
    required this.onDayTap,
    this.selectedDay,
  });

  final DashboardMetrics metrics;
  final List<DateTime> days;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final DateTime? selectedDay;
  final HubMemberPalette palette;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) SizedBox(width: metrics.isCompact ? 6 : 8),
          Expanded(
            child: _WeekDayColumn(
              key: ValueKey(dashboardLookAheadDayKey(days[i])),
              metrics: metrics,
              day: days[i],
              events: dashboardEventsOnDay(events, days[i]),
              isToday: DateUtils.isSameDay(days[i], today),
              isPast: days[i].isBefore(today),
              isSelected:
                  selectedDay != null &&
                  DateUtils.isSameDay(days[i], selectedDay),
              palette: palette,
              onTap: () => onDayTap(days[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    super.key,
    required this.metrics,
    required this.day,
    required this.events,
    required this.isToday,
    required this.isPast,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final bool isToday;
  final bool isPast;
  final bool isSelected;
  final HubMemberPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = DateFormat('EEE').format(day).toUpperCase();
    final wash = isToday ? Colors.greenAccent : DashboardTheme.schedule;
    final labelColor = isToday
        ? Colors.greenAccent
        : isPast
        ? DashboardTheme.inkFaint
        : const Color(0xFF8FB0C8);
    final dateColor = isToday
        ? Colors.greenAccent
        : isPast
        ? DashboardTheme.inkFaint
        : DashboardTheme.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final eventAreaHeight =
                (constraints.maxHeight - (metrics.isCompact ? 52 : 64)).clamp(
                  0.0,
                  constraints.maxHeight,
                );
            var chipBudget = eventAreaHeight < 26
                ? 0
                : eventAreaHeight < 54
                ? 1
                : eventAreaHeight < 82
                ? 2
                : 3;
            // "+N more" needs extra air; if it will not fit, drop to a count
            // label instead of overflowing a chip out of the day box.
            if (events.length > chipBudget &&
                chipBudget > 0 &&
                eventAreaHeight < 48) {
              chipBudget = 0;
            }
            final visible = events.take(chipBudget).toList();
            final overflow = events.length - visible.length;

            return DecoratedBox(
              decoration: BoxDecoration(
                color: DashboardTheme.fade(
                  wash,
                  isSelected
                      ? 0.20
                      : isToday
                      ? 0.12
                      : isPast
                      ? 0.03
                      : 0.05,
                ),
                borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
                border: Border.all(
                  color: DashboardTheme.fade(
                    wash,
                    isSelected
                        ? 0.70
                        : isToday
                        ? 0.45
                        : isPast
                        ? 0.10
                        : 0.16,
                  ),
                  width: isSelected || isToday ? 1.4 : 1,
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
                                    color: isPast
                                        ? DashboardTheme.inkFaint
                                        : DashboardTheme.inkMuted,
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
        ),
      ),
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

class _LookAheadDayDetailLayer extends StatelessWidget {
  const _LookAheadDayDetailLayer({
    required this.metrics,
    required this.day,
    required this.events,
    required this.palette,
    required this.isToday,
    required this.onClose,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final bool isToday;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey('look-ahead-day-detail-barrier'),
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        // Claim horizontal drags so PageView cannot swipe while the card is open.
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        child: ColoredBox(
          color: const Color(0xCC07070C),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.isCompact ? 12 : 48,
              vertical: metrics.isCompact ? 24 : 36,
            ),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (_) {},
                child: _LookAheadDayDetailCard(
                  metrics: metrics,
                  day: day,
                  events: events,
                  palette: palette,
                  isToday: isToday,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LookAheadDayDetailCard extends StatelessWidget {
  const _LookAheadDayDetailCard({
    required this.metrics,
    required this.day,
    required this.events,
    required this.palette,
    required this.isToday,
    required this.onClose,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final bool isToday;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM').format(day);
    final title = isToday ? 'Today · $dateLabel' : dateLabel;

    final header = Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isToday ? Colors.greenAccent : DashboardTheme.ink,
              fontSize: metrics.isCompact ? 18 : 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('look-ahead-day-detail-close'),
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
        ),
      ],
    );
    final summary = Text(
      events.isEmpty
          ? 'Nothing planned'
          : events.length == 1
          ? '1 plan'
          : '${events.length} plans',
      style: const TextStyle(
        color: DashboardTheme.inkMuted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );

    final body = events.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Free day — nothing on the calendar',
              key: ValueKey('look-ahead-day-detail-empty'),
              style: TextStyle(
                color: DashboardTheme.inkFaint,
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        : ListView.separated(
            key: const ValueKey('look-ahead-day-detail-events'),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final event = events[index];
              final style = CalendarColors.fromMap(event, palette: palette);
              final isBirthday = event['category'] == 'birthday';
              final isMeal = event['category'] == 'meal';
              final isWork = event['category'] == 'work';
              return CalendarSplitPill(
                style: style,
                title: dashboardGlanceTitle(event),
                subtitle: dashboardGlanceTimeLabel(event),
                density: metrics.isCompact
                    ? CalendarSplitPillDensity.regular
                    : CalendarSplitPillDensity.comfortable,
                trailing: Icon(
                  isBirthday
                      ? Icons.cake_rounded
                      : isMeal
                      ? Icons.restaurant
                      : isWork
                      ? Icons.work_outline
                      : Icons.circle,
                  size: isBirthday || isMeal || isWork ? 16 : 8,
                ),
              );
            },
          );

    return SizedBox(
      width: metrics.isCompact ? double.infinity : 560,
      height: events.isEmpty
          ? (metrics.isCompact ? 220 : 210)
          : (metrics.isCompact ? 460 : 440),
      child: DashboardGlassCard(
        tint: DashboardTheme.schedule,
        emphasized: true,
        padding: EdgeInsets.all(metrics.isCompact ? 16 : 22),
        child: Column(
          key: const ValueKey('look-ahead-day-detail'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 4),
            summary,
            SizedBox(height: metrics.isCompact ? 12 : 16),
            Expanded(child: body),
          ],
        ),
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
