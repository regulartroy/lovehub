import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../theme/calendar_colors.dart';
import 'dashboard/dashboard_calendar_overview.dart';
import 'dashboard/dashboard_theme.dart';

/// Firestore / in-memory event as the map LOOK AHEAD already understands.
Map<String, dynamic> calendarLookAheadEventMap(EventModel event) {
  return {
    'id': event.id,
    'summary': event.summary,
    'start': event.start,
    'end': event.end,
    'allDay': event.allDay,
    'category': event.category,
    'assignedTo': event.assignedTo,
    if (event.notes != null) 'notes': event.notes,
    if (event.status != null) 'status': event.status,
  };
}

/// Calendar tab board: the dashboard LOOK AHEAD UI, scrolled forward without
/// the ~6 month cap, and back into past weeks. It opens on the current week.
///
/// Day cells, chips, dots, month headers, and the day-detail card all come
/// from [DashboardCalendarOverviewSlide]. This wrapper only supplies the
/// infinite window and the Calendar screen's event list.
class CalendarMonthScroller extends StatelessWidget {
  const CalendarMonthScroller({
    super.key,
    required this.now,
    required this.palette,
    required this.events,
    this.metrics,
    this.onDayTap,
    this.onConfirmTentative,
    this.onMarkTentative,
    this.initialWeekCount = 30,
    this.initialPastMonths = 12,
    this.initialScrollOffset = 0,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
  });

  final DateTime now;
  final HubMemberPalette palette;
  final List<Map<String, dynamic>> events;
  final DashboardMetrics? metrics;
  final ValueChanged<DateTime>? onDayTap;
  final Future<void> Function(Map<String, dynamic> event)? onConfirmTentative;
  final Future<void> Function(Map<String, dynamic> event)? onMarkTentative;
  final int initialWeekCount;

  /// Months of past weeks loaded above the current week at first; more load
  /// as the reader scrolls up.
  final int initialPastMonths;

  /// 0 opens on the current week; negative starts scrolled into the past.
  final double initialScrollOffset;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return DashboardCalendarOverviewSlide(
      metrics: metrics ?? DashboardMetrics(size),
      events: events,
      now: now,
      palette: palette,
      padding: padding,
      infiniteForward: true,
      initialForwardWeeks: initialWeekCount,
      infiniteBackward: true,
      initialPastMonths: initialPastMonths,
      initialScrollOffset: initialScrollOffset,
      onDayTap: onDayTap,
      onConfirmTentative: onConfirmTentative,
      onMarkTentative: onMarkTentative,
    );
  }
}
