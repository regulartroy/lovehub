import 'package:flutter/material.dart';
import 'package:lovehub/models/event_model.dart';
import 'voice_spike_gallery.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_month_scroller.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_chrome.dart';
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
            'Same month headers and gaps as LOOK AHEAD, with lazy future scroll.',
            style: TextStyle(color: Color(0xFF5A564E), fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CalendarMonthScroller(
              now: _previewNow,
              palette: palette,
              eventsForDay: (day) {
                return _lookAheadEvents()
                    .where((event) {
                      return dashboardEventOverlapsDay(event, day);
                    })
                    .map(
                      (event) => EventModel(
                        id: event['summary'].toString(),
                        summary: event['summary'].toString(),
                        start: event['start'] as DateTime,
                        end: (event['end'] ?? event['start']) as DateTime,
                        allDay: event['allDay'] == true,
                        category: (event['category'] ?? 'general').toString(),
                        assignedTo: (event['assignedTo'] ?? 'shared')
                            .toString(),
                      ),
                    )
                    .toList();
              },
            ),
          ),
        ],
      ),
    );
  }
}
