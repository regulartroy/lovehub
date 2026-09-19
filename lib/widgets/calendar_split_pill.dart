import 'package:flutter/material.dart';

import '../theme/calendar_colors.dart';

/// How dense a [CalendarSplitPill] should read at a glance.
enum CalendarSplitPillDensity { compact, regular, comfortable }

/// Dual-colour event chip: left ~1/3 person, right ~2/3 category.
///
/// Title and time sit on the category half with contrast-safe ink so the
/// same widget works on dark dashboard glass and the light calendar list.
class CalendarSplitPill extends StatelessWidget {
  const CalendarSplitPill({
    super.key,
    required this.style,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.density = CalendarSplitPillDensity.regular,
    this.margin,
  });

  final CalendarEventStyle style;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final CalendarSplitPillDensity density;
  final EdgeInsetsGeometry? margin;

  static const Key whoKey = Key('calendar-split-who');
  static const Key kindKey = Key('calendar-split-kind');

  bool get _compact => density == CalendarSplitPillDensity.compact;

  double get _radius {
    switch (density) {
      case CalendarSplitPillDensity.compact:
        return 8;
      case CalendarSplitPillDensity.regular:
        return 12;
      case CalendarSplitPillDensity.comfortable:
        return 14;
    }
  }

  EdgeInsets get _kindPadding {
    switch (density) {
      case CalendarSplitPillDensity.compact:
        return const EdgeInsets.fromLTRB(6, 3, 6, 3);
      case CalendarSplitPillDensity.regular:
        return const EdgeInsets.fromLTRB(10, 8, 10, 8);
      case CalendarSplitPillDensity.comfortable:
        return const EdgeInsets.fromLTRB(12, 10, 12, 10);
    }
  }

  double get _titleSize {
    switch (density) {
      case CalendarSplitPillDensity.compact:
        return 10.5;
      case CalendarSplitPillDensity.regular:
        return 15;
      case CalendarSplitPillDensity.comfortable:
        return 20;
    }
  }

  double get _subtitleSize {
    switch (density) {
      case CalendarSplitPillDensity.compact:
        return 9;
      case CalendarSplitPillDensity.regular:
        return 12;
      case CalendarSplitPillDensity.comfortable:
        return 14;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = style.inkOnKind;
    final showSubtitle = subtitle != null && subtitle!.isNotEmpty && !_compact;

    final kindContent = Padding(
      padding: _kindPadding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSubtitle)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.82),
                      fontSize: _subtitleSize,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: _titleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            IconTheme(
              data: IconThemeData(color: ink, size: _compact ? 12 : 16),
              child: trailing!,
            ),
          ],
        ],
      ),
    );

    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: ColoredBox(
                    key: whoKey,
                    color: style.who,
                    child: leading == null
                        ? const SizedBox.expand()
                        : Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _compact ? 2 : 6,
                              vertical: _compact ? 2 : 6,
                            ),
                            child: Center(child: leading),
                          ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    key: kindKey,
                    color: style.kind,
                    child: kindContent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (margin == null) return pill;
    return Padding(padding: margin!, child: pill);
  }
}

/// Category-primary heatmap / month marker with a tiny person accent ring.
class CalendarGlanceDot extends StatelessWidget {
  const CalendarGlanceDot({
    super.key,
    required this.style,
    this.faded = false,
    this.size = 6,
  });

  final CalendarEventStyle style;
  final bool faded;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = style.glanceDot.withValues(alpha: faded ? 0.45 : 0.95);
    final accent = style.who.withValues(alpha: faded ? 0.5 : 0.95);
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: size >= 7 ? 1.4 : 1.1),
      ),
    );
  }
}
