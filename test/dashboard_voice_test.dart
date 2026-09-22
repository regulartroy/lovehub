import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/dashboard_today_intent.dart';
import 'package:lovehub/services/dashboard_voice.dart';

void main() {
  test('today phrases match, including close synonyms', () {
    const phrases = [
      "what's on today",
      "What’s on today?",
      'what is on today',
      "what's happening today",
      "what's planned for today",
      "today's schedule",
      'todays schedule',
      'what do we have today',
      'what have we got on today',
      'what are we doing today',
      'anything on today',
      "show me today's events",
      "can you tell me what's on today",
      "what's on tonight",
      "what's on this evening",
      'schedule for today',
      "what's the plan today",
    ];

    for (final phrase in phrases) {
      expect(dashboardVoiceAsksForToday(phrase), isTrue, reason: phrase);
    }
  });

  test('other days, weather, and create phrases stay out of scope', () {
    const phrases = [
      "what's on tomorrow",
      "what's on today and tomorrow",
      "what's on this week",
      "what's on Monday",
      'add lunch today',
      'create a task for today',
      "what's the weather today",
      'what time is it',
      'hello',
      '',
    ];

    for (final phrase in phrases) {
      expect(dashboardVoiceAsksForToday(phrase), isFalse, reason: phrase);
    }
  });

  test('a today question keeps the events it was given', () {
    final events = [
      {'summary': 'Farmers market walk'},
      {'summary': 'Pasta night'},
    ];
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.transcript,
        transcript: "what's on today",
      ),
      events,
    );

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.transcript, "what's on today");
    expect(state.events, events);
    expect(state.holdsControls, isTrue);
  });

  test('an empty today still answers, with no events', () {
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.transcript,
        transcript: "today's schedule",
      ),
      const [],
    );

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.events, isEmpty);
  });

  test('unsupported speech opens the typed fallback', () {
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(outcome: DashboardSpeechOutcome.unavailable),
      const [],
    );

    expect(state.phase, DashboardVoicePhase.fallback);
    expect(state.notice, DashboardVoiceState.speechUnavailableNotice);
  });

  test('a blocked microphone opens the typed fallback', () {
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(outcome: DashboardSpeechOutcome.denied),
      const [],
    );

    expect(state.phase, DashboardVoicePhase.fallback);
    expect(state.notice, DashboardVoiceState.micBlockedNotice);
  });

  test('create phrases are not answered as today', () {
    final state = const DashboardVoiceState().fromTranscript(
      'add a task today',
      const [
        {'summary': 'Walk'},
      ],
    );

    expect(state.phase, DashboardVoicePhase.unrecognized);
    expect(state.events, isEmpty);
    expect(state.notice, DashboardVoiceState.unrecognizedNotice);
  });

  test('typing a today question from the fallback shows the events', () {
    const events = [
      {'summary': 'Early shift'},
    ];
    final state = const DashboardVoiceState(
      phase: DashboardVoicePhase.fallback,
      notice: DashboardVoiceState.speechUnavailableNotice,
    ).submitTyped("  what's on today  ", events);

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.events.single['summary'], 'Early shift');
  });
}
