import 'package:flutter/material.dart';
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
      body: PageView(
        children: [
          const DashboardLoadingView(),
          ColoredBox(
            color: DashboardTheme.canvas,
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
          ColoredBox(
            color: DashboardTheme.canvas,
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
          DashboardSlide(
            metrics: metrics,
            tint: DashboardTheme.schedule,
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
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                DashboardSectionHeader(
                  metrics: metrics,
                  icon: Icons.calendar_month_rounded,
                  tint: DashboardTheme.schedule,
                  title: 'SCHEDULE',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: DashboardGlassCard(
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
                        SizedBox(height: 24),
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
                  ),
                ),
                const SizedBox(height: 16),
                const Center(child: DashboardPageDots(count: 4, index: 0)),
              ],
            ),
          ),
          DashboardSlide(
            metrics: metrics,
            tint: DashboardTheme.weather,
            child: Column(
              children: [
                DashboardSectionHeader(
                  metrics: metrics,
                  icon: Icons.wb_cloudy_rounded,
                  tint: DashboardTheme.weather,
                  title: 'FORECAST',
                ),
                const Expanded(
                  child: DashboardEmptyState(
                    icon: Icons.wb_cloudy_outlined,
                    tint: DashboardTheme.weather,
                    title: 'Forecast is taking a pause.',
                    message: 'Add a city, or try again in a moment.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
