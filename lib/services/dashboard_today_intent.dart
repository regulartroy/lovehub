/// Narrow, read-only questions for the dashboard voice spike.
///
/// [dashboardVoiceAsksForToday] matches "what's on today" and close
/// synonyms. [dashboardVoiceQuestion] also matches:
/// - a single calendar day
/// - the Monday–Sunday household week that contains a named date
///   ("the week of 23 October")
/// - an inclusive date range ("from 20 to 25 October", "1–7 November",
///   "between Friday and Sunday")
///
/// A range is at most [dashboardVoiceRangeDayCap] days. Longer stretches
/// set [DashboardVoiceQuestion.overLongRange] and stay unmatched.
/// Create, delete, and remind phrases stay unmatched. A bare weekday,
/// tomorrow, "this week", and the weekend stay unmatched too.
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

/// Monday–Sunday household week, the same weekday rule as LOOK AHEAD.
///
/// Days are calendar dates, so a week that crosses a clock change still
/// runs Monday through Sunday.
class DashboardHouseholdWeek {
  DashboardHouseholdWeek(DateTime day) : monday = dashboardHouseholdMonday(day);

  final DateTime monday;

  DateTime get sunday => DateTime(monday.year, monday.month, monday.day + 6);

  List<DateTime> get days => List<DateTime>.generate(
    7,
    (index) => DateTime(monday.year, monday.month, monday.day + index),
    growable: false,
  );

  bool contains(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return !date.isBefore(monday) && !date.isAfter(sunday);
  }
}

DateTime dashboardHouseholdMonday(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  return DateTime(
    date.year,
    date.month,
    date.day - (date.weekday - DateTime.monday),
  );
}

/// Inclusive limit for a spoken schedule range. A longer ask is refused
/// with [DashboardVoiceQuestion.overLongRange] instead of a giant card.
const int dashboardVoiceRangeDayCap = 31;

/// A read-only schedule question, if [raw] is one.
class DashboardVoiceQuestion {
  const DashboardVoiceQuestion.none()
    : day = null,
      rangeEnd = null,
      isToday = false,
      isWeek = false,
      overLongRange = false;

  const DashboardVoiceQuestion.today()
    : day = null,
      rangeEnd = null,
      isToday = true,
      isWeek = false,
      overLongRange = false;

  const DashboardVoiceQuestion.overLongRange()
    : day = null,
      rangeEnd = null,
      isToday = false,
      isWeek = false,
      overLongRange = true;

  DashboardVoiceQuestion.day(DateTime day)
    : day = DateTime(day.year, day.month, day.day),
      rangeEnd = null,
      isToday = false,
      isWeek = false,
      overLongRange = false;

  DashboardVoiceQuestion.week(DateTime day)
    : day = DateTime(day.year, day.month, day.day),
      rangeEnd = null,
      isToday = false,
      isWeek = true,
      overLongRange = false;

  DashboardVoiceQuestion.range(DateTime start, DateTime end)
    : day = DateTime(start.year, start.month, start.day),
      rangeEnd = DateTime(end.year, end.month, end.day),
      isToday = false,
      isWeek = false,
      overLongRange = false;

  /// For a day, that calendar day. For a week, the named date inside it.
  /// For a range, the first day.
  final DateTime? day;

  /// Last day of an inclusive range. Null for today, a single day, or a week.
  final DateTime? rangeEnd;
  final bool isToday;

  /// True when [day] names the date whose household week was asked for.
  final bool isWeek;

  /// True when the phrase was a schedule range longer than
  /// [dashboardVoiceRangeDayCap]. [matched] stays false.
  final bool overLongRange;

  bool get isRange => rangeEnd != null;

  bool get matched => (isToday || day != null) && !overLongRange;

  DashboardHouseholdWeek? get householdWeek {
    if (!isWeek || day == null) return null;
    return DashboardHouseholdWeek(day!);
  }

  /// Inclusive days from [day] through [rangeEnd].
  List<DateTime> get rangeDays {
    final start = day;
    final end = rangeEnd;
    if (start == null || end == null) return const [];
    final days = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end) && days.length <= dashboardVoiceRangeDayCap) {
      days.add(cursor);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return days;
  }
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

  final range = _findAskedRange(text, today);
  if (range != null) {
    if (range.tooLong) return const DashboardVoiceQuestion.overLongRange();
    return DashboardVoiceQuestion.range(range.start, range.end);
  }

  final hit = _findAskedDate(text, today);
  if (hit == null) return const DashboardVoiceQuestion.none();

  final remainder = _stripFiller(
    '${text.substring(0, hit.start)} ${text.substring(hit.end)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim(),
  );
  if (_isWeekOfDateAsk(remainder)) {
    return DashboardVoiceQuestion.week(hit.day);
  }
  if (!_dateAsks.contains(remainder)) {
    return const DashboardVoiceQuestion.none();
  }
  return DashboardVoiceQuestion.day(hit.day);
}

/// "the week of" / "week containing" wrapped around an otherwise normal
/// schedule question. "this week" has no date, so it never reaches here.
final RegExp _weekOfMarker = RegExp(
  r'\b(?:the\s+|this\s+)?week\s+(?:of|containing)\b',
);

bool _isWeekOfDateAsk(String remainder) {
  if (_weekOfMarker.allMatches(remainder).length != 1) return false;
  final stripped = remainder
      .replaceFirst(_weekOfMarker, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (_dateAsks.contains(stripped)) return true;
  final loosened = _stripWeekConnectors(stripped);
  return loosened != stripped && _dateAsks.contains(loosened);
}

/// Words that can sit beside "the week of" without changing the question.
/// Trailing "on" and "for" stay put so "what's on" / "planned for" survive.
String _stripWeekConnectors(String text) {
  final leading = RegExp(r'^(?:during|around|about|over|in|for|on)(?:\s+|$)');
  final trailing = RegExp(r'\s+(?:during|around|about|over)$');
  var current = text;
  for (var i = 0; i < 3; i++) {
    final next = current
        .replaceFirst(leading, '')
        .replaceFirst(trailing, '')
        .trim();
    if (next == current) break;
    current = next;
  }
  return current;
}

String _prepareDateText(String raw) {
  var text = raw.toLowerCase().replaceAll(RegExp("[’']"), '');
  // "1–7 November" and "1-7 November" are the same range as "1 to 7".
  text = text.replaceAll(RegExp(r'[–—−-]'), ' to ');
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

const Set<String> _rangeConnectors = {
  'to',
  'through',
  'thru',
  'until',
  'till',
  'and',
};

const Map<String, int> _weekdayNumbers = {
  'monday': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'friday': DateTime.friday,
  'saturday': DateTime.saturday,
  'sunday': DateTime.sunday,
};

class _RangeHit {
  const _RangeHit(this.start, this.end, {required this.tooLong});

  final DateTime start;
  final DateTime end;
  final bool tooLong;
}

class _Endpoint {
  const _Endpoint({
    required this.consumed,
    this.day,
    this.month,
    this.year,
    this.weekday,
  });

  final int consumed;
  final int? day;
  final int? month;
  final int? year;
  final int? weekday;

  bool get isWeekdayOnly => weekday != null && day == null;
}

class _DatedSpan {
  const _DatedSpan(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// A from/to (or between/and) schedule range, if [text] is one.
///
/// One named month covers both day numbers when they run forward
/// ("20 to 25 October", "October 20 to 25"). A later day number that is
/// lower crosses into the neighbouring month ("28 to 2 November" is
/// 28 October–2 November). Weekdays use the earliest Mon–Sun span whose
/// end is today or still ahead ("between Friday and Sunday" on Saturday
/// is this weekend). An explicit year is kept even when it is already past.
_RangeHit? _findAskedRange(String text, DateTime today) {
  final tokens = text.split(' ');
  if (tokens.length < 3) return null;
  final todayDate = DateTime(today.year, today.month, today.day);

  for (var i = 0; i < tokens.length; i++) {
    if (!_rangeConnectors.contains(tokens[i])) continue;
    final left = _readEndingAt(tokens, i);
    final right = _readEndpoint(tokens, i + 1);
    if (left == null || right == null) continue;

    final span = _resolveRangeEndpoints(left, right, todayDate);
    if (span == null) continue;

    var spanStart = left.start;
    if (spanStart > 0 &&
        (tokens[spanStart - 1] == 'from' ||
            tokens[spanStart - 1] == 'between')) {
      spanStart -= 1;
    }
    final spanEnd = i + 1 + right.consumed;
    final remainder = _stripFiller(
      '${tokens.sublist(0, spanStart).join(' ')} ${tokens.sublist(spanEnd).join(' ')}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
    if (!_dateAsks.contains(remainder)) continue;

    final length = _inclusiveDays(span.start, span.end);
    if (length < 1) continue;
    if (length > dashboardVoiceRangeDayCap) {
      return _RangeHit(span.start, span.end, tooLong: true);
    }
    return _RangeHit(span.start, span.end, tooLong: false);
  }
  return null;
}

class _PlacedEndpoint extends _Endpoint {
  const _PlacedEndpoint({
    required this.start,
    required super.consumed,
    super.day,
    super.month,
    super.year,
    super.weekday,
  });

  final int start;
}

_PlacedEndpoint? _readEndingAt(List<String> tokens, int endExclusive) {
  _PlacedEndpoint? best;
  final earliest = endExclusive > 6 ? endExclusive - 6 : 0;
  for (var start = earliest; start < endExclusive; start++) {
    final read = _readEndpoint(tokens, start);
    if (read == null || start + read.consumed != endExclusive) continue;
    if (best == null || read.consumed > best.consumed) {
      best = _PlacedEndpoint(
        start: start,
        consumed: read.consumed,
        day: read.day,
        month: read.month,
        year: read.year,
        weekday: read.weekday,
      );
    }
  }
  return best;
}

_Endpoint? _readEndpoint(List<String> tokens, int index) {
  if (index >= tokens.length) return null;
  var cursor = index;
  if (tokens[cursor] == 'the') {
    cursor++;
    if (cursor >= tokens.length) return null;
  }

  final weekday = _weekdayNumbers[tokens[cursor]];
  if (weekday != null && cursor == index) {
    final after = _readEndpoint(tokens, cursor + 1);
    if (after != null && after.day != null) {
      return _Endpoint(
        consumed: 1 + after.consumed,
        day: after.day,
        month: after.month,
        year: after.year,
      );
    }
    return _Endpoint(consumed: 1, weekday: weekday);
  }

  final month = _monthNumbers[tokens[cursor]];
  if (month != null) {
    var dayIndex = cursor + 1;
    if (dayIndex < tokens.length && tokens[dayIndex] == 'the') dayIndex++;
    if (dayIndex >= tokens.length) return null;
    final day = _dayNumber(tokens[dayIndex]);
    if (day == null) return null;
    var consumed = dayIndex + 1 - index;
    int? year;
    final yearIndex = dayIndex + 1;
    if (yearIndex < tokens.length && _isYearToken(tokens[yearIndex])) {
      year = int.parse(tokens[yearIndex]);
      consumed = yearIndex + 1 - index;
    }
    return _Endpoint(consumed: consumed, day: day, month: month, year: year);
  }

  final day = _dayNumber(tokens[cursor]);
  if (day == null) return null;
  var next = cursor + 1;
  if (next < tokens.length && tokens[next] == 'of') next++;
  int? endpointMonth;
  int? year;
  var consumed = next - index;
  if (next < tokens.length && _monthNumbers.containsKey(tokens[next])) {
    endpointMonth = _monthNumbers[tokens[next]];
    next++;
    consumed = next - index;
    if (next < tokens.length && _isYearToken(tokens[next])) {
      year = int.parse(tokens[next]);
      consumed = next + 1 - index;
    }
  }
  return _Endpoint(
    consumed: consumed,
    day: day,
    month: endpointMonth,
    year: year,
  );
}

int? _dayNumber(String token) {
  final match = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(token);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  if (day < 1 || day > 31) return null;
  return day;
}

bool _isYearToken(String token) {
  if (!RegExp(r'^\d{4}$').hasMatch(token)) return false;
  final year = int.parse(token);
  return year >= 1900 && year <= 2100;
}

_DatedSpan? _resolveRangeEndpoints(
  _Endpoint left,
  _Endpoint right,
  DateTime today,
) {
  if (left.isWeekdayOnly && right.isWeekdayOnly) {
    return _resolveWeekdayRange(today, left.weekday!, right.weekday!);
  }
  final startDay = left.day;
  final endDay = right.day;
  if (startDay == null || endDay == null) return null;

  if (left.month == null && right.month == null) {
    return _resolveBareDayRange(
      today,
      startDay,
      endDay,
      left.year ?? right.year,
    );
  }
  return _resolveMonthRange(
    today: today,
    startDay: startDay,
    endDay: endDay,
    startMonth: left.month,
    endMonth: right.month,
    year: left.year ?? right.year,
  );
}

_DatedSpan? _resolveWeekdayRange(DateTime today, int startWd, int endWd) {
  final monday = dashboardHouseholdMonday(today);
  for (var week = -1; week <= 8; week++) {
    final weekMonday = DateTime(
      monday.year,
      monday.month,
      monday.day + 7 * week,
    );
    final start = DateTime(
      weekMonday.year,
      weekMonday.month,
      weekMonday.day + (startWd - DateTime.monday),
    );
    var delta = endWd - startWd;
    if (delta < 0) delta += 7;
    final end = DateTime(start.year, start.month, start.day + delta);
    if (!end.isBefore(today)) return _DatedSpan(start, end);
  }
  return null;
}

_DatedSpan? _resolveBareDayRange(
  DateTime today,
  int startDay,
  int endDay,
  int? year,
) {
  if (year != null) {
    for (var month = 1; month <= 12; month++) {
      final span = _bareSpanInMonth(year, month, startDay, endDay);
      if (span != null && !span.end.isBefore(today)) return span;
    }
    for (var month = 1; month <= 12; month++) {
      final span = _bareSpanInMonth(year, month, startDay, endDay);
      if (span != null) return span;
    }
    return null;
  }

  var cursor = DateTime(today.year, today.month, 1);
  for (var i = 0; i < 18; i++) {
    final span = _bareSpanInMonth(cursor.year, cursor.month, startDay, endDay);
    if (span != null && !span.end.isBefore(today)) return span;
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return null;
}

_DatedSpan? _bareSpanInMonth(int year, int month, int startDay, int endDay) {
  if (!_isRealDate(year, month, startDay)) return null;
  final start = DateTime(year, month, startDay);
  if (endDay >= startDay) {
    if (!_isRealDate(year, month, endDay)) return null;
    return _DatedSpan(start, DateTime(year, month, endDay));
  }
  var cursor = DateTime(year, month + 1, 1);
  for (var i = 0; i < 3; i++) {
    if (_isRealDate(cursor.year, cursor.month, endDay)) {
      return _DatedSpan(start, DateTime(cursor.year, cursor.month, endDay));
    }
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return null;
}

_DatedSpan? _resolveMonthRange({
  required DateTime today,
  required int startDay,
  required int endDay,
  required int? startMonth,
  required int? endMonth,
  required int? year,
}) {
  var startMonthValue = startMonth;
  var endMonthValue = endMonth;
  var startYearOffset = 0;
  var endYearOffset = 0;

  if (startMonthValue == null && endMonthValue != null) {
    if (endDay >= startDay) {
      startMonthValue = endMonthValue;
    } else if (endMonthValue == 1) {
      startMonthValue = 12;
      startYearOffset = -1;
    } else {
      startMonthValue = endMonthValue - 1;
    }
  } else if (endMonthValue == null && startMonthValue != null) {
    if (endDay >= startDay) {
      endMonthValue = startMonthValue;
    } else if (startMonthValue == 12) {
      endMonthValue = 1;
      endYearOffset = 1;
    } else {
      endMonthValue = startMonthValue + 1;
    }
  }
  if (startMonthValue == null || endMonthValue == null) return null;

  _DatedSpan? build(int startYear) {
    final startY = startYear + startYearOffset;
    final endY = startYear + endYearOffset;
    if (!_isRealDate(startY, startMonthValue!, startDay)) return null;
    if (!_isRealDate(endY, endMonthValue!, endDay)) return null;
    var start = DateTime(startY, startMonthValue, startDay);
    var end = DateTime(endY, endMonthValue, endDay);
    if (end.isBefore(start)) {
      if (start.month == end.month) {
        final swap = start;
        start = end;
        end = swap;
      } else {
        final rolled = DateTime(end.year + 1, end.month, end.day);
        if (!_isRealDate(rolled.year, rolled.month, rolled.day)) return null;
        end = rolled;
      }
    }
    return _DatedSpan(start, end);
  }

  if (year != null) return build(year);
  for (var y = today.year - 1; y <= today.year + 8; y++) {
    final span = build(y);
    if (span != null && !span.end.isBefore(today)) return span;
  }
  return null;
}

int _inclusiveDays(DateTime start, DateTime end) {
  return DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;
}
