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
  });

  final DashboardVoicePhase phase;
  final String transcript;
  final String notice;
  final List<Map<String, dynamic>> events;

  static const speechUnavailableNotice = 'Speech not available — try Chrome';
  static const micBlockedNotice =
      'Microphone blocked. Type a question, or allow the mic in Chrome.';
  static const emptyNotice =
      'Didn’t catch that. Try “what’s on today”, or type it below.';
  static const unrecognizedNotice = 'I can answer “what’s on today”.';

  bool get holdsControls => phase != DashboardVoicePhase.idle;

  const DashboardVoiceState.listening()
    : phase = DashboardVoicePhase.listening,
      transcript = '',
      notice = '',
      events = const [];

  DashboardVoiceState applyCapture(
    DashboardSpeechCapture capture,
    List<Map<String, dynamic>> todayEvents,
  ) {
    switch (capture.outcome) {
      case DashboardSpeechOutcome.transcript:
        final heard = capture.transcript.trim();
        if (heard.isEmpty) {
          return const DashboardVoiceState(
            phase: DashboardVoicePhase.fallback,
            notice: emptyNotice,
          );
        }
        return fromTranscript(heard, todayEvents);
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
    List<Map<String, dynamic>> todayEvents,
  ) {
    final text = raw.trim();
    if (text.isEmpty) {
      return DashboardVoiceState(
        phase: DashboardVoicePhase.fallback,
        notice: notice.isEmpty ? unrecognizedNotice : notice,
      );
    }
    return fromTranscript(text, todayEvents);
  }

  DashboardVoiceState fromTranscript(
    String text,
    List<Map<String, dynamic>> todayEvents,
  ) {
    if (dashboardVoiceAsksForToday(text)) {
      return DashboardVoiceState(
        phase: DashboardVoicePhase.answer,
        transcript: text.trim(),
        events: todayEvents,
      );
    }
    return DashboardVoiceState(
      phase: DashboardVoicePhase.unrecognized,
      transcript: text.trim(),
      notice: unrecognizedNotice,
    );
  }
}
