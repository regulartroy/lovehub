import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';
import '../recipe_picture.dart';

/// Label for a planned meal on the Today / Tomorrow panel.
String dashboardMealLabel(DateTime day, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final date = DateUtils.dateOnly(day);
  if (date == today) return "Tonight's dinner";
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  if (date == tomorrow) return "Tomorrow's dinner";
  return 'Dinner';
}

/// One event as shown in a TODAY / TOMORROW section of the schedule slide.
class DashboardDayItem {
  const DashboardDayItem({
    required this.style,
    required this.title,
    required this.timeLabel,
    this.start,
    this.allDay = false,
    this.birthday = false,
    this.meal = false,
    this.mealLabel,
    this.imageUrl,
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

  /// Planned meal (recipe or custom). Rendered as its own dinner strip,
  /// not mixed into the timed tile grid, and without a time range.
  final bool meal;

  /// e.g. "Tonight's dinner" / "Tomorrow's dinner".
  final String? mealLabel;

  /// Recipe picture, when the meal is linked to a cookbook entry that has one.
  final String? imageUrl;
  final Widget? avatar;
  final IconData? icon;
}

/// TODAY / TOMORROW body: all-day strips across the top, then planned meals
/// as a featured dinner strip, then timed events as tiles packed from the
/// left edge in start order, wrapping onto more rows when a day is busy.
class DashboardDayTiles extends StatelessWidget {
  const DashboardDayTiles({super.key, required this.items, this.large = true});

  final List<DashboardDayItem> items;
  final bool large;

  static const Key stripKey = Key('dashboard-day-strip');
  static const Key tileKey = Key('dashboard-day-tile');
  static const Key cakeKey = Key('dashboard-day-cake');
  static const Key mealKey = Key('dashboard-day-meal');
  static const Key mealLabelKey = Key('dashboard-day-meal-label');
  static const Key mealImageKey = Key('dashboard-day-meal-image');

  /// Columns that fit in [width] with tiles at least [minTile] wide.
  static int columnsFor(double width, double minTile, double gap) =>
      math.max(1, math.min(4, ((width + gap) / (minTile + gap)).floor()));

  @override
  Widget build(BuildContext context) {
    final strips = items.where((e) => e.allDay && !e.meal).toList();
    final meals = items.where((e) => e.meal).toList();
    final timed = items.where((e) => !e.allDay && !e.meal).toList();
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
        for (final e in meals)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: _MealStrip(item: e, large: large),
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

/// Warm, full-width dinner strip: thumbnail, meal label, recipe name, no time.
class _MealStrip extends StatelessWidget {
  const _MealStrip({required this.item, required this.large});

  final DashboardDayItem item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final fill = item.style.special ?? CalendarColors.meal;
    final ink = CalendarColors.inkOn(fill);
    final radius = BorderRadius.circular(large ? 14 : 12);
    final thumb = large ? 96.0 : 76.0;
    final label = item.mealLabel ?? 'Dinner';
    return Container(
      key: DashboardDayTiles.mealKey,
      height: thumb,
      foregroundDecoration: item.style.tentative
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: CalendarColors.darkInk.withValues(alpha: 0.55),
                width: 1.4,
              ),
            )
          : null,
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: thumb,
            child: _MealThumb(
              imageUrl: item.imageUrl,
              size: large ? 36 : 30,
              ink: ink,
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                large ? 16 : 12,
                large ? 12 : 10,
                large ? 14 : 10,
                large ? 12 : 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (item.style.tentative)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _mealMark(),
                    ),
                  Text(
                    label.toUpperCase(),
                    key: DashboardDayTiles.mealLabelKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.82),
                      fontSize: large ? 12 : 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: large ? 5 : 3),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: large ? 20 : 16,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealMark() => Container(
    key: CalendarSplitPill.tentativeMarkKey,
    width: 18,
    height: 18,
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
        fontSize: 12,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

class _MealThumb extends StatelessWidget {
  const _MealThumb({
    required this.imageUrl,
    required this.size,
    required this.ink,
  });

  final String? imageUrl;
  final double size;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return RecipeImage(
        key: DashboardDayTiles.mealImageKey,
        imageUrl: url,
        iconSize: size,
      );
    }
    return ColoredBox(
      key: DashboardDayTiles.mealImageKey,
      color: Colors.black.withValues(alpha: 0.18),
      child: Icon(Icons.restaurant_menu, color: ink, size: size),
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
