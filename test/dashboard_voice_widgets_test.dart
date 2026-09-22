import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/dashboard_voice.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_controls_overlay.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';
import 'package:lovehub/widgets/dashboard/dashboard_today_answer.dart';

void _noop() {}

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
    expect(find.byTooltip("Ask what's on"), findsOneWidget);
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

  testWidgets('a hidden controls pill does not block page swipes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onTap: () {},
            child: Stack(
              children: [
                PageView(
                  children: const [
                    Center(child: Text('Slide one')),
                    Center(child: Text('Slide two')),
                  ],
                ),
                DashboardControlsOverlay(
                  visible: false,
                  isPlaying: true,
                  isListening: false,
                  onExit: _noop,
                  onTogglePlay: _noop,
                  onMic: _noop,
                  onOptions: _noop,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Slide one'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Slide two'), findsOneWidget);
  });

  testWidgets('the today card keeps a horizontal swipe on the page', (
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
              PageView(
                children: const [
                  Center(child: Text('Slide one')),
                  Center(child: Text('Slide two')),
                ],
              ),
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

    await tester.drag(
      find.byKey(DashboardTodayAnswerLayer.barrierKey),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Slide one'), findsOneWidget);
    expect(find.text('Slide two'), findsNothing);
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
                today: DateTime(2026, 9, 22),
                notice:
                    'Speech not available — try Chrome. You can type a day below.',
                controller: controller,
                onClose: () {},
                onSubmit: (value) => submitted = value,
                onShowToday: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Speech not available — try Chrome. You can type a day below.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      "what's on today",
    );
    await tester.tap(find.byKey(DashboardVoicePromptLayer.submitKey));
    expect(submitted, "what's on today");
  });

  testWidgets('tapping Show today opens today’s answer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(
        today: DateTime(2026, 9, 22),
        initialText: "what's the weather",
        events: _voiceEvents(),
      ),
    );

    expect(find.text('Show today'), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.cardKey), findsNothing);

    await tester.tap(find.text('Show today'));
    await tester.pump();

    expect(find.byKey(DashboardTodayAnswerLayer.cardKey), findsOneWidget);
    expect(find.text('Today · Tuesday 22 September'), findsOneWidget);
    expect(find.text('Early shift'), findsOneWidget);
    expect(find.text('2 plans'), findsOneWidget);
    expect(find.text('Show today'), findsNothing);
    expect(find.byKey(DashboardVoicePromptLayer.cardKey), findsNothing);
  });

  testWidgets('an empty Show today button still opens today’s answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: const []),
    );

    await tester.tap(find.text('Show today'));
    await tester.pump();

    expect(find.text('Today · Tuesday 22 September'), findsOneWidget);
    expect(find.text('Free day — nothing on the calendar'), findsOneWidget);
  });

  testWidgets('typing a date and tapping the button opens that day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: _voiceEvents()),
    );

    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      'what have I got on 23rd of October',
    );
    await tester.pump();

    expect(find.text('Show 23 October'), findsOneWidget);
    await tester.tap(find.text('Show 23 October'));
    await tester.pump();

    expect(find.text('Friday 23 October'), findsOneWidget);
    expect(find.text('Half-term train'), findsOneWidget);
    expect(find.text('08:15'), findsOneWidget);
    expect(find.text('Early shift'), findsNothing);
    expect(find.textContaining('Heard:'), findsOneWidget);
  });

  testWidgets('pressing done on a date question opens that day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: _voiceEvents()),
    );

    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      "what's on the 23rd",
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Wednesday 23 September'), findsOneWidget);
    expect(find.text('Market morning'), findsOneWidget);
    expect(find.text('Early shift'), findsNothing);
  });

  testWidgets('naming a date’s week opens that Monday–Sunday card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: _voiceEvents()),
    );

    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      'week of October 23rd',
    );
    await tester.pump();

    expect(find.text('Show week'), findsOneWidget);
    await tester.tap(find.text('Show week'));
    await tester.pump();

    expect(find.text('Week of 23 October'), findsOneWidget);
    expect(find.text('Monday 19 – Sunday 25 October'), findsOneWidget);
    expect(find.text('1 plan · 6 free days'), findsOneWidget);
    expect(find.text('Half-term train'), findsOneWidget);
    expect(find.text('08:15'), findsOneWidget);
    expect(find.text('Early shift'), findsNothing);
    expect(
      find.byKey(DashboardWeekAnswerLayer.freeKey(DateTime(2026, 10, 19))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardWeekAnswerLayer.freeKey(DateTime(2026, 10, 25))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardWeekAnswerLayer.dayKey(DateTime(2026, 10, 23))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardWeekAnswerLayer.freeKey(DateTime(2026, 10, 23))),
      findsNothing,
    );

    await tester.tap(find.byKey(DashboardWeekAnswerLayer.closeKey));
    await tester.pump();
  });

  testWidgets('show week on a day card opens the week containing that day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: _voiceEvents()),
    );

    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      'what have I got on 23rd of October',
    );
    await tester.pump();
    await tester.tap(find.text('Show 23 October'));
    await tester.pump();

    expect(find.text('Friday 23 October'), findsOneWidget);
    expect(find.byKey(DashboardTodayAnswerLayer.showWeekKey), findsOneWidget);

    await tester.tap(find.byKey(DashboardTodayAnswerLayer.showWeekKey));
    await tester.pump();

    expect(find.text('Friday 23 October'), findsNothing);
    expect(find.text('Week of 23 October'), findsOneWidget);
    expect(find.text('Monday 19 – Sunday 25 October'), findsOneWidget);
    expect(find.text('Half-term train'), findsOneWidget);
    expect(find.text('Free'), findsNWidgets(6));
  });

  testWidgets('a from-to date opens that inclusive range', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _AskHarness(today: DateTime(2026, 9, 22), events: _voiceEvents()),
    );

    await tester.enterText(
      find.byKey(DashboardVoicePromptLayer.fieldKey),
      "what's on from 20 to 25 October",
    );
    await tester.pump();

    expect(find.text('Show 20–25 October'), findsOneWidget);
    await tester.tap(find.text('Show 20–25 October'));
    await tester.pump();

    expect(find.text('20–25 October'), findsOneWidget);
    expect(find.text('Tuesday 20 – Sunday 25 October'), findsOneWidget);
    expect(find.text('1 plan · 5 free days'), findsOneWidget);
    expect(find.text('Half-term train'), findsOneWidget);
    expect(find.text('08:15'), findsOneWidget);
    expect(find.text('Early shift'), findsNothing);
    expect(find.text('Week of 23 October'), findsNothing);
    expect(
      find.byKey(DashboardRangeAnswerLayer.freeKey(DateTime(2026, 10, 20))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardRangeAnswerLayer.freeKey(DateTime(2026, 10, 25))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardRangeAnswerLayer.dayKey(DateTime(2026, 10, 23))),
      findsOneWidget,
    );
    expect(
      find.byKey(DashboardRangeAnswerLayer.freeKey(DateTime(2026, 10, 23))),
      findsNothing,
    );
  });
}

List<Map<String, dynamic>> _voiceEvents() {
  return [
    {
      'summary': 'Early shift',
      'start': DateTime(2026, 9, 22, 7),
      'end': DateTime(2026, 9, 22, 15),
      'allDay': false,
      'category': 'work',
      'assignedTo': 'tom',
    },
    {
      'summary': 'Pasta night',
      'start': DateTime(2026, 9, 22, 19),
      'end': DateTime(2026, 9, 22, 20, 30),
      'allDay': false,
      'category': 'meal',
      'assignedTo': 'maria',
    },
    {
      'summary': 'Half-term train',
      'start': DateTime(2026, 10, 23, 8, 15),
      'end': DateTime(2026, 10, 23, 12),
      'allDay': false,
      'category': 'general',
      'assignedTo': 'tom',
    },
    {
      'summary': 'Market morning',
      'start': DateTime(2026, 9, 23, 9),
      'end': DateTime(2026, 9, 23, 11),
      'allDay': false,
      'category': 'general',
      'assignedTo': 'shared',
    },
  ];
}

/// Same prompt → answer wiring as the dashboard, including the outer tap
/// target that shows the controls pill.
class _AskHarness extends StatefulWidget {
  const _AskHarness({
    required this.today,
    required this.events,
    this.initialText = '',
  });

  final DateTime today;
  final List<Map<String, dynamic>> events;
  final String initialText;

  @override
  State<_AskHarness> createState() => _AskHarnessState();
}

class _AskHarnessState extends State<_AskHarness> {
  late final TextEditingController _controller;
  late DashboardVoiceState _voice;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _voice = DashboardVoiceState(
      phase: widget.initialText.isEmpty
          ? DashboardVoicePhase.fallback
          : DashboardVoicePhase.unrecognized,
      transcript: widget.initialText,
      notice: widget.initialText.isEmpty
          ? DashboardVoiceState.speechUnavailableNotice
          : DashboardVoiceState.unrecognizedNotice,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _eventsOn(DateTime day) {
    return widget.events.where((event) {
      final start = event['start'] as DateTime;
      return start.year == day.year &&
          start.month == day.month &&
          start.day == day.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = DashboardMetrics(const Size(1200, 900));
    final palette = HubMemberPalette.fromMembers(const [
      {'uid': 'tom', 'name': 'Tom'},
      {'uid': 'maria', 'name': 'Maria'},
    ]);
    final showingAnswer = _voice.phase == DashboardVoicePhase.answer;
    final showingPrompt =
        _voice.phase == DashboardVoicePhase.fallback ||
        _voice.phase == DashboardVoicePhase.unrecognized;

    return MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          onTap: () {},
          child: Stack(
            children: [
              const SizedBox.expand(),
              if (showingAnswer)
                DashboardVoiceAnswerLayer(
                  metrics: metrics,
                  state: _voice,
                  today: widget.today,
                  palette: palette,
                  onClose: () {},
                  onShowWeek: () {
                    setState(() {
                      _voice = _voice.showWeekContaining(
                        _voice.answerDay ?? widget.today,
                        eventsOn: _eventsOn,
                      );
                    });
                  },
                ),
              if (showingPrompt)
                DashboardVoicePromptLayer(
                  metrics: metrics,
                  today: widget.today,
                  notice: _voice.notice,
                  controller: _controller,
                  onClose: () {},
                  onShowToday: () {
                    setState(() {
                      _voice = _voice.showToday(
                        _eventsOn(widget.today),
                        day: widget.today,
                      );
                    });
                  },
                  onSubmit: (raw) {
                    setState(() {
                      _voice = _voice.answerQuestion(
                        raw,
                        today: widget.today,
                        eventsOn: _eventsOn,
                      );
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
