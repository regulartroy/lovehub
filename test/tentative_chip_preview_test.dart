import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/calendar_split_pill.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';

void main() {
  testWidgets('tentative chips stay readable against confirmed work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(880, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: TentativeChipPreview()));
    await tester.pumpAndSettle();

    expect(find.text('?'), findsNWidgets(3));
    expect(find.byKey(CalendarSplitPill.tentativeMarkKey), findsNWidgets(3));

    final confirmed = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('confirmed-calendar')),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    final tentative = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const Key('tentative-calendar')),
        matching: find.byKey(CalendarSplitPill.kindKey),
      ),
    );
    expect(confirmed.color, CalendarColors.work);
    expect(
      tentative.color.computeLuminance(),
      greaterThan(confirmed.color.computeLuminance()),
    );

    if (Platform.environment['SAVE_TENTATIVE_SCREENSHOT'] == '1') {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('tentative-preview-boundary')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'docs/tentative-vs-confirmed.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}

class TentativeChipPreview extends StatelessWidget {
  const TentativeChipPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'uid-tom', 'displayName': 'Tom Workman'},
    ]);
    CalendarSplitPill chip({
      required Key key,
      required String status,
      required String title,
      required CalendarSplitPillDensity density,
      bool showAvatar = false,
    }) {
      return CalendarSplitPill(
        key: key,
        style: CalendarColors.resolve(
          assignedTo: 'tom',
          category: 'work',
          status: status,
          palette: palette,
        ),
        title: title,
        subtitle: density == CalendarSplitPillDensity.compact
            ? null
            : '15:00 – 23:30',
        density: density,
        margin: const EdgeInsets.only(bottom: 10),
        leading: showAvatar
            ? const CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white24,
                child: Text('T', style: TextStyle(fontSize: 12)),
              )
            : null,
        trailing: density == CalendarSplitPillDensity.compact
            ? null
            : const Icon(Icons.work, size: 16),
      );
    }

    return ColoredBox(
      color: const Color(0xFF101014),
      child: RepaintBoundary(
        key: const Key('tentative-preview-boundary'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Confirmed work stays Tom blue and stone grey',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tentative Concorde dates are paler, with a ?',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 18),
              _Panel(
                title: 'Calendar',
                background: const Color(0xFFF4F0EA),
                ink: const Color(0xFF1C1914),
                children: [
                  chip(
                    key: const Key('confirmed-calendar'),
                    status: 'confirmed',
                    title: 'C2 Show — Artist',
                    density: CalendarSplitPillDensity.regular,
                    showAvatar: true,
                  ),
                  chip(
                    key: const Key('tentative-calendar'),
                    status: 'tentative',
                    title: 'C2 Show — Artist',
                    density: CalendarSplitPillDensity.regular,
                    showAvatar: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Panel(
                title: 'Dashboard and LOOK AHEAD',
                background: DashboardTheme.canvas,
                ink: Colors.white,
                children: [
                  chip(
                    key: const Key('confirmed-dashboard'),
                    status: 'confirmed',
                    title: 'C2 Show — Artist',
                    density: CalendarSplitPillDensity.comfortable,
                  ),
                  chip(
                    key: const Key('tentative-dashboard'),
                    status: 'tentative',
                    title: 'C2 Show — Artist',
                    density: CalendarSplitPillDensity.comfortable,
                  ),
                  chip(
                    key: const Key('tentative-lookahead'),
                    status: 'tentative',
                    title: '15:00 C2 Show — Artist',
                    density: CalendarSplitPillDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.background,
    required this.ink,
    required this.children,
  });

  final String title;
  final Color background;
  final Color ink;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
