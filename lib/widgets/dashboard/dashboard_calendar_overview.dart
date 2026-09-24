import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../event_import/imported_event.dart';
import '../../models/event_model.dart';
import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';
import '../tentative_event_confirm.dart';
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

/// Local hour before which an overnight continuation is not a new day.
///
/// Club nights that run 23:00 → 04:00 stay on the start day in overviews.
/// An end at exactly 06:00 still counts on that morning.
const int dashboardOverviewOvernightCutoffHour = 6;

/// Coloured chips drawn in a LOOK AHEAD day cell. A fifth event replaces
/// the chips with a row of coloured dots, one per event.
const int dashboardLookAheadMaxVisibleEvents = 4;

/// "4 events" — a plain count. Busy LOOK AHEAD days draw coloured dots
/// instead of this label.
String dashboardLookAheadEventCountLabel(int count) {
  if (count == 1) return '1 event';
  return '$count events';
}

/// Kitchen-tablet day box: weekday, date, and four compact chips.
const double dashboardLookAheadRowHeight = 184;

/// Phone day box. The header is smaller, and four chips still fit.
const double dashboardLookAheadCompactRowHeight = 168;

/// Whether [start]/[end] should place a chip on [day] in calendar overviews.
///
/// The start day always keeps the event. Later days keep it when the event
/// is all-day, or when it is still going at
/// [dashboardOverviewOvernightCutoffHour]. A timed event that only touches
/// the next calendar day because it ends strictly before that hour is left
/// off that morning. Stored times are not changed.
bool dashboardEventBelongsOnOverviewDay({
  required DateTime start,
  required DateTime end,
  required DateTime day,
  bool allDay = false,
}) {
  final checkDay = DateUtils.dateOnly(day);
  final startDay = DateUtils.dateOnly(start);
  final effectiveEnd = end.isBefore(start) ? start : end;
  final endDay = DateUtils.dateOnly(effectiveEnd);
  if (checkDay.isBefore(startDay) || checkDay.isAfter(endDay)) {
    return false;
  }
  if (allDay || DateUtils.isSameDay(checkDay, startDay)) return true;
  final cutoff = DateTime(
    checkDay.year,
    checkDay.month,
    checkDay.day,
    dashboardOverviewOvernightCutoffHour,
  );
  return !effectiveEnd.isBefore(cutoff);
}

/// Overview day membership for a Firestore event map. Same rule as
/// [dashboardEventBelongsOnOverviewDay].
bool dashboardEventOverlapsDay(Map<String, dynamic> data, DateTime day) {
  final startRaw = dashboardEventDateTime(data['start']);
  if (startRaw == null) return false;
  final endRaw = dashboardEventDateTime(data['end']) ?? startRaw;
  return dashboardEventBelongsOnOverviewDay(
    start: startRaw,
    end: endRaw,
    day: day,
    allDay: data['allDay'] == true,
  );
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
///
/// Every row is a full Monday–Sunday strip. Days from the neighbouring month
/// stay in that row, the way a printed calendar pads the week.
class DashboardLookAheadMonthSection {
  DashboardLookAheadMonthSection({
    required this.month,
    required this.label,
    required List<List<DateTime>> weeks,
  }) : weeks = List<List<DateTime>>.from(weeks);

  /// First day of the labeled calendar month.
  final DateTime month;
  final String label;

  /// Continuous Monday–Sunday rows. A row may include days from the month
  /// before or after [month].
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
/// card listing that day's events. Tentative shifts in that card offer
/// confirm. Confirmed shifts can be marked tentative from the chip.
/// [onDayTap] is fired as well so the host screen can keep showing
/// play–pause controls on the same touch.
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
    this.onConfirmTentative,
    this.onMarkTentative,
    this.infiniteForward = false,
    this.initialForwardWeeks = 30,
    this.boardLabel,
  });

  /// How many extra Monday-rows to append when an infinite board nears its end.
  static const int infiniteChunkWeeks = 26;

  /// About twenty years. Far enough that the Calendar tab does not feel capped.
  static const int infiniteMaxWeeks = 52 * 20;

  final DashboardMetrics metrics;
  final List<Map<String, dynamic>> events;
  final DateTime now;
  final List<Map<String, dynamic>> members;
  final HubMemberPalette? palette;
  final EdgeInsets? padding;

  /// Calendar tab: keep the same board, and grow it as the reader scrolls.
  /// Dashboard LOOK AHEAD stays on the ~6 month horizon when this is false.
  final bool infiniteForward;

  /// First window when [infiniteForward] is set. Ignored on the dashboard.
  final int initialForwardWeeks;

  /// Inner glass-card label. Defaults to "NEXT 6 MONTHS" or "ONWARD".
  final String? boardLabel;

  /// Invoked when a day cell is tapped, in addition to opening day detail.
  final ValueChanged<DateTime>? onDayTap;

  /// Invoked when the day-detail card is dismissed.
  final VoidCallback? onCloseDayDetail;

  /// Writes `status: confirmed` for a tentative shift. The chip paints solid
  /// immediately; a failed future restores the question mark.
  final Future<void> Function(Map<String, dynamic> event)? onConfirmTentative;

  /// Writes `status: tentative` for a confirmed shift. The chip mutes and
  /// shows ? immediately; a failed future restores the solid chip.
  final Future<void> Function(Map<String, dynamic> event)? onMarkTentative;

  HubMemberPalette get resolvedPalette =>
      palette ?? HubMemberPalette.fromMembers(members);

  @override
  State<DashboardCalendarOverviewSlide> createState() =>
      _DashboardCalendarOverviewSlideState();
}

class _DashboardCalendarOverviewSlideState
    extends State<DashboardCalendarOverviewSlide> {
  DateTime? _selectedDay;
  final Set<String> _locallyConfirmed = {};
  final Set<String> _locallyTentative = {};
  final Set<String> _dismissedConfirm = {};
  String? _confirmingId;
  late int _forwardWeeks;
  bool _expandScheduled = false;

  int _resolvedForwardWeeks(DashboardCalendarOverviewSlide source) {
    if (!source.infiniteForward) {
      return dashboardLookAheadWeekCount(source.now);
    }
    return source.initialForwardWeeks.clamp(
      8,
      DashboardCalendarOverviewSlide.infiniteMaxWeeks,
    );
  }

  @override
  void initState() {
    super.initState();
    _forwardWeeks = _resolvedForwardWeeks(widget);
  }

  @override
  void didUpdateWidget(covariant DashboardCalendarOverviewSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mondayChanged =
        dashboardMondayOf(oldWidget.now) != dashboardMondayOf(widget.now);
    if (!widget.infiniteForward ||
        mondayChanged ||
        oldWidget.infiniteForward != widget.infiniteForward) {
      _forwardWeeks = _resolvedForwardWeeks(widget);
    }
  }

  void _maybeExpandForward() {
    if (!widget.infiniteForward || _expandScheduled) return;
    if (_forwardWeeks >= DashboardCalendarOverviewSlide.infiniteMaxWeeks) {
      return;
    }
    _expandScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expandScheduled = false;
      if (!mounted) return;
      if (!widget.infiniteForward) return;
      setState(() {
        _forwardWeeks =
            (_forwardWeeks + DashboardCalendarOverviewSlide.infiniteChunkWeeks)
                .clamp(8, DashboardCalendarOverviewSlide.infiniteMaxWeeks);
      });
    });
  }

  void _handleDayTap(DateTime day) {
    final date = DateUtils.dateOnly(day);
    setState(() => _selectedDay = date);
    widget.onDayTap?.call(date);
  }

  void _closeDayDetail() {
    if (_selectedDay == null) return;
    setState(() {
      _selectedDay = null;
      _dismissedConfirm.clear();
    });
    widget.onCloseDayDetail?.call();
  }

  String? _eventId(Map<String, dynamic> event) {
    final raw = event['id'];
    if (raw is! String) return null;
    final id = raw.trim();
    return id.isEmpty ? null : id;
  }

  List<Map<String, dynamic>> _presentedEvents() {
    _locallyConfirmed.removeWhere((id) {
      for (final event in widget.events) {
        if (_eventId(event) == id && !isTentativeEventStatus(event['status'])) {
          return true;
        }
      }
      return false;
    });
    _locallyTentative.removeWhere((id) {
      for (final event in widget.events) {
        if (_eventId(event) == id && isTentativeEventStatus(event['status'])) {
          return true;
        }
      }
      return false;
    });
    return [
      for (final event in widget.events)
        if (_locallyTentative.contains(_eventId(event)))
          {...event, 'status': eventStatusTentative}
        else if (_locallyConfirmed.contains(_eventId(event)))
          {...event, 'status': eventStatusConfirmed}
        else
          event,
    ];
  }

  Future<void> _confirmTentative(Map<String, dynamic> event) async {
    final id = _eventId(event);
    final confirm = widget.onConfirmTentative;
    if (id == null || confirm == null || _confirmingId != null) return;
    setState(() {
      _confirmingId = id;
      _locallyConfirmed.add(id);
      _locallyTentative.remove(id);
    });
    try {
      await confirm(event);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locallyConfirmed.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't confirm that shift. It's still tentative."),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmingId = null);
    }
  }

  Future<void> _markTentative(Map<String, dynamic> event) async {
    final id = _eventId(event);
    final mark = widget.onMarkTentative;
    if (id == null || mark == null) {
      throw StateError('This shift cannot be marked tentative.');
    }
    setState(() {
      _locallyTentative.add(id);
      _locallyConfirmed.remove(id);
      _dismissedConfirm.add(id);
    });
    try {
      await mark(event);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locallyTentative.remove(id);
        _dismissedConfirm.remove(id);
      });
      rethrow;
    }
  }

  void _offerMarkTentative(Map<String, dynamic> event) {
    final id = _eventId(event);
    if (id == null) return;
    final notes = event['notes'];
    showMarkEventTentativeSheet(
      context: context,
      eventId: id,
      title: dashboardGlanceTitle(event),
      subtitle: dashboardGlanceTimeLabel(event),
      notes: notes is String ? notes : null,
      onMarkTentative: () => _markTentative(event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _presentedEvents();
    final today = DateUtils.dateOnly(widget.now);
    final weeks = dashboardLookAheadWeeks(today, weekCount: _forwardWeeks);
    final horizonEnd = weeks.last.last;
    final rangeStart = weeks.first.first;
    final boardLabel =
        widget.boardLabel ??
        (widget.infiniteForward ? 'ONWARD' : 'NEXT 6 MONTHS');
    final hasUpcoming = events.any((event) {
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
        : dashboardEventsOnDay(events, _selectedDay!);

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
                trailing: widget.infiniteForward
                    ? null
                    : _RangeChip(
                        label: dashboardCompactDayRange(today, horizonEnd),
                      ),
              ),
              SizedBox(height: widget.metrics.isCompact ? 12 : 16),
              Expanded(
                child: _LookAheadWeekBoard(
                  metrics: widget.metrics,
                  weeks: weeks,
                  events: events,
                  today: today,
                  selectedDay: _selectedDay,
                  rangeLabel: widget.infiniteForward
                      ? null
                      : dashboardCompactDayRange(today, horizonEnd),
                  boardLabel: boardLabel,
                  emptyHint: hasUpcoming
                      ? null
                      : 'Quiet stretch — add plans from Calendar',
                  palette: whoPalette,
                  onDayTap: _handleDayTap,
                  onNearEnd: widget.infiniteForward
                      ? _maybeExpandForward
                      : null,
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
              onConfirmTentative: widget.onConfirmTentative == null
                  ? null
                  : _confirmTentative,
              onRequestMarkTentative: widget.onMarkTentative == null
                  ? null
                  : _offerMarkTentative,
              dismissedConfirmIds: _dismissedConfirm,
              confirmingId: _confirmingId,
              onKeepTentative: (id) =>
                  setState(() => _dismissedConfirm.add(id)),
              onReopenTentativeConfirm: (id) =>
                  setState(() => _dismissedConfirm.remove(id)),
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
    required this.boardLabel,
    required this.palette,
    required this.onDayTap,
    this.rangeLabel,
    this.selectedDay,
    this.emptyHint,
    this.onNearEnd,
  });

  final DashboardMetrics metrics;
  final List<List<DateTime>> weeks;
  final List<Map<String, dynamic>> events;
  final DateTime today;
  final DateTime? selectedDay;
  final String? rangeLabel;
  final String boardLabel;
  final HubMemberPalette palette;
  final String? emptyHint;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback? onNearEnd;

  @override
  Widget build(BuildContext context) {
    final rowGap = metrics.isCompact ? 8.0 : 10.0;
    // Modest extra air between months so the board reads as sections, not one
    // continuous grid. Tight enough for a wall tablet.
    final monthGap = metrics.isCompact ? 16.0 : 22.0;
    // Tall enough for the weekday, the date, and four coloured chips.
    // A shorter box was collapsing busy days to a count.
    final minRow = metrics.isCompact
        ? dashboardLookAheadCompactRowHeight
        : dashboardLookAheadRowHeight;
    final sections = dashboardLookAheadMonthSections(weeks, now: today);

    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(metrics.isCompact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(
            text: boardLabel,
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
                if (sectionIndex >= sections.length - 1) {
                  onNearEnd?.call();
                }
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
    // 1–4 events stay as chips. Five or more become coloured dots so a
    // busy day still reads as full, without a plain "N events" count.
    final showDots = events.length > dashboardLookAheadMaxVisibleEvents;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DashboardTheme.radiusMd),
        child: DecoratedBox(
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
                        : showDots
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: LookAheadEventDots(
                              events: events,
                              palette: palette,
                              muted: isPast,
                            ),
                          )
                        : Column(
                            children: [
                              for (final event in events)
                                _EventChip(
                                  event: event,
                                  compact: metrics.isCompact,
                                  palette: palette,
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
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

/// Compact coloured dots for a LOOK AHEAD day with more than
/// [dashboardLookAheadMaxVisibleEvents] events.
///
/// One dot per event, in the same who/kind colours as the chips. When the
/// row cannot hold every dot, the rest collapse to a small "+N" cue.
class LookAheadEventDots extends StatelessWidget {
  const LookAheadEventDots({
    super.key,
    required this.events,
    required this.palette,
    this.muted = false,
  });

  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;

  /// Past days fade the dots the same way the date label fades.
  final bool muted;

  static const Key rowKey = Key('look-ahead-event-dots');
  static const Key overflowKey = Key('look-ahead-event-dots-overflow');

  static const double dotSize = 8;

  /// [CalendarGlanceDot] adds 1px of horizontal margin on each side.
  static const double dotSlot = dotSize + 2;

  /// Room for a "+NN" cue, its padding, and a little slack inside the cell.
  static double _overflowCueWidth(int hidden) => hidden >= 10 ? 36 : 28;

  @override
  Widget build(BuildContext context) {
    final styles = [
      for (final event in events)
        CalendarColors.fromMap(event, palette: palette),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var visible = styles.length;
        if (maxWidth.isFinite && styles.isNotEmpty) {
          while (visible > 0) {
            final hidden = styles.length - visible;
            final cue = hidden == 0 ? 0.0 : _overflowCueWidth(hidden);
            if (visible * dotSlot + cue <= maxWidth + 0.5) break;
            visible--;
          }
        }
        final hidden = styles.length - visible;
        return Row(
          key: rowKey,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < visible; i++)
              CalendarGlanceDot(style: styles[i], size: dotSize, faded: muted),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  '+$hidden',
                  key: overflowKey,
                  style: TextStyle(
                    color: muted
                        ? DashboardTheme.inkFaint
                        : DashboardTheme.inkMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
          ],
        );
      },
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
    this.onConfirmTentative,
    this.onRequestMarkTentative,
    this.dismissedConfirmIds = const {},
    this.confirmingId,
    this.onKeepTentative,
    this.onReopenTentativeConfirm,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final bool isToday;
  final VoidCallback onClose;
  final Future<void> Function(Map<String, dynamic> event)? onConfirmTentative;
  final void Function(Map<String, dynamic> event)? onRequestMarkTentative;
  final Set<String> dismissedConfirmIds;
  final String? confirmingId;
  final ValueChanged<String>? onKeepTentative;
  final ValueChanged<String>? onReopenTentativeConfirm;

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
                  onConfirmTentative: onConfirmTentative,
                  onRequestMarkTentative: onRequestMarkTentative,
                  dismissedConfirmIds: dismissedConfirmIds,
                  confirmingId: confirmingId,
                  onKeepTentative: onKeepTentative,
                  onReopenTentativeConfirm: onReopenTentativeConfirm,
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
    this.onConfirmTentative,
    this.onRequestMarkTentative,
    this.dismissedConfirmIds = const {},
    this.confirmingId,
    this.onKeepTentative,
    this.onReopenTentativeConfirm,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final bool isToday;
  final VoidCallback onClose;
  final Future<void> Function(Map<String, dynamic> event)? onConfirmTentative;
  final void Function(Map<String, dynamic> event)? onRequestMarkTentative;
  final Set<String> dismissedConfirmIds;
  final String? confirmingId;
  final ValueChanged<String>? onKeepTentative;
  final ValueChanged<String>? onReopenTentativeConfirm;

  String? _eventId(Map<String, dynamic> event) {
    final raw = event['id'];
    if (raw is! String) return null;
    final id = raw.trim();
    return id.isEmpty ? null : id;
  }

  VoidCallback? _chipTap(
    Map<String, dynamic> event,
    String? id,
    CalendarEventStyle style,
  ) {
    if (id == null) return null;
    if (style.tentative) {
      if (dismissedConfirmIds.contains(id)) {
        return () => onReopenTentativeConfirm?.call(id);
      }
      return null;
    }
    final request = onRequestMarkTentative;
    if (request == null) return null;
    if (!canMarkEventTentativeFromChip(eventId: id, status: event['status'])) {
      return null;
    }
    return () => request(event);
  }

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
              final id = _eventId(event);
              final offerConfirm =
                  onConfirmTentative != null &&
                  id != null &&
                  style.tentative &&
                  !dismissedConfirmIds.contains(id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CalendarSplitPill(
                    style: style,
                    title: dashboardGlanceTitle(event),
                    subtitle: dashboardGlanceTimeLabel(event),
                    density: metrics.isCompact
                        ? CalendarSplitPillDensity.regular
                        : CalendarSplitPillDensity.comfortable,
                    onTap: _chipTap(event, id, style),
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
                  ),
                  if (id != null && offerConfirm) ...[
                    const SizedBox(height: 8),
                    TentativeEventActions(
                      eventId: id,
                      dark: true,
                      busy: confirmingId == id,
                      onConfirm: () => onConfirmTentative!(event),
                      onKeep: () => onKeepTentative?.call(id),
                    ),
                  ],
                ],
              );
            },
          );

    final offersConfirm =
        onConfirmTentative != null &&
        events.any((event) {
          final id = _eventId(event);
          return id != null &&
              isTentativeEventStatus(event['status']) &&
              !dismissedConfirmIds.contains(id);
        });
    final desired = events.isEmpty
        ? (metrics.isCompact ? 220.0 : 210.0)
        : (metrics.isCompact ? 460.0 : 440.0) + (offersConfirm ? 108.0 : 0.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final height = maxHeight.isFinite && desired > maxHeight
            ? maxHeight
            : desired;
        return SizedBox(
          width: metrics.isCompact ? double.infinity : 560,
          height: height,
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
      },
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
