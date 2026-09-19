import 'package:flutter/material.dart';
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
              style: const TextStyle(color: DashboardTheme.inkMuted, fontSize: 16),
            ),
            const SizedBox(height: 28),
            _panel(
              height: 280,
              child: const DashboardLoadingView(),
            ),
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
              height: metrics.isCompact ? 640 : 560,
              child: _lookAheadPreview(metrics),
            ),
            const SizedBox(height: 20),
            _panel(
              height: metrics.isCompact ? 520 : 480,
              child: _lookAheadEmptyPreview(metrics),
            ),
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
        children: const [
          Text(
            'TOMORROW',
            style: TextStyle(
              color: Color(0xFF8FB0C8),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Farmers market walk',
            style: TextStyle(color: Colors.white, fontSize: 20),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        'summary': 'Farmers market walk',
        'start': at(0, 9, 30),
        'end': at(0, 11, 0),
        'allDay': false,
        'category': 'shared',
        'assignedTo': 'shared',
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
    ];
  }

  Widget _lookAheadPreview(DashboardMetrics metrics) {
    return Stack(
      children: [
        DashboardCalendarOverviewSlide(
          metrics: metrics,
          events: _lookAheadEvents(),
          now: _previewNow,
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

  Widget _lookAheadEmptyPreview(DashboardMetrics metrics) {
    return DashboardCalendarOverviewSlide(
      metrics: metrics,
      events: const [],
      now: _previewNow,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    );
  }
}
