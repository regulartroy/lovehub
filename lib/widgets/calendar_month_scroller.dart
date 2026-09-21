import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../theme/calendar_colors.dart';
import 'calendar_split_pill.dart';
import 'dashboard/dashboard_calendar_overview.dart';

String calendarScrollerDayKey(DateTime day) {
  final date = DateUtils.dateOnly(day);
  return 'calendar-day-${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String calendarScrollerMonthKey(DateTime month) {
  final date = dashboardLookAheadMonthOf(month);
  return 'calendar-month-${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String calendarScrollerMonthGapKey(DateTime month) {
  final date = dashboardLookAheadMonthOf(month);
  return 'calendar-month-gap-${date.year}-${date.month.toString().padLeft(2, '0')}';
}

/// Monday of the week that contains the 1st of [now]'s month, so the
/// current month is fully on the Calendar board.
DateTime calendarScrollerStartMonday(DateTime now) {
  final today = DateUtils.dateOnly(now);
  return dashboardMondayOf(DateTime(today.year, today.month, 1));
}

List<DateTime> calendarScrollerWeekAt(DateTime startMonday, int weekIndex) {
  final start = DateUtils.dateOnly(startMonday);
  return List<DateTime>.generate(
    7,
    (day) => start.add(Duration(days: weekIndex * 7 + day)),
  );
}

/// Light Calendar-tab board: LOOK AHEAD month headers + gaps, Mon–Sun weeks,
/// lazy future scroll that grows as you approach the end.
///
/// Future is capped at [_maxWeeks] (~20 years) so it feels unbounded without
/// paging one month at a time. Past starts at the week of the current 1st.
class CalendarMonthScroller extends StatefulWidget {
  const CalendarMonthScroller({
    super.key,
    required this.now,
    required this.palette,
    required this.eventsForDay,
    this.selectedDay,
    this.onDayTap,
    this.initialWeekCount = 30,
  });

  final DateTime now;
  final HubMemberPalette palette;
  final List<EventModel> Function(DateTime day) eventsForDay;
  final DateTime? selectedDay;
  final ValueChanged<DateTime>? onDayTap;
  final int initialWeekCount;

  static const int chunkWeeks = 26;
  static const int maxWeeks = 52 * 20;

  @override
  State<CalendarMonthScroller> createState() => _CalendarMonthScrollerState();
}

class _CalendarMonthScrollerState extends State<CalendarMonthScroller> {
  late int _weekCount;
  late DateTime _startMonday;

  @override
  void initState() {
    super.initState();
    _startMonday = calendarScrollerStartMonday(widget.now);
    _weekCount = widget.initialWeekCount.clamp(
      8,
      CalendarMonthScroller.maxWeeks,
    );
  }

  @override
  void didUpdateWidget(covariant CalendarMonthScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextStart = calendarScrollerStartMonday(widget.now);
    if (nextStart != _startMonday) {
      _startMonday = nextStart;
      _weekCount = widget.initialWeekCount.clamp(
        8,
        CalendarMonthScroller.maxWeeks,
      );
    }
  }

  void _maybeExpand(int weekIndex) {
    if (weekIndex < _weekCount - 12) return;
    if (_weekCount >= CalendarMonthScroller.maxWeeks) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _weekCount = (_weekCount + CalendarMonthScroller.chunkWeeks).clamp(
          8,
          CalendarMonthScroller.maxWeeks,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(widget.now);
    final weeks = List<List<DateTime>>.generate(
      _weekCount,
      (index) => calendarScrollerWeekAt(_startMonday, index),
    );
    final sections = dashboardLookAheadMonthSections(weeks, now: today);

    return Column(
      children: [
        const _WeekdayStrip(),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('calendar-month-list'),
            physics: const BouncingScrollPhysics(),
            itemCount: sections.length,
            itemBuilder: (context, sectionIndex) {
              final section = sections[sectionIndex];
              var weekIndex = 0;
              for (var i = 0; i < sectionIndex; i++) {
                weekIndex += sections[i].weeks.length;
              }
              _maybeExpand(weekIndex + section.weeks.length - 1);
              return Column(
                key: ValueKey(calendarScrollerMonthKey(section.month)),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sectionIndex > 0)
                    SizedBox(
                      key: ValueKey(calendarScrollerMonthGapKey(section.month)),
                      height: 20,
                    ),
                  _MonthHeader(label: section.label),
                  const SizedBox(height: 8),
                  for (var i = 0; i < section.weeks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    SizedBox(
                      height: 68,
                      child: _WeekRow(
                        key: ValueKey('calendar-week-${weekIndex + i}'),
                        days: section.weeks[i],
                        today: today,
                        selectedDay: widget.selectedDay,
                        palette: widget.palette,
                        eventsForDay: widget.eventsForDay,
                        onDayTap: widget.onDayTap,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip();

  @override
  Widget build(BuildContext context) {
    const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Text(
              labels[i],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8A8680),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF5A564E),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Color(0xFFD9D4CC), height: 1)),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    super.key,
    required this.days,
    required this.today,
    required this.palette,
    required this.eventsForDay,
    this.selectedDay,
    this.onDayTap,
  });

  final List<DateTime> days;
  final DateTime today;
  final DateTime? selectedDay;
  final HubMemberPalette palette;
  final List<EventModel> Function(DateTime day) eventsForDay;
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayCell(
              key: ValueKey(calendarScrollerDayKey(days[i])),
              day: days[i],
              events: eventsForDay(days[i]),
              isToday: DateUtils.isSameDay(days[i], today),
              isPast: days[i].isBefore(today),
              isSelected:
                  selectedDay != null &&
                  DateUtils.isSameDay(days[i], selectedDay),
              palette: palette,
              onTap: onDayTap == null ? null : () => onDayTap!(days[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.events,
    required this.isToday,
    required this.isPast,
    required this.isSelected,
    required this.palette,
    this.onTap,
  });

  final DateTime day;
  final List<EventModel> events;
  final bool isToday;
  final bool isPast;
  final bool isSelected;
  final HubMemberPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dateColor = isToday
        ? const Color(0xFF1C1914)
        : isPast
        ? const Color(0xFFB0AAA2)
        : const Color(0xFF1C1914);
    final fill = isSelected
        ? CalendarColors.shared.withValues(alpha: 0.14)
        : isToday
        ? const Color(0xFF1C1914).withValues(alpha: 0.06)
        : Colors.white;
    final border = isSelected
        ? CalendarColors.shared
        : isToday
        ? const Color(0xFF1C1914)
        : const Color(0xFFE6E1D8);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border,
              width: isToday || isSelected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Column(
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: dateColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const Spacer(),
                if (events.isEmpty)
                  const SizedBox(height: 8)
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final event in events.take(3))
                        CalendarGlanceDot(
                          style: CalendarColors.fromEvent(
                            event,
                            palette: palette,
                          ),
                          size: 6,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
