import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';

/// One event as shown in a TODAY / TOMORROW section of the schedule slide.
class DashboardDayItem {
  const DashboardDayItem({
    required this.style,
    required this.title,
    required this.timeLabel,
    this.start,
    this.allDay = false,
    this.birthday = false,
    this.avatar,
    this.icon,
  });

  final CalendarEventStyle style;
  final String title;
  final String timeLabel;

  /// Start within the shown day (clipped to midnight for carry-overs).
  /// Drives the loose left-to-right placement of timed tiles.
  final DateTime? start;

  /// Whole-day items render as a full-width strip above the tiles.
  final bool allDay;
  final bool birthday;
  final Widget? avatar;
  final IconData? icon;
}

/// TODAY / TOMORROW body: all-day strips across the top, then timed events
/// as tiles packed from the left edge in start order, wrapping onto more rows when a day is busy.
class DashboardDayTiles extends StatelessWidget {
  const DashboardDayTiles({super.key, required this.items, this.large = true});

  final List<DashboardDayItem> items;
  final bool large;

  static const Key stripKey = Key('dashboard-day-strip');
  static const Key tileKey = Key('dashboard-day-tile');
  static const Key cakeKey = Key('dashboard-day-cake');

  /// Columns that fit in [width] with tiles at least [minTile] wide.
  static int columnsFor(double width, double minTile, double gap) =>
      math.max(1, math.min(4, ((width + gap) / (minTile + gap)).floor()));

  @override
  Widget build(BuildContext context) {
    final strips = items.where((e) => e.allDay).toList();
    final timed = items.where((e) => !e.allDay).toList();
    final gap = large ? 12.0 : 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in strips)
          CalendarSplitPill(
            key: stripKey,
            style: e.style,
            title: e.title,
            subtitle: e.birthday ? null : e.timeLabel,
            fitSubtitle: true,
            tentativeMarkInline: true,
            density: large
                ? CalendarSplitPillDensity.comfortable
                : CalendarSplitPillDensity.regular,
            margin: EdgeInsets.only(bottom: gap),
            leading: e.avatar,
            trailing: e.birthday
                ? Icon(Icons.cake_rounded, key: cakeKey, size: large ? 22 : 18)
                : (e.icon == null ? null : Icon(e.icon, size: large ? 20 : 16)),
          ),
        if (timed.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = columnsFor(
                constraints.maxWidth,
                large ? 170 : 140,
                gap,
              );
              final rows = <List<DashboardDayItem>>[];
              for (var i = 0; i < timed.length; i += cols) {
                rows.add(timed.sublist(i, math.min(i + cols, timed.length)));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows)
                    Padding(
                      padding: EdgeInsets.only(bottom: gap),
                      child: _row(row, cols, gap),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _row(List<DashboardDayItem> row, int cols, double gap) {
    // Left-aligned packing: tiles fill from the left in start order.
    final cells = List<Widget>.generate(
      cols,
      (c) => c < row.length
          ? _DayTile(item: row[c], large: large)
          : const SizedBox(),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var c = 0; c < cols; c++) ...[
            if (c > 0) SizedBox(width: gap),
            Expanded(child: cells[c]),
          ],
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.item, required this.large});

  final DashboardDayItem item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = item.style;
    final radius = BorderRadius.circular(large ? 14 : 12);
    final kindInk = style.inkOnKind;
    final whoInk = style.inkOnWho;
    return Container(
      key: DashboardDayTiles.tileKey,
      foregroundDecoration: style.tentative
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: CalendarColors.darkInk.withValues(alpha: 0.55),
                width: 1.4,
              ),
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: style.who,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 7, 10, 7),
                child: Row(
                  children: [
                    ?item.avatar,
                    if (item.avatar != null) const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          item.timeLabel,
                          maxLines: 1,
                          style: TextStyle(
                            color: whoInk,
                            fontSize: large ? 16 : 13,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: style.kind,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (style.tentative) ...[
                        _mark(),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kindInk,
                            fontSize: large ? 19 : 15,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ),
                      if (item.icon != null) ...[
                        const SizedBox(width: 4),
                        Icon(item.icon, color: kindInk, size: large ? 18 : 15),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mark() => Container(
    key: CalendarSplitPill.tentativeMarkKey,
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: CalendarColors.darkInk,
      shape: BoxShape.circle,
    ),
    child: const Text(
      '?',
      semanticsLabel: 'Tentative',
      style: TextStyle(
        color: CalendarColors.lightInk,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}
