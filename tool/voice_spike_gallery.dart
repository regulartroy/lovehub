import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lovehub/services/dashboard_speech.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';
import 'package:lovehub/widgets/dashboard/dashboard_chrome.dart';
import 'package:lovehub/widgets/dashboard/dashboard_controls_overlay.dart';
import 'package:lovehub/widgets/dashboard/dashboard_theme.dart';
import 'package:lovehub/widgets/dashboard/dashboard_today_answer.dart';

/// Wall-tablet demo of the dashboard mic, using the same controls pill,
/// voice state, and today-answer card as [DashboardScreen].
///
/// Sample events stand in for the hub calendar so the UI can be reviewed
/// without signing in. Open with `?scene=controls&menu=0` (or listening,
/// events, empty) for a clean frame.
class VoiceSpikeGallery extends StatefulWidget {
  const VoiceSpikeGallery({super.key});

  @override
  State<VoiceSpikeGallery> createState() => _VoiceSpikeGalleryState();
}

enum _VoiceScene { live, controls, listening, events, empty, ask }

class _VoiceSpikeGalleryState extends State<VoiceSpikeGallery> {
  final PageController _pageController = PageController();
  final TextEditingController _voiceQueryController = TextEditingController();
  late final DashboardSpeechRecognizer _speech;

  _VoiceScene _scene = _VoiceScene.live;
  bool _showMenu = true;
  bool _showControls = false;
  bool _isPlaying = true;
  int _page = 0;
  DashboardVoiceState _voice = const DashboardVoiceState();
  int _listenToken = 0;
  Timer? _hideTimer;

  static const _members = [
    {'uid': 'tom', 'name': 'Tom'},
    {'uid': 'maria', 'name': 'Maria'},
  ];

  @override
  void initState() {
    super.initState();
    _speech = createDashboardSpeechRecognizer();
    _scene = _sceneFromQuery(Uri.base.queryParameters['scene']);
    _showMenu = Uri.base.queryParameters['menu'] != '0';
    _showControls = _scene != _VoiceScene.live;
    _voice = _voiceForScene(_scene);
    final preset = Uri.base.queryParameters['q'];
    if (_scene == _VoiceScene.ask && preset != null && preset.isNotEmpty) {
      _voiceQueryController.text = preset;
      _voice = DashboardVoiceState(
        phase: DashboardVoicePhase.unrecognized,
        transcript: preset,
        notice: DashboardVoiceState.unrecognizedNotice,
      );
    }
  }

  @override
  void dispose() {
    _listenToken++;
    _speech.cancel();
    _hideTimer?.cancel();
    _pageController.dispose();
    _voiceQueryController.dispose();
    super.dispose();
  }

  _VoiceScene _sceneFromQuery(String? raw) {
    switch (raw) {
      case 'controls':
        return _VoiceScene.controls;
      case 'listening':
        return _VoiceScene.listening;
      case 'events':
        return _VoiceScene.events;
      case 'empty':
        return _VoiceScene.empty;
      case 'ask':
        return _VoiceScene.ask;
      default:
        return _VoiceScene.live;
    }
  }

  List<Map<String, dynamic>> _sampleEvents({required bool empty}) {
    if (empty) return const [];
    final today = DateUtils.dateOnly(DateTime.now());
    DateTime at(int dayOffset, int hour, int minute) {
      return DateTime(
        today.year,
        today.month,
        today.day + dayOffset,
        hour,
        minute,
      );
    }

    return [
      {
        'summary': 'Early shift',
        'start': at(0, 7, 0),
        'end': at(0, 15, 0),
        'allDay': false,
        'category': 'work',
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
        'summary': 'Pasta night',
        'start': at(0, 19, 0),
        'end': at(0, 20, 30),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'maria',
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
        'summary': 'Date night',
        'start': at(3, 19, 30),
        'end': at(3, 22, 0),
        'allDay': false,
        'category': 'meal',
        'assignedTo': 'shared',
      },
      ..._october23(today),
    ];
  }

  /// 23 October this year and next, so a dated question finds the trip
  /// whether or not that day has already passed.
  List<Map<String, dynamic>> _october23(DateTime today) {
    Map<String, dynamic> trip(int year) {
      return {
        'summary': 'Half-term train',
        'start': DateTime(year, 10, 23, 8, 15),
        'end': DateTime(year, 10, 23, 12, 0),
        'allDay': false,
        'category': 'general',
        'assignedTo': 'tom',
      };
    }

    return [trip(today.year), trip(today.year + 1)];
  }

  List<Map<String, dynamic>> get _events =>
      _sampleEvents(empty: _scene == _VoiceScene.empty);

  List<Map<String, dynamic>> _eventsOn(DateTime day) {
    return dashboardEventsOnDay(_events, day);
  }

  List<Map<String, dynamic>> _eventsToday() {
    return _eventsOn(DateUtils.dateOnly(DateTime.now()));
  }

  DashboardVoiceState _voiceForScene(_VoiceScene scene) {
    switch (scene) {
      case _VoiceScene.live:
      case _VoiceScene.controls:
        return const DashboardVoiceState();
      case _VoiceScene.listening:
        return const DashboardVoiceState.listening();
      case _VoiceScene.events:
        return const DashboardVoiceState().fromTranscript(
          "what's on today",
          _eventsToday(),
        );
      case _VoiceScene.empty:
        return const DashboardVoiceState().fromTranscript(
          "what's on today",
          const [],
        );
      case _VoiceScene.ask:
        return const DashboardVoiceState(
          phase: DashboardVoicePhase.fallback,
          notice: DashboardVoiceState.unrecognizedNotice,
        );
    }
  }

  void _applyScene(_VoiceScene scene) {
    _listenToken++;
    _speech.cancel();
    _hideTimer?.cancel();
    _voiceQueryController.clear();
    setState(() {
      _scene = scene;
      _voice = _voiceForScene(scene);
      _showControls = true;
    });
  }

  void _showControlsOverlay() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    if (_scene != _VoiceScene.live || _voice.holdsControls) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _dismissVoice() {
    _listenToken++;
    _speech.cancel();
    _voiceQueryController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _scene = _VoiceScene.live;
      _voice = const DashboardVoiceState();
    });
    _showControlsOverlay();
  }

  Future<void> _onMic() async {
    if (_voice.phase == DashboardVoicePhase.listening) {
      _dismissVoice();
      return;
    }
    if (_scene != _VoiceScene.live) {
      _applyScene(_VoiceScene.live);
    }
    if (!_speech.isSupported) {
      setState(() {
        _voice = const DashboardVoiceState(
          phase: DashboardVoicePhase.fallback,
          notice: DashboardVoiceState.speechUnavailableNotice,
        );
      });
      _showControlsOverlay();
      return;
    }

    final token = ++_listenToken;
    setState(() => _voice = const DashboardVoiceState.listening());
    _showControlsOverlay();

    DashboardSpeechCapture capture;
    try {
      capture = await _speech.listen();
    } catch (_) {
      capture = const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.unavailable,
        message: DashboardVoiceState.speechUnavailableNotice,
      );
    }
    if (!mounted || token != _listenToken) return;
    if (capture.message == 'cancelled') return;

    final next = const DashboardVoiceState().applyCapture(
      capture,
      _eventsToday(),
      today: DateTime.now(),
      eventsOn: _eventsOn,
    );
    if (next.phase == DashboardVoicePhase.unrecognized &&
        next.transcript.isNotEmpty) {
      _voiceQueryController.text = next.transcript;
    }
    setState(() => _voice = next);
    _showControlsOverlay();
  }

  void _submitVoiceQuery(String raw) {
    final next = _voice.answerQuestion(
      raw,
      today: DateTime.now(),
      eventsOn: _eventsOn,
    );
    if (next.phase == DashboardVoicePhase.answer) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => _voice = next);
    _showControlsOverlay();
  }

  void _showVoiceToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    final next = _voice.showToday(_eventsOn(today), day: today);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _voice = next);
    _showControlsOverlay();
  }

  void _showVoiceWeek() {
    final day = _voice.answerDay ?? DateUtils.dateOnly(DateTime.now());
    setState(() {
      _voice = _voice.showWeekContaining(day, eventsOn: _eventsOn);
    });
    _showControlsOverlay();
  }

  bool get _controlsVisible =>
      _showControls || _voice.holdsControls || _scene != _VoiceScene.live;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final metrics = DashboardMetrics(size);
    final now = DateTime.now();
    final palette = HubMemberPalette.fromMembers(_members);

    return Scaffold(
      backgroundColor: DashboardTheme.canvas,
      body: GestureDetector(
        onTap: _showControlsOverlay,
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _page = index),
              children: [
                DashboardCalendarOverviewSlide(
                  metrics: metrics,
                  events: _events,
                  now: now,
                  members: _members,
                  onDayTap: (_) => _showControlsOverlay(),
                ),
                DashboardSlide(
                  metrics: metrics,
                  tint: DashboardTheme.photos,
                  child: Center(
                    child: Text(
                      'Swipe back to the week.\nThe mic stays on the controls pill.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DashboardTheme.ink,
                        fontSize: metrics.isCompact ? 22 : 28,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.headerPadH,
                  metrics.headerPadTop,
                  metrics.headerPadH,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(now),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: metrics.clockSize,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE d MMMM').format(now).toUpperCase(),
                      style: TextStyle(
                        color: DashboardTheme.inkMuted,
                        fontSize: metrics.dateSize,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_voice.phase == DashboardVoicePhase.answer)
              DashboardVoiceAnswerLayer(
                metrics: metrics,
                state: _voice,
                today: now,
                palette: palette,
                onClose: _dismissVoice,
                onShowWeek: _showVoiceWeek,
              ),
            if (_voice.phase == DashboardVoicePhase.fallback ||
                _voice.phase == DashboardVoicePhase.unrecognized)
              DashboardVoicePromptLayer(
                metrics: metrics,
                today: now,
                notice: _voice.notice,
                controller: _voiceQueryController,
                onClose: _dismissVoice,
                onSubmit: _submitVoiceQuery,
                onShowToday: _showVoiceToday,
              ),
            DashboardControlsOverlay(
              visible: _controlsVisible,
              isPlaying: _isPlaying,
              isListening: _voice.phase == DashboardVoicePhase.listening,
              onExit: () {},
              onTogglePlay: () {
                setState(() => _isPlaying = !_isPlaying);
                _showControlsOverlay();
              },
              onMic: () {
                unawaited(_onMic());
              },
              onOptions: () {
                _showControlsOverlay();
              },
            ),
            if (_events.isNotEmpty || _page == 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: _showMenu ? 64 : 16,
                child: IgnorePointer(
                  child: Center(
                    child: DashboardPageDots(count: 2, index: _page),
                  ),
                ),
              ),
            if (_showMenu) _sceneMenu(),
          ],
        ),
      ),
    );
  }

  Widget _sceneMenu() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Material(
            color: DashboardTheme.fade(Colors.black, 0.72),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  _sceneButton(
                    'Live',
                    _VoiceScene.live,
                    'voice-gallery-scene-live',
                  ),
                  _sceneButton(
                    'Controls',
                    _VoiceScene.controls,
                    'voice-gallery-scene-controls',
                  ),
                  _sceneButton(
                    'Listening',
                    _VoiceScene.listening,
                    'voice-gallery-scene-listening',
                  ),
                  _sceneButton(
                    'Today',
                    _VoiceScene.events,
                    'voice-gallery-scene-events',
                  ),
                  _sceneButton(
                    'Free day',
                    _VoiceScene.empty,
                    'voice-gallery-scene-empty',
                  ),
                  _sceneButton(
                    'Ask',
                    _VoiceScene.ask,
                    'voice-gallery-scene-ask',
                  ),
                  TextButton(
                    key: const ValueKey('voice-gallery-hide-menu'),
                    onPressed: () => setState(() => _showMenu = false),
                    child: const Text('Hide menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sceneButton(String label, _VoiceScene scene, String keyName) {
    final selected = _scene == scene;
    return TextButton(
      key: ValueKey(keyName),
      onPressed: () => _applyScene(scene),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? DashboardTheme.accent : Colors.white70,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
