import 'dart:async';

import 'package:flutter/material.dart';
import 'voice_spike_gallery.dart';
import 'package:lovehub/models/quote_model.dart';
import 'package:lovehub/repositories/quote_repository.dart';
import 'package:lovehub/screens/dashboard/quotes_screen.dart';
import 'package:lovehub/services/home_feed_logic.dart';
import 'package:lovehub/widgets/home_feed/home_feed_view.dart';
import 'package:lovehub/services/dashboard_voice.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/quote_composer.dart';
import 'package:lovehub/widgets/calendar_month_scroller.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_birthday_timeline.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_chrome.dart';
import 'package:lovehub/widgets/dashboard/dashboard_day_tiles.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

/// Local visual gallery for dashboard chrome. Not used in production.
void main() {
  runApp(const DashboardGalleryApp());
}

class DashboardGalleryApp extends StatelessWidget {
  const DashboardGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const DashboardGalleryPage(),
    );
  }
}

class DashboardGalleryPage extends StatelessWidget {
  const DashboardGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final metrics = DashboardMetrics(size);
    const lookAheadOnly = bool.fromEnvironment('LOOK_AHEAD_ONLY');
    const calendarBoardOnly = bool.fromEnvironment('CALENDAR_BOARD_ONLY');
    const voiceSpike = bool.fromEnvironment('VOICE_SPIKE');

    if (voiceSpike) {
      return const VoiceSpikeGallery();
    }

    const birthdaysOnly = bool.fromEnvironment('BIRTHDAYS_ONLY');
    if (birthdaysOnly) {
      // BIRTHDAYS_COUNT=0|1|n picks how many sample birthdays to show.
      const count = int.fromEnvironment('BIRTHDAYS_COUNT', defaultValue: 8);
      final today = DateTime(2026, 10, 1);
      return Scaffold(
        backgroundColor: BirthdayTimelineColors.canvas,
        body: DashboardBirthdaysSlide(
          metrics: metrics,
          today: today,
          birthdays: galleryBirthdays(today).take(count).toList(),
        ),
      );
    }

    const feedOnly = bool.fromEnvironment('FEED_ONLY');
    if (feedOnly) {
      return const _FeedGallery();
    }

    const quotesOnly = bool.fromEnvironment('QUOTES_ONLY');
    if (quotesOnly) {
      return const _QuotesGallery();
    }

    const choresOnly = bool.fromEnvironment('CHORES_ONLY');
    if (choresOnly) {
      return Scaffold(
        backgroundColor: DashboardTheme.canvas,
        body: _choresPreview(metrics),
      );
    }

    const shoppingOnly = bool.fromEnvironment('SHOPPING_ONLY');
    if (shoppingOnly) {
      return Scaffold(
        backgroundColor: DashboardTheme.canvas,
        body: _shoppingPreview(metrics),
      );
    }

    const scheduleOnly = bool.fromEnvironment('SCHEDULE_ONLY');
    if (scheduleOnly) {
      return Scaffold(
        backgroundColor: DashboardTheme.canvas,
        body: _scheduleWeekPreview(metrics),
      );
    }

    if (lookAheadOnly) {
      return Scaffold(
        backgroundColor: DashboardTheme.canvas,
        body: _lookAheadPreview(metrics),
      );
    }

    if (calendarBoardOnly) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F3EE),
        body: SafeArea(child: _calendarBoardPreview()),
      );
    }

    if (lookAheadOnly) {
      return Scaffold(
        backgroundColor: DashboardTheme.canvas,
        body: _lookAheadPreview(metrics),
      );
    }

    return Scaffold(
      backgroundColor: DashboardTheme.canvas,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.slidePadH,
            vertical: 24,
          ),
          children: [
            Text(
              'Dashboard gallery',
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.titleSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              metrics.isCompact
                  ? 'Phone layout — compact type and single column'
                  : 'Tablet layout — roomier type and split schedule',
              style: const TextStyle(
                color: DashboardTheme.inkMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 28),
            _palettePanel(metrics),
            const SizedBox(height: 20),
            _splitPillPanel(metrics),
            const SizedBox(height: 20),
            _calendarListPreview(),
            const SizedBox(height: 20),
            _panel(height: 280, child: const DashboardLoadingView()),
            const SizedBox(height: 20),
            _panel(
              height: 360,
              child: DashboardEmptyState(
                icon: Icons.favorite_outline_rounded,
                title: 'No hub selected',
                message:
                    'Open a shared hub from settings, then come back to this wall view.',
                action: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DashboardTheme.accent,
                  ),
                  onPressed: () {},
                  child: const Text('Back to LoveHub'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _panel(
              height: 360,
              child: DashboardEmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Dashboard needs a moment',
                message: 'Could not load your home dashboard.',
                action: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DashboardTheme.accent,
                  ),
                  onPressed: () {},
                  child: const Text('Try again'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _panel(
              height: metrics.isCompact ? 520 : 420,
              child: _schedulePreview(metrics),
            ),
            const SizedBox(height: 20),
            _panel(
              height: metrics.isCompact ? 820 : 720,
              child: _lookAheadPreview(metrics),
            ),
            const SizedBox(height: 20),
            _panel(
              height: metrics.isCompact ? 780 : 680,
              child: _lookAheadEmptyPreview(metrics),
            ),
            const SizedBox(height: 20),
            _calendarBoardPanel(metrics),
            const SizedBox(height: 20),
            _panel(
              height: 320,
              child: const DashboardEmptyState(
                icon: Icons.wb_cloudy_outlined,
                tint: DashboardTheme.weather,
                title: 'Forecast is taking a pause.',
                message: 'Add a city, or try again in a moment.',
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  static const _galleryMembers = [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ];

  Widget _palettePanel(DashboardMetrics metrics) {
    const swatches = [
      (CalendarColors.tom, 'Tom', 'clear blue'),
      (CalendarColors.maria, 'Maria', 'kitchen yellow'),
      (CalendarColors.shared, 'Shared', 'pink / magenta'),
      (CalendarColors.work, 'Work', 'stone grey'),
      (CalendarColors.personal, 'Leisure', 'green'),
      (CalendarColors.birthday, 'Birthdays', 'purple'),
    ];

    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendar colours',
            style: TextStyle(
              color: Colors.white,
              fontSize: metrics.bodySize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Split pill: left who, right category. Maria yellow ≠ Shared pink. Leisure is green.',
            style: TextStyle(color: DashboardTheme.inkMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final swatch in swatches)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: swatch.$1,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          swatch.$2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          swatch.$3,
                          style: const TextStyle(
                            color: DashboardTheme.inkFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({required double height, required Widget child}) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
        child: ColoredBox(color: DashboardTheme.canvas, child: child),
      ),
    );
  }

  /// Mirrors the live SCHEDULE slide (no section header, 60/40 split on
  /// tablet, one 7-day column on phone) with time ranges.
  Widget _scheduleWeekPreview(DashboardMetrics metrics) {
    final today = DateTime(2026, 10, 2);
    DateTime at(int day, int h, [int m = 0]) =>
        DateTime(today.year, today.month, today.day + day, h, m);
    Map<String, dynamic> ev(
      String title,
      Color who,
      Color kind,
      DateTime start, {
      DateTime? end,
      bool allDay = false,
      Color? special,
      IconData? icon,
    }) => {
      'title': title,
      'style': CalendarEventStyle(who: who, kind: kind, special: special),
      'start': start,
      if (end != null) 'end': end,
      'allDay': allDay,
      if (icon != null) 'icon': icon,
    };

    final tentative = CalendarEventStyle(
      who: CalendarColors.mute(CalendarColors.tom),
      kind: CalendarColors.mute(CalendarColors.work),
      tentative: true,
    );
    final days = <List<Map<String, dynamic>>>[
      [
        ev(
          'School run',
          CalendarColors.maria,
          CalendarColors.personal,
          at(0, 8, 15),
          end: at(0, 8, 45),
        ),
        ev(
          'Gym',
          CalendarColors.tom,
          CalendarColors.personal,
          at(0, 9, 30),
          end: at(0, 10, 30),
        ),
        ev(
          'Standup',
          CalendarColors.tom,
          CalendarColors.work,
          at(0, 11),
          end: at(0, 11, 30),
        ),
        ev(
          'Lunch with Mum',
          CalendarColors.shared,
          CalendarColors.personal,
          at(0, 13),
          end: at(0, 14),
          icon: Icons.restaurant,
        ),
        ev(
          'Dentist',
          CalendarColors.maria,
          CalendarColors.personal,
          at(0, 16, 15),
          end: at(0, 16, 45),
        ),
        ev(
          'Dinner with Sam & Alex',
          CalendarColors.shared,
          CalendarColors.personal,
          at(0, 19),
          end: at(0, 23),
          icon: Icons.restaurant,
        ),
        ev(
          'Gig at Concorde 2',
          CalendarColors.tom,
          CalendarColors.work,
          at(0, 22),
          end: at(1, 3),
        ),
      ],
      [
        ev(
          "Jordan's birthday",
          CalendarColors.shared,
          CalendarColors.birthday,
          at(1, 0),
          allDay: true,
          special: CalendarColors.birthday,
          icon: Icons.cake_rounded,
        ),
        ev(
          'General checkup',
          CalendarColors.maria,
          CalendarColors.personal,
          at(1, 10),
          end: at(1, 10, 30),
        ),
        ev(
          'C2 shift',
          CalendarColors.tom,
          CalendarColors.work,
          at(1, 17),
          end: at(1, 23, 30),
        ),
      ],
      [
        ev(
          'Weekend in Cornwall (Day 1/3)',
          CalendarColors.shared,
          CalendarColors.personal,
          at(2, 18),
          end: at(4, 16),
        ),
        {
          ...ev(
            'Concorde shift',
            CalendarColors.tom,
            CalendarColors.work,
            at(2, 12),
            end: at(2, 18),
          ),
          'style': tentative,
        },
      ],
      [
        ev(
          'Team offsite planning session',
          CalendarColors.tom,
          CalendarColors.work,
          at(3, 9),
          end: at(3, 17, 30),
        ),
      ],
      [],
      [
        ev(
          'Late shift',
          CalendarColors.maria,
          CalendarColors.work,
          at(5, 14),
          end: at(5, 22),
        ),
      ],
      [],
    ];

    Widget box(int from, int count, bool large) {
      return DashboardGlassCard(
        tint: DashboardTheme.schedule,
        padding: EdgeInsets.all(large ? 28 : 20),
        child: ListView(
          children: [
            for (var index = 0; index < count; index++)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : (large ? 24 : 18),
                      bottom: 10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          from + index == 0
                              ? 'TODAY'
                              : from + index == 1
                              ? 'TOMORROW'
                              : _galleryDayLabel(
                                  today.add(Duration(days: from + index)),
                                ),
                          style: TextStyle(
                            color: from + index == 0
                                ? Colors.greenAccent
                                : const Color(0xFF8FB0C8),
                            fontSize: large ? 22 : 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Divider(
                            color: DashboardTheme.fade(
                              from + index == 0
                                  ? Colors.greenAccent
                                  : Colors.white,
                              0.2,
                            ),
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (days[from + index].isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Nothing planned',
                        style: TextStyle(
                          color: DashboardTheme.inkFaint,
                          fontSize: large ? 20 : 17,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else if (large)
                    DashboardDayTiles(
                      items: [
                        for (final e in days[from + index])
                          DashboardDayItem(
                            style: e['style'] as CalendarEventStyle,
                            title: e['title'] as String,
                            timeLabel: dashboardEventTimeRangeLabel(e),
                            start: e['start'] as DateTime,
                            allDay: e['allDay'] == true,
                            birthday: e['icon'] == Icons.cake_rounded,
                            avatar: const CircleAvatar(
                              radius: 13,
                              backgroundColor: Colors.white24,
                            ),
                            icon: e['icon'] == Icons.cake_rounded
                                ? null
                                : e['icon'] as IconData?,
                          ),
                      ],
                    )
                  else
                    for (final e in days[from + index])
                      CalendarSplitPill(
                        style: e['style'] as CalendarEventStyle,
                        title: e['title'] as String,
                        subtitle: dashboardEventTimeRangeLabel(e),
                        fitSubtitle: true,
                        tentativeMarkInline: true,
                        density: CalendarSplitPillDensity.regular,
                        margin: const EdgeInsets.only(bottom: 12),
                        leading: const CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.white24,
                        ),
                        trailing: e['icon'] == null
                            ? null
                            : Icon(e['icon'] as IconData, size: 16),
                      ),
                ],
              ),
          ],
        ),
      );
    }

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.schedule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: metrics.isCompact
                ? box(0, 7, false)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 64, child: box(0, 2, true)),
                      SizedBox(width: metrics.isWide ? 32 : 24),
                      Expanded(flex: 36, child: box(2, 5, false)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// CHORES_ONLY: mirrors the HOUSE ROTA slide's per-person cards.
  Widget _choresPreview(DashboardMetrics metrics) {
    Widget group(String name, Color who, List<(String, int, bool)> chores) {
      return DashboardGlassCard(
        tint: DashboardTheme.rota,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 22, backgroundColor: who),
                const SizedBox(width: 12),
                Text(
                  name,
                  style: const TextStyle(
                    color: DashboardTheme.rota,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (final (title, mins, done) in chores)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    DashboardChoreIcon(
                      title: title,
                      done: done,
                      tint: DashboardTheme.rota,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: done ? Colors.white38 : Colors.white,
                          fontSize: metrics.bodySize,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    Text(
                      '${mins}m',
                      style: TextStyle(
                        color: done ? Colors.white24 : DashboardTheme.rota,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.rota,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.cleaning_services_rounded,
            tint: DashboardTheme.rota,
            title: 'HOUSE ROTA',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: group('TOM', CalendarColors.tom, [
                    ('Hoover downstairs', 20, false),
                    ('Take the bins out', 5, true),
                    ('Clean the bathroom', 25, false),
                  ]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: group('MARIA', CalendarColors.maria, [
                    ('Change the bed sheets', 15, false),
                    ('Mop the kitchen floor', 15, false),
                    ('Laundry', 30, true),
                  ]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: group('SHARED', CalendarColors.shared, [
                    ('Water the plants', 10, false),
                    ('Dust the living room', 15, false),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// SHOPPING_ONLY: mirrors the SHOPPING slide (priority + regular).
  Widget _shoppingPreview(DashboardMetrics metrics) {
    Widget list(List<String> items, bool urgent) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  urgent ? Icons.error_rounded : Icons.circle_outlined,
                  color: urgent ? Colors.redAccent : Colors.white38,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Text(
                  t,
                  style: const TextStyle(color: Colors.white, fontSize: 26),
                ),
              ],
            ),
          ),
      ],
    );
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.shopping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.shopping_cart_rounded,
            tint: DashboardTheme.shopping,
            title: 'SHOPPING',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DashboardGlassCard(
                    tint: DashboardTheme.shoppingUrgent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PRIORITY',
                          style: TextStyle(
                            color: DashboardTheme.shoppingUrgent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        list(['Milk', 'Bin bags'], true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: DashboardGlassCard(
                    tint: DashboardTheme.shopping,
                    child: list(['Bread', 'Bananas', 'Coffee', 'Pasta'], false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _galleryDayLabel(DateTime d) {
    const wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const mo = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
  }

  Widget _schedulePreview(DashboardMetrics metrics) {
    final todayCard = DashboardGlassCard(
      tint: DashboardTheme.schedule,
      child: ListView(
        children: const [
          Text(
            'TODAY',
            style: TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'All done for today',
            style: TextStyle(
              color: DashboardTheme.inkFaint,
              fontStyle: FontStyle.italic,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
    final tomorrowCard = DashboardGlassCard(
      tint: DashboardTheme.schedule,
      child: ListView(
        children: [
          const Text(
            'TOMORROW',
            style: TextStyle(
              color: Color(0xFF8FB0C8),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.tom,
              kind: CalendarColors.work,
            ),
            title: 'Early shift',
            subtitle: '07:00',
            density: CalendarSplitPillDensity.comfortable,
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.maria,
              kind: CalendarColors.personal,
            ),
            title: 'School pickup',
            subtitle: '15:30',
            density: CalendarSplitPillDensity.comfortable,
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.shared,
              kind: CalendarColors.personal,
            ),
            title: 'Farmers market walk',
            subtitle: '09:30',
            density: CalendarSplitPillDensity.comfortable,
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.shared,
              kind: CalendarColors.birthday,
              special: CalendarColors.birthday,
            ),
            title: "Maria's birthday",
            subtitle: 'All day',
            density: CalendarSplitPillDensity.comfortable,
            trailing: const Icon(Icons.cake_rounded),
          ),
        ],
      ),
    );

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.schedule,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '07:42',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: metrics.clockSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: DashboardTheme.fade(Colors.white, 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text(
                  '14°  Brighton',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          Text(
            'FRIDAY, 18 SEPTEMBER',
            style: TextStyle(
              color: DashboardTheme.accent,
              fontSize: metrics.dateSize,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.calendar_month_rounded,
            tint: DashboardTheme.schedule,
            title: 'SCHEDULE',
          ),
          const SizedBox(height: 14),
          Expanded(
            child: metrics.isCompact
                ? todayCard
                : Row(
                    children: [
                      Expanded(flex: 60, child: todayCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 40, child: tomorrowCard),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          const Center(child: DashboardPageDots(count: 5, index: 0)),
        ],
      ),
    );
  }

  static final DateTime _previewNow = DateTime(2026, 9, 19);

  List<Map<String, dynamic>> _lookAheadEvents() {
    DateTime at(int dayOffset, [int hour = 9, int minute = 0]) {
      return DateTime(
        _previewNow.year,
        _previewNow.month,
        _previewNow.day + dayOffset,
        hour,
        minute,
      );
    }

    return [
      {
        'summary': 'C2 — Grace Petrie',
        'start': at(-17, 15),
        'end': at(-17, 23, 30),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Dinner at Mum’s',
        'start': at(-12, 18, 30),
        'end': at(-12, 22),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Enzo VET',
        'start': at(-24, 16, 45),
        'end': at(-24, 17, 45),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Late shift',
        'start': at(-9, 14),
        'end': at(-9, 22),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'maria',
      },
      {
        'summary': 'Bin night',
        'start': DateUtils.dateOnly(at(-5)),
        'end': DateUtils.dateOnly(at(-5)),
        'allDay': true,
        'category': 'general',
        'assignedTo': 'tom',
      },
      {
        'summary': 'School pickup',
        'start': at(-2, 15, 30),
        'end': at(-2, 16, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Farmers market walk',
        'start': at(0, 9, 30),
        'end': at(0, 11, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Early shift',
        'start': at(1, 7, 0),
        'end': at(1, 15, 0),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Pasta night',
        'start': at(0, 19, 0),
        'end': at(0, 20, 30),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
      },
      {
        'summary': 'School pickup',
        'start': at(1, 15, 30),
        'end': at(1, 16, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Dentist',
        'start': at(2, 10, 0),
        'end': at(2, 10, 45),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'maria',
      },
      {
        'summary': "Maria's birthday",
        'start': DateUtils.dateOnly(at(3)),
        'end': DateUtils.dateOnly(at(3)),
        'allDay': true,
        'category': 'birthday',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Weekend away',
        'start': DateUtils.dateOnly(at(6)),
        'end': DateUtils.dateOnly(at(8)),
        'allDay': true,
        'category': 'shared',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Dentist',
        'start': at(10, 10, 0),
        'end': at(10, 10, 45),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'maria',
      },
      {
        'summary': 'Date night',
        'start': at(12, 19, 30),
        'end': at(12, 22, 0),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Bin night',
        'start': DateUtils.dateOnly(at(14)),
        'end': DateUtils.dateOnly(at(14)),
        'allDay': true,
        'category': 'general',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Swimming',
        'start': at(18, 16, 0),
        'end': at(18, 17, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'maria',
      },
      {
        'summary': 'Parents evening',
        'start': at(21, 18, 0),
        'end': at(21, 19, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Sunday roast',
        'start': at(23, 13, 0),
        'end': at(23, 15, 0),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
      },
      {
        'summary': 'Half-term walk',
        'start': at(150, 10, 0),
        'end': at(150, 12, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
    ];
  }

  Widget _lookAheadPreview(DashboardMetrics metrics) {
    return Stack(
      children: [
        DashboardCalendarOverviewSlide(
          metrics: metrics,
          events: _lookAheadEvents(),
          now: _previewNow,
          members: _galleryMembers,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Center(child: DashboardPageDots(count: 5, index: 1)),
        ),
      ],
    );
  }

  Widget _splitPillPanel(DashboardMetrics metrics) {
    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule chips',
            style: TextStyle(
              color: Colors.white,
              fontSize: metrics.bodySize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Left third is who. Right two-thirds is work grey, leisure green, or birthday purple.',
            style: TextStyle(color: DashboardTheme.inkMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.tom,
              kind: CalendarColors.work,
            ),
            title: 'Early shift',
            subtitle: '07:00',
            density: CalendarSplitPillDensity.comfortable,
            trailing: const Icon(Icons.work_outline),
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.maria,
              kind: CalendarColors.personal,
            ),
            title: 'Dentist',
            subtitle: '10:00',
            density: CalendarSplitPillDensity.comfortable,
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.shared,
              kind: CalendarColors.personal,
            ),
            title: 'Farmers market walk',
            subtitle: '09:30',
            density: CalendarSplitPillDensity.comfortable,
          ),
          const SizedBox(height: 8),
          CalendarSplitPill(
            style: const CalendarEventStyle(
              who: CalendarColors.shared,
              kind: CalendarColors.birthday,
              special: CalendarColors.birthday,
            ),
            title: "Maria's birthday",
            subtitle: 'All day',
            density: CalendarSplitPillDensity.comfortable,
            trailing: const Icon(Icons.cake_rounded),
          ),
        ],
      ),
    );
  }

  Widget _calendarListPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
      child: ColoredBox(
        color: const Color(0xFFF6F3EE),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calendar list',
                style: TextStyle(
                  color: Color(0xFF1C1914),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Same split pill on the light calendar tab.',
                style: TextStyle(color: Color(0xFF5A564E), fontSize: 14),
              ),
              const SizedBox(height: 16),
              CalendarSplitPill(
                style: const CalendarEventStyle(
                  who: CalendarColors.tom,
                  kind: CalendarColors.work,
                ),
                title: 'Early shift',
                subtitle: '07:00 - 15:00',
                trailing: const Icon(Icons.work),
              ),
              const SizedBox(height: 8),
              CalendarSplitPill(
                style: const CalendarEventStyle(
                  who: CalendarColors.maria,
                  kind: CalendarColors.personal,
                ),
                title: 'Dentist',
                subtitle: '10:00 - 10:45',
              ),
              const SizedBox(height: 8),
              CalendarSplitPill(
                style: const CalendarEventStyle(
                  who: CalendarColors.shared,
                  kind: CalendarColors.birthday,
                  special: CalendarColors.birthday,
                ),
                title: "Maria's birthday",
                trailing: const Icon(Icons.cake_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lookAheadEmptyPreview(DashboardMetrics metrics) {
    return DashboardCalendarOverviewSlide(
      metrics: metrics,
      events: const [],
      now: _previewNow,
      members: _galleryMembers,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    );
  }

  Widget _calendarBoardPanel(DashboardMetrics metrics) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
      child: ColoredBox(
        color: const Color(0xFFF6F3EE),
        child: SizedBox(
          height: metrics.isCompact ? 780 : 720,
          child: _calendarBoardPreview(),
        ),
      ),
    );
  }

  Widget _calendarBoardPreview() {
    final palette = HubMemberPalette.fromMembers(_galleryMembers);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendar',
            style: TextStyle(
              color: Color(0xFF1C1914),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Same LOOK AHEAD day cells. Scroll down for later weeks, up for past ones.',
            style: TextStyle(color: Color(0xFF5A564E), fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CalendarMonthScroller(
              now: _previewNow,
              palette: palette,
              events: _lookAheadEvents(),
              // `?offset=-600` opens scrolled up into past weeks.
              initialScrollOffset:
                  double.tryParse(Uri.base.queryParameters['offset'] ?? '') ??
                  0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sample upcoming birthdays for the gallery and screenshots.
List<DashboardBirthday> galleryBirthdays(DateTime today) {
  DateTime inDays(int d) => DateTime(today.year, today.month, today.day + d);
  return [
    DashboardBirthday(id: 'maria', name: 'Maria', date: inDays(2), turning: 34),
    DashboardBirthday(id: 'nan', name: 'Nan', date: inDays(9), turning: 81),
    DashboardBirthday(id: 'jake', name: 'Jake', date: inDays(12)),
    DashboardBirthday(
      id: 'sophie',
      name: 'Sophie Carter',
      date: inDays(23),
      turning: 30,
    ),
    DashboardBirthday(id: 'dad', name: 'Dad', date: inDays(37), turning: 66),
    DashboardBirthday(id: 'ellie', name: 'Ellie', date: inDays(51), turning: 7),
    DashboardBirthday(id: 'sam', name: 'Sam', date: inDays(64)),
    DashboardBirthday(
      id: 'priya',
      name: 'Priya',
      date: inDays(83),
      turning: 41,
    ),
  ];
}

/// Quotes page + composer, with an in-memory repo and a fake recognizer.
/// `?scene=` page | empty | listening | quote | who | unsupported.
class _QuotesGallery extends StatefulWidget {
  const _QuotesGallery();

  @override
  State<_QuotesGallery> createState() => _QuotesGalleryState();
}

class _GalleryRecognizer implements DashboardSpeechRecognizer {
  _GalleryRecognizer({required this.supported});

  final bool supported;

  @override
  bool get isSupported => supported;

  @override
  Future<DashboardSpeechCapture> listen({
    Duration maxDuration = kDashboardListenLimit,
  }) => Completer<DashboardSpeechCapture>().future; // listens forever

  @override
  void cancel() {}
}

class _GalleryQuotes implements QuoteRepository {
  _GalleryQuotes({required this.empty});

  final bool empty;

  @override
  Stream<List<QuoteModel>> watch(String hubId) => Stream.value(
    empty
        ? const []
        : const [
            QuoteModel(
              id: '1',
              text:
                  'You still load the dishwasher wrong, and I still love you.',
              author: 'Maria',
            ),
            QuoteModel(
              id: '2',
              text: 'Home is wherever I’m with you.',
              author: 'Us',
            ),
            QuoteModel(
              id: '3',
              text: 'Tea first, then the world.',
              author: 'Tom',
            ),
            QuoteModel(
              id: '4',
              text: 'Two are better than one.',
              author: 'Nan',
            ),
          ],
  );

  @override
  Future<void> add(
    String hubId, {
    required String text,
    String author = '',
  }) async {}

  @override
  Future<void> update(
    String hubId,
    String id, {
    required String text,
    String author = '',
  }) async {}

  @override
  Future<void> delete(String hubId, String id) async {}

  @override
  Future<void> restore(String hubId, QuoteModel quote) async {}
}

class _QuotesGalleryState extends State<_QuotesGallery> {
  @override
  void initState() {
    super.initState();
    final scene = Uri.base.queryParameters['scene'] ?? 'page';
    if (scene == 'page' || scene == 'empty' || scene == 'unsupported') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showQuoteComposer(
        context,
        recognizer: _GalleryRecognizer(supported: true),
        onSave: (_, _) async {},
        startListening: scene == 'listening',
        editing: scene == 'edit',
        initialAuthor: scene == 'edit' ? 'Tom' : '',
        initialText: scene == 'quote' || scene == 'who' || scene == 'edit'
            ? 'Tea first, then the world.'
            : '',
        dictatedInitialText: scene == 'quote',
        initialStep: scene == 'who'
            ? QuoteComposerStep.author
            : QuoteComposerStep.quote,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scene = Uri.base.queryParameters['scene'] ?? 'page';
    return QuotesScreen(
      hubId: 'gallery',
      repository: _GalleryQuotes(empty: scene == 'empty'),
      speechRecognizer: _GalleryRecognizer(supported: scene != 'unsupported'),
    );
  }
}

/// FEED_ONLY gallery: the adaptive Home feed with sample data.
/// `?time=morning|afternoon|evening|night` picks the moment (Fri 23 Oct).
class _FeedGallery extends StatefulWidget {
  const _FeedGallery();

  @override
  State<_FeedGallery> createState() => _FeedGalleryState();
}

class _FeedGalleryState extends State<_FeedGallery> {
  final Set<String> _done = {'c3'};

  static const tom = 'tom';
  static const maria = 'maria';

  @override
  Widget build(BuildContext context) {
    final time = Uri.base.queryParameters['time'] ?? 'morning';
    final hour = switch (time) {
      'afternoon' => 13,
      'evening' => 18,
      'night' => 23,
      _ => 8,
    };
    final now = DateTime(2026, 10, 23, hour, 5);
    DateTime at(int d, int h, [int m = 0]) => DateTime(2026, 10, 23 + d, h, m);
    Map<String, dynamic> e(
      String title,
      DateTime s,
      DateTime en, {
      String who = 'shared',
      String cat = 'general',
      bool allDay = false,
      String? status,
    }) => {
      'summary': title,
      'start': s,
      'end': en,
      'assignedTo': who,
      'category': cat,
      'allDay': allDay,
      'status': ?status,
    };
    final chores = [
      ('c1', 'Dusting (Window sills, appliances, plants etc)', tom, 30),
      ('c2', 'Clean Bathroom', tom, 25),
      ('c3', 'Hoovering', tom, 15),
      ('c4', 'Check fridge for expired food', tom, 5),
      ('c5', 'Change Bedding', maria, 30),
      ('c6', 'Change Litter', maria, 20),
      ('c7', 'Hoovering', maria, 15),
      ('c8', 'Water plants', maria, 10),
    ];
    final data = HomeFeedData(
      now: now,
      myUid: tom,
      names: const {tom: 'Tom', maria: 'Maria'},
      events: [
        e(
          'C2 — R&B Orchestra',
          at(0, 15),
          at(0, 23, 30),
          who: tom,
          cat: 'work',
          status: 'tentative',
        ),
        e(
          'C2 — Bou',
          at(0, 22),
          at(1, 4, 30),
          who: tom,
          cat: 'work',
          status: 'tentative',
        ),
        e('Coffee with Janis', at(0, 10, 30), at(0, 11, 30), who: maria),
        e('Enzo walk on the Downs', at(0, 9), at(0, 10)),
        e(
          'C2 — Dirty DC',
          at(1, 15),
          at(1, 23, 30),
          who: tom,
          cat: 'work',
          status: 'tentative',
        ),
        e('Brunch at Bills', at(1, 11), at(1, 12, 30)),
        e(
          'C2 — Hold Tight',
          at(1, 22),
          at(2, 3, 30),
          who: tom,
          cat: 'work',
          status: 'tentative',
        ),
        e('Fajitas', at(0, 19), at(0, 20), cat: 'meal'),
        e(
          "Bella Burch's Birthday",
          DateTime(2026, 10, 26),
          DateTime(2026, 10, 26),
          cat: 'birthday',
          allDay: true,
        ),
      ],
      chores: [
        for (final (id, t, who, m) in chores)
          FeedChore(
            id: id,
            title: t,
            assignedTo: who,
            minutes: m,
            done: _done.contains(id),
          ),
      ],
      tasks: [
        FeedTask(
          id: 't1',
          text: 'Book Enzo vet booster',
          due: DateTime(2026, 10, 21),
          urgent: true,
        ),
        FeedTask(
          id: 't2',
          text: 'Pay council tax',
          due: DateTime(2026, 10, 23),
        ),
        const FeedTask(id: 't3', text: 'Call the letting agent'),
        FeedTask(id: 't4', text: 'Gift for Bella', due: DateTime(2026, 10, 25)),
        const FeedTask(id: 's1', text: 'Milk', listName: 'Shopping'),
        const FeedTask(id: 's2', text: 'Bananas', listName: 'Shopping'),
        const FeedTask(id: 's3', text: 'Dog food', listName: 'Shopping'),
        const FeedTask(id: 's4', text: 'Tin foil', listName: 'Shopping'),
      ],
      weather: FeedWeather(
        city: 'Brighton',
        tempNow: 12,
        todayMax: 14,
        todayMin: 8,
        rainChance: time == 'morning' || time == 'afternoon' ? 70 : 20,
        rainFrom: at(0, 15),
      ),
      quote: "God that soundcheck was long. It was a whole bag of Haribo long",
      quoteAuthor: 'Pob',
    );
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Text(
                  feedGreeting(now, 'Tom'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    color: Colors.black54,
                  ),
                ),
              ),
              HomeFeedView(
                data: data,
                palette: HubMemberPalette.fromMembers(const [
                  {'uid': tom, 'name': 'Tom'},
                  {'uid': maria, 'name': 'Maria'},
                ]),
                onToggleChore: (c, v) =>
                    setState(() => v ? _done.add(c.id) : _done.remove(c.id)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
