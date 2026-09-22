import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/dashboard_today_intent.dart';
import '../../theme/calendar_colors.dart';
import '../calendar_split_pill.dart';
import 'dashboard_calendar_overview.dart';
import 'dashboard_chrome.dart';
import 'dashboard_theme.dart';

/// Dismissible glass card for a "what's on …" answer.
///
/// Same family as the LOOK AHEAD day detail: dark scrim, glass card, and
/// split-pill event chips. Horizontal drags are claimed so the slide
/// PageView does not swipe while the card is open.
class DashboardTodayAnswerLayer extends StatelessWidget {
  const DashboardTodayAnswerLayer({
    super.key,
    required this.metrics,
    required this.day,
    required this.events,
    required this.palette,
    required this.onClose,
    this.transcript = '',
    this.labelAsToday = true,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final VoidCallback onClose;
  final String transcript;

  /// Prefixes the heading with "Today" for the household's current day.
  final bool labelAsToday;

  static const barrierKey = ValueKey('dashboard-today-answer-barrier');
  static const cardKey = ValueKey('dashboard-today-answer');
  static const closeKey = ValueKey('dashboard-today-answer-close');
  static const emptyKey = ValueKey('dashboard-today-answer-empty');
  static const eventsKey = ValueKey('dashboard-today-answer-events');

  @override
  Widget build(BuildContext context) {
    return _VoiceScrim(
      barrierKey: barrierKey,
      onDismiss: onClose,
      child: _TodayAnswerCard(
        metrics: metrics,
        day: day,
        events: events,
        palette: palette,
        transcript: transcript,
        labelAsToday: labelAsToday,
        onClose: onClose,
      ),
    );
  }
}

/// Typed fallback when speech recognition is missing, blocked, or unheard.
class DashboardVoicePromptLayer extends StatelessWidget {
  const DashboardVoicePromptLayer({
    super.key,
    required this.metrics,
    required this.today,
    required this.notice,
    required this.controller,
    required this.onClose,
    required this.onSubmit,
    required this.onShowToday,
  });

  final DashboardMetrics metrics;
  final DateTime today;
  final String notice;
  final TextEditingController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;

  /// Opens today's events when the field is empty or not a question.
  final VoidCallback onShowToday;

  static const barrierKey = ValueKey('dashboard-voice-prompt-barrier');
  static const cardKey = ValueKey('dashboard-voice-prompt');
  static const fieldKey = ValueKey('dashboard-voice-prompt-field');
  static const submitKey = ValueKey('dashboard-voice-prompt-submit');
  static const closeKey = ValueKey('dashboard-voice-prompt-close');

  @override
  Widget build(BuildContext context) {
    return _VoiceScrim(
      barrierKey: barrierKey,
      onDismiss: onClose,
      child: _VoicePromptCard(
        metrics: metrics,
        today: today,
        notice: notice,
        controller: controller,
        onClose: onClose,
        onSubmit: onSubmit,
        onShowToday: onShowToday,
      ),
    );
  }
}

class _VoiceScrim extends StatelessWidget {
  const _VoiceScrim({
    required this.barrierKey,
    required this.onDismiss,
    required this.child,
  });

  final Key barrierKey;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        key: barrierKey,
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        child: ColoredBox(
          color: const Color(0xCC07070C),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 96, 28, 36),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                onHorizontalDragStart: (_) {},
                onHorizontalDragUpdate: (_) {},
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayAnswerCard extends StatelessWidget {
  const _TodayAnswerCard({
    required this.metrics,
    required this.day,
    required this.events,
    required this.palette,
    required this.transcript,
    required this.labelAsToday,
    required this.onClose,
  });

  final DashboardMetrics metrics;
  final DateTime day;
  final List<Map<String, dynamic>> events;
  final HubMemberPalette palette;
  final String transcript;
  final bool labelAsToday;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE d MMMM').format(day);
    final heading = labelAsToday ? 'Today · $dateLabel' : dateLabel;
    final heard = transcript.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(560.0, constraints.maxWidth);
        final desired = events.isEmpty
            ? (metrics.isCompact ? 250.0 : 240.0)
            : (metrics.isCompact ? 480.0 : 460.0);
        final height = math.min(desired, constraints.maxHeight);

        return SizedBox(
          width: width,
          height: height,
          child: DashboardGlassCard(
            tint: DashboardTheme.schedule,
            emphasized: true,
            padding: EdgeInsets.all(metrics.isCompact ? 16 : 22),
            child: Column(
              key: DashboardTodayAnswerLayer.cardKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: metrics.isCompact ? 18 : 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      key: DashboardTodayAnswerLayer.closeKey,
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  events.isEmpty
                      ? 'Nothing planned'
                      : events.length == 1
                      ? '1 plan'
                      : '${events.length} plans',
                  style: const TextStyle(
                    color: DashboardTheme.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                if (heard.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Heard: $heard',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DashboardTheme.inkFaint,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                SizedBox(height: metrics.isCompact ? 12 : 16),
                Expanded(child: _body()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body() {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Free day — nothing on the calendar',
          key: DashboardTodayAnswerLayer.emptyKey,
          style: TextStyle(
            color: DashboardTheme.inkFaint,
            fontSize: 18,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return ListView.separated(
      key: DashboardTodayAnswerLayer.eventsKey,
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        return CalendarSplitPill(
          style: CalendarColors.fromMap(event, palette: palette),
          title: dashboardGlanceTitle(event),
          subtitle: dashboardGlanceTimeLabel(event),
          density: metrics.isCompact
              ? CalendarSplitPillDensity.regular
              : CalendarSplitPillDensity.comfortable,
          trailing: Icon(_eventIcon(event), size: 16),
        );
      },
    );
  }

  IconData _eventIcon(Map<String, dynamic> event) {
    switch (event['category']) {
      case 'birthday':
        return Icons.cake_rounded;
      case 'meal':
        return Icons.restaurant;
      case 'work':
        return Icons.work_outline;
      default:
        return Icons.circle;
    }
  }
}

class _VoicePromptCard extends StatelessWidget {
  const _VoicePromptCard({
    required this.metrics,
    required this.today,
    required this.notice,
    required this.controller,
    required this.onClose,
    required this.onSubmit,
    required this.onShowToday,
  });

  final DashboardMetrics metrics;
  final DateTime today;
  final String notice;
  final TextEditingController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;
  final VoidCallback onShowToday;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(560.0, constraints.maxWidth);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: DashboardGlassCard(
            tint: DashboardTheme.schedule,
            emphasized: true,
            padding: EdgeInsets.all(metrics.isCompact ? 16 : 22),
            child: Column(
              key: DashboardVoicePromptLayer.cardKey,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ask the hub',
                        style: TextStyle(
                          color: DashboardTheme.ink,
                          fontSize: metrics.isCompact ? 18 : 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: DashboardVoicePromptLayer.closeKey,
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  notice,
                  style: const TextStyle(
                    color: DashboardTheme.inkMuted,
                    fontSize: 18,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  key: DashboardVoicePromptLayer.fieldKey,
                  controller: controller,
                  autofocus: controller.text.trim().isEmpty,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  cursorColor: DashboardTheme.accent,
                  decoration: InputDecoration(
                    hintText: "what's on today, or 23 October",
                    hintStyle: const TextStyle(color: DashboardTheme.inkFaint),
                    filled: true,
                    fillColor: DashboardTheme.fade(Colors.white, 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: DashboardTheme.schedule,
                      ),
                    ),
                  ),
                  onSubmitted: onSubmit,
                ),
                const SizedBox(height: 14),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final label = dashboardVoicePromptActionLabel(
                      controller.text,
                      today: today,
                    );
                    return Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: DashboardVoicePromptLayer.submitKey,
                        style: FilledButton.styleFrom(
                          backgroundColor: DashboardTheme.schedule,
                          foregroundColor: const Color(0xFF102033),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () => _activateVoicePrompt(
                          controller: controller,
                          today: today,
                          onShowToday: onShowToday,
                          onSubmit: onSubmit,
                        ),
                        child: Text(label),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Button label for the typed prompt.
///
/// A recognised other day is named on the button. Anything else stays
/// "Show today", including an empty field and a phrase the hub cannot
/// answer — that tap must still open today's events.
String dashboardVoicePromptActionLabel(String raw, {required DateTime today}) {
  final question = dashboardVoiceQuestion(raw, today: today);
  final day = question.day;
  if (question.matched && day != null) {
    return 'Show ${DateFormat('d MMMM').format(day)}';
  }
  return 'Show today';
}

void _activateVoicePrompt({
  required TextEditingController controller,
  required DateTime today,
  required VoidCallback onShowToday,
  required ValueChanged<String> onSubmit,
}) {
  final text = controller.text.trim();
  final question = dashboardVoiceQuestion(text, today: today);
  if (text.isEmpty || !question.matched) {
    onShowToday();
    return;
  }
  onSubmit(text);
}
