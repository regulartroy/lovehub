import 'dashboard_today_intent.dart';

enum DashboardSpeechOutcome { transcript, unavailable, denied, empty, error }

class DashboardSpeechCapture {
  const DashboardSpeechCapture({
    required this.outcome,
    this.transcript = '',
    this.message = '',
  });

  final DashboardSpeechOutcome outcome;
  final String transcript;
  final String message;
}

abstract class DashboardSpeechRecognizer {
  bool get isSupported;

  Future<DashboardSpeechCapture> listen();

  void cancel();
}

/// Used on non-web targets and when the browser has no Speech Recognition.
class UnavailableDashboardSpeechRecognizer
    implements DashboardSpeechRecognizer {
  const UnavailableDashboardSpeechRecognizer();

  @override
  bool get isSupported => false;

  @override
  Future<DashboardSpeechCapture> listen() async {
    return const DashboardSpeechCapture(
      outcome: DashboardSpeechOutcome.unavailable,
      message: DashboardVoiceState.speechUnavailableNotice,
    );
  }

  @override
  void cancel() {}
}

enum DashboardVoicePhase { idle, listening, answer, fallback, unrecognized }

/// What the dashboard should show after a mic tap or a typed question.
class DashboardVoiceState {
  const DashboardVoiceState({
    this.phase = DashboardVoicePhase.idle,
    this.transcript = '',
    this.notice = '',
    this.events = const [],
    this.answerDay,
  });

  final DashboardVoicePhase phase;
  final String transcript;
  final String notice;
  final List<Map<String, dynamic>> events;

  /// Calendar day for an answer. Null unless [phase] is answer.
  final DateTime? answerDay;

  static const speechUnavailableNotice =
      'Speech not available — try Chrome. You can type a day below.';
  static const micBlockedNotice =
      'Microphone blocked. Type a day below, or allow the mic in Chrome.';
  static const emptyNotice =
      'Didn’t catch that. Try “what’s on today” or “what’s on 23 October”.';
  static const unrecognizedNotice =
      'I can answer “what’s on today”, or a date like “23 October”.';

  bool get holdsControls => phase != DashboardVoicePhase.idle;

  const DashboardVoiceState.listening()
    : phase = DashboardVoicePhase.listening,
      transcript = '',
      notice = '',
      events = const [],
      answerDay = null;

  DashboardVoiceState applyCapture(
    DashboardSpeechCapture capture,
    List<Map<String, dynamic>> todayEvents, {
    DateTime? today,
    List<Map<String, dynamic>> Function(DateTime day)? eventsOn,
  }) {
    switch (capture.outcome) {
      case DashboardSpeechOutcome.transcript:
        final heard = capture.transcript.trim();
        if (heard.isEmpty) {
          return const DashboardVoiceState(
            phase: DashboardVoicePhase.fallback,
            notice: emptyNotice,
          );
        }
        return answerQuestion(
          heard,
          today: today ?? DateTime.now(),
          todayEvents: todayEvents,
          eventsOn: eventsOn,
        );
      case DashboardSpeechOutcome.unavailable:
      case DashboardSpeechOutcome.error:
        return const DashboardVoiceState(
          phase: DashboardVoicePhase.fallback,
          notice: speechUnavailableNotice,
        );
      case DashboardSpeechOutcome.denied:
        return const DashboardVoiceState(
          phase: DashboardVoicePhase.fallback,
          notice: micBlockedNotice,
        );
      case DashboardSpeechOutcome.empty:
        return const DashboardVoiceState(
          phase: DashboardVoicePhase.fallback,
          notice: emptyNotice,
        );
    }
  }

  DashboardVoiceState submitTyped(
    String raw,
    List<Map<String, dynamic>> todayEvents, {
    DateTime? today,
    List<Map<String, dynamic>> Function(DateTime day)? eventsOn,
  }) {
    final text = raw.trim();
    final day = today ?? DateTime.now();
    if (text.isEmpty) {
      return showToday(todayEvents, day: day);
    }
    return answerQuestion(
      text,
      today: day,
      todayEvents: todayEvents,
      eventsOn: eventsOn,
    );
  }

  /// Opens today's events directly.
  ///
  /// The prompt's Show today button uses this when the field is empty or
  /// not a schedule question. Re-submitting that text used to stay on the
  /// same unrecognized card, so the tap looked like it did nothing.
  DashboardVoiceState showToday(
    List<Map<String, dynamic>> todayEvents, {
    required DateTime day,
  }) {
    return DashboardVoiceState(
      phase: DashboardVoicePhase.answer,
      events: todayEvents,
      answerDay: DateTime(day.year, day.month, day.day),
    );
  }

  DashboardVoiceState answerQuestion(
    String text, {
    required DateTime today,
    List<Map<String, dynamic>> todayEvents = const [],
    List<Map<String, dynamic>> Function(DateTime day)? eventsOn,
  }) {
    final question = dashboardVoiceQuestion(text, today: today);
    if (!question.matched) {
      return DashboardVoiceState(
        phase: DashboardVoicePhase.unrecognized,
        transcript: text.trim(),
        notice: unrecognizedNotice,
      );
    }
    final day = question.isToday
        ? DateTime(today.year, today.month, today.day)
        : question.day!;
    final events = eventsOn != null
        ? eventsOn(day)
        : (question.isToday ? todayEvents : const <Map<String, dynamic>>[]);
    return DashboardVoiceState(
      phase: DashboardVoicePhase.answer,
      transcript: text.trim(),
      events: events,
      answerDay: day,
    );
  }

  DashboardVoiceState fromTranscript(
    String text,
    List<Map<String, dynamic>> todayEvents, {
    DateTime? today,
    List<Map<String, dynamic>> Function(DateTime day)? eventsOn,
  }) {
    return answerQuestion(
      text,
      today: today ?? DateTime.now(),
      todayEvents: todayEvents,
      eventsOn: eventsOn,
    );
  }
}
