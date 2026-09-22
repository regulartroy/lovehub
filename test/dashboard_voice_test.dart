import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/dashboard_today_intent.dart';
import 'package:lovehub/services/dashboard_voice.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

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
    ).submitTyped("  what's on today  ", events, today: DateTime(2026, 9, 22));

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.events.single['summary'], 'Early shift');
    expect(state.answerDay, DateTime(2026, 9, 22));
  });

  test('show today ignores an unrecognized transcript', () {
    const events = [
      {'summary': 'Early shift'},
    ];
    final state = const DashboardVoiceState(
      phase: DashboardVoicePhase.unrecognized,
      transcript: 'what have I got on 23rd of October',
      notice: DashboardVoiceState.unrecognizedNotice,
    ).showToday(events, day: DateTime(2026, 9, 22, 17, 30));

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.transcript, isEmpty);
    expect(state.events, events);
    expect(state.answerDay, DateTime(2026, 9, 22));
  });

  test('date questions resolve to one calendar day', () {
    final today = DateTime(2026, 9, 22);

    expect(
      dashboardVoiceQuestion(
        'what have I got on 23rd of October',
        today: today,
      ).day,
      DateTime(2026, 10, 23),
    );
    expect(
      dashboardVoiceQuestion("what's on October 23", today: today).day,
      DateTime(2026, 10, 23),
    );
    expect(
      dashboardVoiceQuestion("what's on Oct 23rd?", today: today).day,
      DateTime(2026, 10, 23),
    );
    expect(
      dashboardVoiceQuestion("what's on the 23rd", today: today).day,
      DateTime(2026, 9, 23),
    );
    expect(
      dashboardVoiceQuestion(
        "what's on the 23rd",
        today: DateTime(2026, 10, 1),
      ).day,
      DateTime(2026, 10, 23),
    );
    expect(
      dashboardVoiceQuestion("what's on the 21st", today: today).day,
      DateTime(2026, 10, 21),
    );
    expect(
      dashboardVoiceQuestion('1st of September', today: today).day,
      DateTime(2027, 9, 1),
    );
    expect(
      dashboardVoiceQuestion("what's on October 23 2024", today: today).day,
      DateTime(2024, 10, 23),
    );
    expect(
      dashboardVoiceQuestion("what's on February 29", today: today).day,
      DateTime(2028, 2, 29),
    );
    expect(
      dashboardVoiceQuestion("what's on today", today: today).isToday,
      isTrue,
    );
  });

  test('dates that are not a schedule question stay unmatched', () {
    final today = DateTime(2026, 9, 22);
    const phrases = [
      "what's the weather on October 23",
      'add lunch on October 23',
      "what's on tomorrow",
      "what's on Monday",
      '32nd of October',
      "what's on February 29 2026",
      'hello',
    ];

    for (final phrase in phrases) {
      expect(
        dashboardVoiceQuestion(phrase, today: today).matched,
        isFalse,
        reason: phrase,
      );
    }
  });

  test('a spoken date keeps that day’s events', () {
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.transcript,
        transcript: 'what have I got on 23rd of October',
      ),
      const [
        {'summary': 'Early shift'},
      ],
      today: DateTime(2026, 9, 22),
      eventsOn: (day) {
        if (day == DateTime(2026, 10, 23)) {
          return const [
            {'summary': 'Half-term train'},
          ];
        }
        return const [
          {'summary': 'Early shift'},
        ];
      },
    );

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.answerDay, DateTime(2026, 10, 23));
    expect(state.transcript, 'what have I got on 23rd of October');
    expect(state.events.single['summary'], 'Half-term train');
    expect(state.isWeekAnswer, isFalse);
  });

  test('week-of-date phrases match and day phrases stay single days', () {
    final today = DateTime(2026, 9, 22);
    const weekPhrases = [
      "what’s on the week of 23 October",
      "what's on the week of 23 October",
      'show me the week of the 23rd',
      'week of October 23rd',
      'Week of Oct 23',
      "what's happening the week of 23 October",
      "what's planned for the week of October 23",
      'show the week containing 23 October',
      'what have I got the week of the 23rd of October',
      'anything on for the week of Oct 23rd',
      'during the week of 23 October',
      'please show me the week of 23rd of October',
    ];

    for (final phrase in weekPhrases) {
      final question = dashboardVoiceQuestion(phrase, today: today);
      expect(question.isWeek, isTrue, reason: phrase);
      expect(question.matched, isTrue, reason: phrase);
      expect(question.isToday, isFalse, reason: phrase);
    }

    expect(
      dashboardVoiceQuestion(
        "what’s on the week of 23 October",
        today: today,
      ).day,
      DateTime(2026, 10, 23),
    );
    expect(
      dashboardVoiceQuestion('show me the week of the 23rd', today: today).day,
      DateTime(2026, 9, 23),
    );
    expect(
      dashboardVoiceQuestion('week of October 23rd', today: today).day,
      DateTime(2026, 10, 23),
    );

    final day = dashboardVoiceQuestion("what's on 23 October", today: today);
    expect(day.isWeek, isFalse);
    expect(day.day, DateTime(2026, 10, 23));
    expect(
      dashboardVoiceQuestion("what's on the 23rd", today: today).isWeek,
      isFalse,
    );
    expect(
      dashboardVoiceQuestion("what's on today", today: today).isToday,
      isTrue,
    );
  });

  test('a named date resolves to the Monday–Sunday week that contains it', () {
    final today = DateTime(2026, 9, 22);

    void expectWeek(String phrase, DateTime anchor, DateTime monday) {
      final question = dashboardVoiceQuestion(phrase, today: today);
      expect(question.day, anchor, reason: phrase);
      final week = question.householdWeek!;
      expect(week.monday, monday, reason: phrase);
      expect(week.sunday, monday.addCalendarDays(6), reason: phrase);
      expect(week.days, hasLength(7));
      expect(week.days.first.weekday, DateTime.monday);
      expect(week.days.last.weekday, DateTime.sunday);
      expect(week.monday, dashboardMondayOf(anchor), reason: phrase);
      expect(week.contains(anchor), isTrue);
      expect(week.contains(week.sunday), isTrue);
      expect(week.contains(week.sunday.addCalendarDays(1)), isFalse);
    }

    expectWeek(
      "what's on the week of 23 October",
      DateTime(2026, 10, 23),
      DateTime(2026, 10, 19),
    );
    expectWeek(
      'week of 19 October',
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 19),
    );
    expectWeek(
      'week of 25 October',
      DateTime(2026, 10, 25),
      DateTime(2026, 10, 19),
    );
    expectWeek(
      'week of 1 October',
      DateTime(2026, 10, 1),
      DateTime(2026, 9, 28),
    );
    expect(
      dashboardVoiceQuestion(
        'week of 1 October',
        today: today,
      ).householdWeek!.sunday,
      DateTime(2026, 10, 4),
    );
    expectWeek(
      'week of October 23 2024',
      DateTime(2024, 10, 23),
      DateTime(2024, 10, 21),
    );
    expect(
      dashboardVoiceQuestion(
        'week of February 29',
        today: today,
      ).householdWeek!.monday,
      dashboardMondayOf(DateTime(2028, 2, 29)),
    );

    for (final day in [
      DateTime(2026, 9, 22),
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 25),
      DateTime(2026, 10, 26),
      DateTime(2026, 3, 29),
      DateTime(2026, 12, 31),
    ]) {
      expect(
        dashboardHouseholdMonday(day),
        dashboardMondayOf(day),
        reason: '$day',
      );
    }
  });

  test('this week, ranges, and non-schedule week phrases stay unmatched', () {
    final today = DateTime(2026, 9, 22);
    const phrases = [
      "what's on this week",
      "what's on next week",
      "what's on the weekend",
      "what's on Monday",
      "what's the weather the week of 23 October",
      'add lunch the week of October 23',
      'week of 32 October',
      "what's on February 29 2026",
      'week of February 29 2026',
      "what's on the week of today",
      "what's on 23 October and 30 October",
    ];

    for (final phrase in phrases) {
      expect(
        dashboardVoiceQuestion(phrase, today: today).matched,
        isFalse,
        reason: phrase,
      );
    }
  });

  test('a spoken week keeps each day’s events', () {
    final state = const DashboardVoiceState().applyCapture(
      const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.transcript,
        transcript: "what's on the week of 23 October",
      ),
      const [
        {'summary': 'Early shift'},
      ],
      today: DateTime(2026, 9, 22),
      eventsOn: (day) {
        if (day == DateTime(2026, 10, 23)) {
          return const [
            {'summary': 'Half-term train'},
          ];
        }
        if (day == DateTime(2026, 10, 21)) {
          return const [
            {'summary': 'School pickup'},
          ];
        }
        return const [];
      },
    );

    expect(state.phase, DashboardVoicePhase.answer);
    expect(state.isWeekAnswer, isTrue);
    expect(state.answerDay, DateTime(2026, 10, 23));
    expect(state.answerWeekStart, DateTime(2026, 10, 19));
    expect(state.events, isEmpty);
    expect(state.weekEvents, hasLength(7));
    expect(state.weekEvents[0], isEmpty);
    expect(state.weekEvents[2].single['summary'], 'School pickup');
    expect(state.weekEvents[4].single['summary'], 'Half-term train');
    expect(state.transcript, "what's on the week of 23 October");
  });

  test('show week from a day answer opens that day’s household week', () {
    final day = const DashboardVoiceState().answerQuestion(
      'what have I got on 23rd of October',
      today: DateTime(2026, 9, 22),
      eventsOn: (date) => date == DateTime(2026, 10, 23)
          ? const [
              {'summary': 'Half-term train'},
            ]
          : const [],
    );

    final week = day.showWeekContaining(
      day.answerDay!,
      eventsOn: (date) => date == DateTime(2026, 10, 19)
          ? const [
              {'summary': 'Monday meeting'},
            ]
          : date == DateTime(2026, 10, 23)
          ? const [
              {'summary': 'Half-term train'},
            ]
          : const [],
    );

    expect(week.phase, DashboardVoicePhase.answer);
    expect(week.transcript, 'what have I got on 23rd of October');
    expect(week.answerWeekStart, DateTime(2026, 10, 19));
    expect(week.answerDay, DateTime(2026, 10, 23));
    expect(week.weekEvents.first.single['summary'], 'Monday meeting');
    expect(week.weekEvents[4].single['summary'], 'Half-term train');
  });
}

extension on DateTime {
  DateTime addCalendarDays(int days) => DateTime(year, month, day + days);
}
