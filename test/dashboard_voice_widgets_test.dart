import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_controls_overlay.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';
import 'package:lovehub/widgets/dashboard/dashboard_today_answer.dart';

void main() {
  final palette = HubMemberPalette.fromMembers(const [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ]);
  final day = DateTime(2026, 9, 21);

  List<Map<String, dynamic>> events() {
    return [
      {
        'summary': 'Early shift',
        'start': DateTime(2026, 9, 21, 7),
        'end': DateTime(2026, 9, 21, 15),
        'allDay': false,
        'category': 'work',
        'assignedTo': 'tom',
      },
      {
        'summary': 'Farmers market walk',
        'start': DateTime(2026, 9, 21, 9, 30),
        'end': DateTime(2026, 9, 21, 11),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'shared',
      },
    ];
  }

  Future<void> pumpOverlay(
    WidgetTester tester, {
    required bool visible,
    bool isPlaying = true,
    bool isListening = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardControlsOverlay(
            visible: visible,
            isPlaying: isPlaying,
            isListening: isListening,
            onExit: () {},
            onTogglePlay: () {},
            onOptions: () {},
            onMic: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('controls overlay includes the mic with play and pause', (
    tester,
  ) async {
    await pumpOverlay(tester, visible: true);

    final opacity = tester.widget<AnimatedOpacity>(
      find.byKey(DashboardControlsOverlay.opacityKey),
    );
    expect(opacity.duration, const Duration(milliseconds: 280));
    expect(opacity.opacity, 1);

    expect(
      find.descendant(
        of: find.byKey(DashboardControlsOverlay.pillKey),
        matching: find.byKey(DashboardControlsOverlay.playKey),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(DashboardControlsOverlay.pillKey),
        matching: find.byKey(DashboardControlsOverlay.micKey),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
    expect(find.byTooltip("Ask what's on today"), findsOneWidget);
    expect(find.byKey(DashboardControlsOverlay.listeningKey), findsNothing);
  });

  testWidgets('hidden controls omit the mic so the wall can be swiped', (
    tester,
  ) async {
    await pumpOverlay(tester, visible: false);

    expect(find.byKey(DashboardControlsOverlay.micKey), findsNothing);
    expect(find.byKey(DashboardControlsOverlay.playKey), findsNothing);
    final opacity = tester.widget<AnimatedOpacity>(
      find.byKey(DashboardControlsOverlay.opacityKey),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('listening state sits on the same controls pill', (tester) async {
    await pumpOverlay(
      tester,
      visible: true,
      isPlaying: false,
      isListening: true,
    );

    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
    expect(icon.color, DashboardTheme.accent);
  });

  testWidgets('answer card lists today events on split pills', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DashboardTodayAnswerLayer(
                metrics: DashboardMetrics(const Size(1200, 900)),
                day: day,
                events: events(),
                palette: palette,
                transcript: "what's on today",
                onClose: () => closed = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Today · Monday 21 September'), findsOneWidget);
    expect(find.text('2 plans'), findsOneWidget);
    expect(find.text('Early shift'), findsOneWidget);
    expect(find.text('Farmers market walk'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.eventsKey), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.emptyKey), findsNothing);

    await tester.tap(find.byKey(DashboardTodayAnswerLayer.closeKey));
    expect(closed, isTrue);
  });

  testWidgets('answer card shows a free day when nothing is planned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DashboardTodayAnswerLayer(
                metrics: DashboardMetrics(const Size(1200, 900)),
                day: day,
                events: const [],
                palette: palette,
                onClose: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Nothing planned'), findsOneWidget);
    expect(find.text('Free day — nothing on the calendar'), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.emptyKey), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.eventsKey), findsNothing);
  });

  testWidgets('typed fallback explains when speech is unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DashboardVoicePromptLayer(
                metrics: DashboardMetrics(const Size(1200, 900)),
                notice: 'Speech not available — try Chrome',
                controller: controller,
                onClose: () {},
                onSubmit: (value) => submitted = value,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Speech not available — try Chrome'), findsOneWidget);
    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      "what's on today",
    );
    await tester.tap(find.byKey(DashboardVoicePromptLayer.submitKey));
    expect(submitted, "what's on today");
  });
}
