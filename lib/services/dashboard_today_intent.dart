/// Narrow, read-only questions for the dashboard voice spike.
///
/// [dashboardVoiceAsksForToday] matches "what's on today" and close
/// synonyms. [dashboardVoiceQuestion] also matches a single calendar day.
/// Create, delete, and remind phrases stay unmatched. Weekdays, tomorrow,
/// and ranges stay unmatched too.
///
/// Date rule, compared with the household's current day:
/// - A month and day with no year means the next occurrence on or after
///   today. If that day has already passed this year, it rolls to the same
///   month and day next year. A day that does not exist in a year (29
///   February) skips to the next year that has it, at most eight years ahead.
/// - A day of the month with no month ("the 23rd", "23rd") means the next
///   occurrence on or after today: this month when that day is today or
///   still ahead, otherwise the next month that contains it.
/// - A spoken four-digit year is used as given, including dates already
///   past. An impossible day (32 October, 29 February 2026) does not match.
/// - The phrase must be a schedule question, or just the date. "What's the
///   weather on 23 October" stays unmatched.
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

/// A read-only schedule question, if [raw] is one.
class DashboardVoiceQuestion {
  const DashboardVoiceQuestion.none() : day = null, isToday = false;

  const DashboardVoiceQuestion.today() : day = null, isToday = true;

  DashboardVoiceQuestion.day(DateTime day)
    : day = DateTime(day.year, day.month, day.day),
      isToday = false;

  final DateTime? day;
  final bool isToday;

  bool get matched => isToday || day != null;
}

DashboardVoiceQuestion dashboardVoiceQuestion(
  String raw, {
  required DateTime today,
}) {
  if (dashboardVoiceAsksForToday(raw)) {
    return const DashboardVoiceQuestion.today();
  }

  final text = _prepareDateText(raw);
  if (text.isEmpty || _mutation.hasMatch(text)) {
    return const DashboardVoiceQuestion.none();
  }
  // A today word plus some other day is ambiguous, so leave it unmatched.
  if (RegExp(r'\btoday\b').hasMatch(text)) {
    return const DashboardVoiceQuestion.none();
  }

  final hit = _findAskedDate(text, today);
  if (hit == null) return const DashboardVoiceQuestion.none();

  final remainder = _stripFiller(
    '${text.substring(0, hit.start)} ${text.substring(hit.end)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim(),
  );
  if (!_dateAsks.contains(remainder)) {
    return const DashboardVoiceQuestion.none();
  }
  return DashboardVoiceQuestion.day(hit.day);
}

String _prepareDateText(String raw) {
  var text = raw.toLowerCase().replaceAll(RegExp("[’']"), '');
  text = text
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  text = text.replaceAll(RegExp(r'\bthis evening\b'), 'today');
  text = text.replaceAll(RegExp(r'\btonight\b'), 'today');
  return _stripFiller(text);
}

class _DateHit {
  const _DateHit(this.day, this.start, this.end);

  final DateTime day;
  final int start;
  final int end;
}

const String _monthNames =
    'january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec';

final RegExp _dayThenMonth = RegExp(
  '\\b(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+of)?\\s+($_monthNames)\\b(?:\\s+(\\d{4}))?',
);

final RegExp _monthThenDay = RegExp(
  '\\b($_monthNames)\\s+(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\b(?:\\s+(\\d{4}))?',
);

/// "the 23rd", "23rd", or "the 23". A bare number is not a day.
final RegExp _dayOnly = RegExp(
  r'\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)\b|\bthe\s+(\d{1,2})\b',
);

const Map<String, int> _monthNumbers = {
  'january': 1,
  'jan': 1,
  'february': 2,
  'feb': 2,
  'march': 3,
  'mar': 3,
  'april': 4,
  'apr': 4,
  'may': 5,
  'june': 6,
  'jun': 6,
  'july': 7,
  'jul': 7,
  'august': 8,
  'aug': 8,
  'september': 9,
  'sept': 9,
  'sep': 9,
  'october': 10,
  'oct': 10,
  'november': 11,
  'nov': 11,
  'december': 12,
  'dec': 12,
};

_DateHit? _findAskedDate(String text, DateTime today) {
  final dated = <_DateHit>[];
  var sawInvalidDatedPhrase = false;

  void consider(RegExp pattern, _DateHit? Function(RegExpMatch match) read) {
    for (final match in pattern.allMatches(text)) {
      final hit = read(match);
      if (hit == null) {
        sawInvalidDatedPhrase = true;
      } else {
        dated.add(hit);
      }
    }
  }

  consider(_dayThenMonth, (match) {
    return _hitFor(
      today: today,
      day: int.parse(match.group(1)!),
      month: _monthNumbers[match.group(2)!],
      year: _optionalYear(match.group(3)),
      start: match.start,
      end: match.end,
    );
  });
  consider(_monthThenDay, (match) {
    return _hitFor(
      today: today,
      day: int.parse(match.group(2)!),
      month: _monthNumbers[match.group(1)!],
      year: _optionalYear(match.group(3)),
      start: match.start,
      end: match.end,
    );
  });

  if (dated.isNotEmpty) {
    dated.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return (b.end - b.start).compareTo(a.end - a.start);
    });
    return dated.first;
  }
  if (sawInvalidDatedPhrase) return null;

  for (final match in _dayOnly.allMatches(text)) {
    final rawDay = match.group(1) ?? match.group(2);
    if (rawDay == null) continue;
    final hit = _hitFor(
      today: today,
      day: int.parse(rawDay),
      start: match.start,
      end: match.end,
    );
    if (hit != null) return hit;
  }
  return null;
}

int? _optionalYear(String? raw) {
  if (raw == null) return null;
  return int.parse(raw);
}

_DateHit? _hitFor({
  required DateTime today,
  required int day,
  int? month,
  int? year,
  required int start,
  required int end,
}) {
  final resolved = _resolveAskedDay(
    today: today,
    day: day,
    month: month,
    year: year,
  );
  if (resolved == null) return null;
  return _DateHit(resolved, start, end);
}

DateTime? _resolveAskedDay({
  required DateTime today,
  required int day,
  int? month,
  int? year,
}) {
  if (day < 1 || day > 31) return null;
  final todayDate = DateTime(today.year, today.month, today.day);

  if (month == null) {
    var cursor = DateTime(todayDate.year, todayDate.month, 1);
    for (var i = 0; i < 14; i++) {
      if (_isRealDate(cursor.year, cursor.month, day)) {
        final date = DateTime(cursor.year, cursor.month, day);
        if (!date.isBefore(todayDate)) return date;
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return null;
  }

  if (month < 1 || month > 12) return null;
  if (year != null) {
    if (!_isRealDate(year, month, day)) return null;
    return DateTime(year, month, day);
  }

  for (var y = todayDate.year; y <= todayDate.year + 8; y++) {
    if (!_isRealDate(y, month, day)) continue;
    final date = DateTime(y, month, day);
    if (!date.isBefore(todayDate)) return date;
  }
  return null;
}

bool _isRealDate(int year, int month, int day) {
  if (year < 1900 || year > 2100) return false;
  final probe = DateTime(year, month, day);
  return probe.year == year && probe.month == month && probe.day == day;
}

/// What may be left once the date words are removed.
const Set<String> _dateAsks = {
  '',
  'whats on',
  'whats on for',
  'what is on',
  'what is on for',
  'whats happening',
  'whats happening on',
  'what is happening',
  'what is happening on',
  'whats planned',
  'whats planned for',
  'what is planned',
  'what is planned for',
  'whats going on',
  'what is going on',
  'whats the plan',
  'whats the plan for',
  'what is the plan',
  'what is the plan for',
  'whats the agenda',
  'whats the agenda for',
  'what do we have',
  'what do we have on',
  'what do we have planned',
  'what do we have planned for',
  'what do i have',
  'what do i have on',
  'what have we got',
  'what have we got on',
  'what have we got planned',
  'what have i got',
  'what have i got on',
  'what have i got planned',
  'what have i got planned for',
  'what are we doing',
  'what are we doing on',
  'what am i doing',
  'what am i doing on',
  'what are we up to',
  'what are we up to on',
  'anything on',
  'anything on for',
  'anything planned',
  'anything planned for',
  'anything happening',
  'anything happening on',
  'show',
  'show me',
  'show me whats on',
  'whats on the calendar',
  'whats on the calendar for',
  'whats on the schedule',
  'whats on the schedule for',
  'whats on our calendar',
  'whats on our calendar for',
  'whats our schedule',
  'whats our schedule for',
  'whats our plan',
  'whats our plan for',
};
