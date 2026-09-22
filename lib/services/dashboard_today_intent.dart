/// Narrow, read-only intent for the dashboard voice spike.
///
/// Matches "what's on today" and close synonyms. Anything that asks to
/// create or change a plan, or that names another day, stays unmatched so
/// a later spike can own those phrases.
bool dashboardVoiceAsksForToday(String raw) {
  var text = _normalize(raw);
  if (text.isEmpty) return false;

  text = text.replaceAll(RegExp(r'\bthis evening\b'), 'today');
  text = text.replaceAll(RegExp(r'\btonight\b'), 'today');

  if (_mutation.hasMatch(text)) return false;
  if (_otherDay.hasMatch(text)) return false;

  text = _stripFiller(text);
  return _todayPhrases.contains(text);
}

String _normalize(String raw) {
  final lower = raw.toLowerCase().replaceAll(RegExp("[’']"), '');
  return lower
      .replaceAll(RegExp(r'[^a-z\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripFiller(String text) {
  final leading = RegExp(
    r'^(please|hey|hi|ok|okay|so|um|uh|lovehub|can you|could you|would you|will you|tell me)\s+',
  );
  final trailing = RegExp(r'\s+(please|thanks|thank you)$');
  var current = text;
  for (var i = 0; i < 4; i++) {
    final next = current.replaceFirst(leading, '').replaceFirst(trailing, '');
    if (next == current) break;
    current = next.trim();
  }
  return current;
}

final RegExp _mutation = RegExp(
  r'\b(add|create|delete|remove|cancel|book|remind|reschedule)\b|\b(new|make) (a )?(task|event|plan)\b',
);

final RegExp _otherDay = RegExp(
  r'\b(tomorrow|yesterday|week|weekend|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
);

const Set<String> _todayPhrases = {
  'whats on today',
  'what is on today',
  'whats happening today',
  'what is happening today',
  'whats planned today',
  'what is planned today',
  'whats planned for today',
  'what is planned for today',
  'whats going on today',
  'what is going on today',
  'whats the plan today',
  'what is the plan today',
  'whats the plan for today',
  'what is the plan for today',
  'whats the agenda today',
  'whats the agenda for today',
  'whats on for today',
  'whats on the calendar today',
  'whats on the calendar for today',
  'whats on the schedule today',
  'whats on our calendar today',
  'whats our schedule today',
  'whats our plan today',
  'whats todays schedule',
  'what is todays schedule',
  'todays schedule',
  'today schedule',
  'schedule today',
  'schedule for today',
  'the schedule today',
  'the schedule for today',
  'todays plans',
  'plans for today',
  'our plans for today',
  'todays agenda',
  'agenda for today',
  'todays events',
  'todays calendar',
  'calendar for today',
  'what do we have today',
  'what do we have on today',
  'what do we have planned today',
  'what have we got today',
  'what have we got on today',
  'what have we got planned today',
  'what are we doing today',
  'what are we up to today',
  'anything on today',
  'anything planned today',
  'anything happening today',
  'anything on for today',
  'show today',
  'show todays schedule',
  'show todays events',
  'show todays plans',
  'show me today',
  'show me todays schedule',
  'show me todays events',
  'whats today looking like',
  'what is today looking like',
};
