// Read-only LoveHub schedule export for other household bots.
//
// Maps stored hub events (and yearly birthday recurrences) into a dated
// window in Europe/London, a JSON snapshot, an ICS calendar, and a
// per-day busy summary for Tom's work. This library does not talk to
// Firestore and has no write path.

import 'london_date.dart';

const lovehubScheduleTimezone = 'Europe/London';
const defaultScheduleExportDays = 56;
const minScheduleExportDays = 1;
const maxScheduleExportDays = 366;
const defaultScheduleExportOutDir = '/home/box/shared/lovehub';

/// Same 06:00 cutoff the dashboard and calendar use for overnight events.
const scheduleOvernightCutoffHour = 6;

/// Local hour where a work day counts as evening rather than daytime.
const scheduleEveningHour = 17;

const scheduleExportMaxDocuments = 5000;

class ScheduleExportException implements Exception {
  ScheduleExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScheduleExportArgsException implements Exception {
  ScheduleExportArgsException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ExportPerson { tom, maria, shared }

enum ExportCategory { work, personal, birthday, meal, other }

enum TomBusy { none, daytime, evening, allDay }

extension TomBusyLabel on TomBusy {
  String get label => switch (this) {
    TomBusy.none => 'none',
    TomBusy.daytime => 'daytime',
    TomBusy.evening => 'evening',
    TomBusy.allDay => 'all-day',
  };
}

class ExportEvent {
  const ExportEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.person,
    required this.category,
    required this.tentative,
    required this.source,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final ExportPerson person;
  final ExportCategory category;
  final bool tentative;
  final String source;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'start': formatLondonIso(start),
    'end': formatLondonIso(end),
    'allDay': allDay,
    'person': person.name,
    'category': category.name,
    'tentative': tentative,
    'source': source,
  };
}

class ExportDaySummary {
  const ExportDaySummary({
    required this.date,
    required this.tomBusy,
    required this.eventCount,
  });

  final LondonDate date;
  final TomBusy tomBusy;
  final int eventCount;

  Map<String, Object> toJson() => {
    'date': date.ymd,
    'tomBusy': tomBusy.label,
    'eventCount': eventCount,
  };
}

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.generatedAt,
    required this.windowStart,
    required this.windowEnd,
    required this.events,
    required this.days,
    this.hubId,
    this.timezone = lovehubScheduleTimezone,
  });

  final DateTime generatedAt;
  final LondonDate windowStart;
  final LondonDate windowEnd;
  final List<ExportEvent> events;
  final List<ExportDaySummary> days;
  final String? hubId;
  final String timezone;

  Map<String, Object?> toJson() => {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'timezone': timezone,
    'windowStart': windowStart.ymd,
    'windowEnd': windowEnd.ymd,
    if (hubId != null) 'hubId': hubId,
    'events': events.map((event) => event.toJson()).toList(),
    'days': days.map((day) => day.toJson()).toList(),
  };
}

class StoredExportEvent {
  const StoredExportEvent({
    required this.id,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    required this.category,
    required this.assignedTo,
    this.status,
    this.source,
  });

  final String id;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String category;
  final String assignedTo;
  final String? status;
  final String? source;
}

class StoredBirthday {
  const StoredBirthday({
    required this.id,
    required this.name,
    required this.month,
    required this.day,
    this.year,
  });

  final String id;
  final String name;
  final int month;
  final int day;
  final int? year;
}

class ScheduleExportCommand {
  const ScheduleExportCommand({
    this.hubId,
    this.outDir = defaultScheduleExportOutDir,
    this.days = defaultScheduleExportDays,
    this.now,
    this.help = false,
  });

  final String? hubId;
  final String outDir;
  final int days;
  final DateTime? now;
  final bool help;
}

ScheduleExportCommand parseScheduleExportArgs(
  List<String> args, {
  Map<String, String> environment = const {},
}) {
  var hubId = environment['HUB_ID'];
  var outDir = defaultScheduleExportOutDir;
  var days = defaultScheduleExportDays;
  DateTime? now;
  var help = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String requireValue() {
      if (i + 1 >= args.length) {
        throw ScheduleExportArgsException('$arg needs a value.');
      }
      return args[++i];
    }

    switch (arg) {
      case '--help':
      case '-h':
        help = true;
      case '--hub':
        hubId = requireValue();
      case '--out-dir':
        outDir = requireValue();
      case '--days':
        days = _parseDays(requireValue());
      case '--now':
        now = _parseNow(requireValue());
      default:
        if (arg.startsWith('-')) {
          throw ScheduleExportArgsException('Unknown argument: $arg');
        }
        throw ScheduleExportArgsException('Unexpected argument: $arg');
    }
  }

  if (help) {
    return ScheduleExportCommand(
      hubId: hubId?.trim(),
      outDir: outDir,
      days: days,
      now: now,
      help: true,
    );
  }

  final trimmedHub = hubId?.trim() ?? '';
  if (trimmedHub.isEmpty) {
    throw ScheduleExportArgsException('Pass --hub <id> or set HUB_ID.');
  }
  final trimmedOut = outDir.trim();
  if (trimmedOut.isEmpty) {
    throw ScheduleExportArgsException('--out-dir must not be empty.');
  }
  return ScheduleExportCommand(
    hubId: trimmedHub,
    outDir: trimmedOut,
    days: days,
    now: now,
  );
}

int _parseDays(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) {
    throw ScheduleExportArgsException('--days must be a whole number.');
  }
  if (value < minScheduleExportDays || value > maxScheduleExportDays) {
    throw ScheduleExportArgsException(
      '--days must be between $minScheduleExportDays and $maxScheduleExportDays.',
    );
  }
  return value;
}

DateTime _parseNow(String raw) {
  try {
    return DateTime.parse(raw.trim()).toUtc();
  } on FormatException {
    throw ScheduleExportArgsException('--now must be an ISO-8601 timestamp.');
  }
}

/// Inclusive window: today through today+[days] on the London calendar.
LondonWindow scheduleExportWindow(DateTime now, {required int days}) {
  final today = londonCivilDate(now);
  return LondonWindow(start: today, end: today.addDays(days));
}

String formatLondonIso(DateTime instant) {
  final utc = instant.toUtc();
  final offsetHours = londonIsBst(utc) ? 1 : 0;
  final local = utc.add(Duration(hours: offsetHours));
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}';
  final time = '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  final offset = offsetHours == 0 ? '+00:00' : '+0$offsetHours:00';
  return '${date}T$time$offset';
}

/// 00:00 Europe/London on [date], as UTC.
DateTime londonStartOfDay(LondonDate date) {
  final noonUtc = DateTime.utc(date.year, date.month, date.day, 12);
  if (londonIsBst(noonUtc)) {
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      0,
    ).subtract(const Duration(hours: 1));
  }
  return DateTime.utc(date.year, date.month, date.day);
}

DateTime londonWallTime(LondonDate date, int hour, [int minute = 0]) {
  return londonStartOfDay(date).add(Duration(hours: hour, minutes: minute));
}

/// Map a stored assignedTo token or uid to tom, maria, or shared.
/// Unknown uids become shared so the snapshot never leaks an identifier.
ExportPerson exportPersonFor(
  String assignedTo,
  Map<String, ExportPerson> peopleByUid,
) {
  final token = assignedTo.trim();
  if (token.isEmpty) return ExportPerson.shared;
  final lower = token.toLowerCase();
  if (lower == 'shared') return ExportPerson.shared;
  if (lower == 'tom') return ExportPerson.tom;
  if (lower == 'maria') return ExportPerson.maria;
  return peopleByUid[token] ?? ExportPerson.shared;
}

/// Build a uid → person map from hub member display names. Names that
/// contain "tom" or "maria" (the same rule the calendar colours use)
/// are kept; anyone else is omitted and later treated as shared.
Map<String, ExportPerson> peopleByUidFromProfiles(
  Map<String, String> namesByUid,
) {
  final mapped = <String, ExportPerson>{};
  for (final entry in namesByUid.entries) {
    final uid = entry.key.trim();
    if (uid.isEmpty || uid == 'shared') continue;
    final lower = entry.value.toLowerCase();
    if (lower.contains('tom')) {
      mapped[uid] = ExportPerson.tom;
    } else if (lower.contains('maria')) {
      mapped[uid] = ExportPerson.maria;
    }
  }
  return mapped;
}

ExportCategory exportCategoryFor(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'work':
      return ExportCategory.work;
    case 'birthday':
      return ExportCategory.birthday;
    case 'meal':
      return ExportCategory.meal;
    case 'general':
    case 'personal':
      return ExportCategory.personal;
    default:
      return ExportCategory.other;
  }
}

String exportSourceFor(String? raw) {
  final value = raw?.trim() ?? '';
  return value.isEmpty ? 'manual' : value;
}

String redactSecrets(String raw) {
  var text = raw;
  text = text.replaceAll(
    RegExp(
      r'\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b',
      caseSensitive: false,
    ),
    '[redacted]',
  );
  return text;
}

bool isTentativeStatus(String? raw) {
  return raw?.trim().toLowerCase() == 'tentative';
}

/// Whether [event] should appear on [day], using the dashboard overnight
/// rule evaluated in Europe/London: a timed event that ends before 06:00
/// the next morning stays on its start day only.
bool exportEventBelongsOnDay(ExportEvent event, LondonDate day) {
  final startDay = londonCivilDate(event.start);
  final effectiveEnd = event.end.isBefore(event.start)
      ? event.start
      : event.end;
  var endDay = londonCivilDate(effectiveEnd);
  // All-day events use an exclusive end when [end] is exactly the start
  // of a later civil day, matching the ICS VALUE=DATE convention.
  if (event.allDay &&
      endDay > startDay &&
      effectiveEnd.toUtc() == londonStartOfDay(endDay)) {
    endDay = endDay.addDays(-1);
  }
  if (day < startDay || day > endDay) return false;
  if (event.allDay || day == startDay) return true;
  final cutoff = londonWallTime(day, scheduleOvernightCutoffHour);
  return !effectiveEnd.isBefore(cutoff);
}

bool exportEventOverlapsWindow(ExportEvent event, LondonWindow window) {
  var day = window.start;
  while (true) {
    if (exportEventBelongsOnDay(event, day)) return true;
    if (day == window.end) return false;
    day = day.addDays(1);
  }
}

TomBusy tomBusyForDay(List<ExportEvent> events, LondonDate day) {
  var daytime = false;
  var evening = false;
  var allDay = false;
  for (final event in events) {
    if (event.person != ExportPerson.tom ||
        event.category != ExportCategory.work) {
      continue;
    }
    if (!exportEventBelongsOnDay(event, day)) continue;
    if (event.allDay) {
      allDay = true;
      continue;
    }
    final start = event.start.toUtc();
    final end = (event.end.isBefore(event.start) ? event.start : event.end)
        .toUtc();
    final dayStart = londonStartOfDay(day);
    final daytimeStart = londonWallTime(day, scheduleOvernightCutoffHour);
    final eveningStart = londonWallTime(day, scheduleEveningHour);
    final overnightEnd = londonWallTime(
      day.addDays(1),
      scheduleOvernightCutoffHour,
    );
    final overlapStart = start.isAfter(dayStart) ? start : dayStart;
    final overlapEnd = end.isBefore(overnightEnd) ? end : overnightEnd;
    if (!overlapEnd.isAfter(overlapStart)) continue;
    if (_rangesOverlap(overlapStart, overlapEnd, daytimeStart, eveningStart)) {
      daytime = true;
    }
    if (_rangesOverlap(overlapStart, overlapEnd, eveningStart, overnightEnd)) {
      evening = true;
    }
  }
  if (allDay || (daytime && evening)) return TomBusy.allDay;
  if (daytime) return TomBusy.daytime;
  if (evening) return TomBusy.evening;
  return TomBusy.none;
}

bool _rangesOverlap(
  DateTime start,
  DateTime end,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return start.isBefore(rangeEnd) && end.isAfter(rangeStart);
}

/// Yearly birthday recurrences that fall inside [window].
List<ExportEvent> expandBirthdays(
  List<StoredBirthday> birthdays,
  LondonWindow window,
) {
  final events = <ExportEvent>[];
  for (final birthday in birthdays) {
    final name = redactSecrets(birthday.name.trim());
    if (name.isEmpty) continue;
    if (birthday.month < 1 ||
        birthday.month > 12 ||
        birthday.day < 1 ||
        birthday.day > 31) {
      continue;
    }
    for (var year = window.start.year; year <= window.end.year; year++) {
      final date = tryParseCivilDate(
        '${year.toString().padLeft(4, '0')}-'
        '${birthday.month.toString().padLeft(2, '0')}-'
        '${birthday.day.toString().padLeft(2, '0')}',
      );
      if (date == null || !window.contains(date)) continue;
      final start = londonStartOfDay(date);
      final end = londonStartOfDay(date.addDays(1));
      final title = birthday.year != null
          ? '$name (${year - birthday.year!})'
          : name;
      events.add(
        ExportEvent(
          id: 'bday_${birthday.id}_$year',
          title: title,
          start: start,
          end: end,
          allDay: true,
          person: ExportPerson.shared,
          category: ExportCategory.birthday,
          tentative: false,
          source: 'birthday',
        ),
      );
    }
  }
  return events;
}

ExportEvent? mapStoredEvent(
  StoredExportEvent event, {
  required Map<String, ExportPerson> peopleByUid,
}) {
  final id = event.id.trim();
  if (id.isEmpty) return null;
  return ExportEvent(
    id: id,
    title: redactSecrets(
      event.summary.trim().isEmpty ? 'Untitled Event' : event.summary.trim(),
    ),
    start: event.start.toUtc(),
    end: (event.end.isBefore(event.start) ? event.start : event.end).toUtc(),
    allDay: event.allDay,
    person: exportPersonFor(event.assignedTo, peopleByUid),
    category: exportCategoryFor(event.category),
    tentative: isTentativeStatus(event.status),
    source: exportSourceFor(event.source),
  );
}

List<ExportEvent> mapStoredEvents(
  List<StoredExportEvent> events, {
  required Map<String, ExportPerson> peopleByUid,
  required LondonWindow window,
}) {
  final mapped = <ExportEvent>[];
  for (final event in events) {
    final export = mapStoredEvent(event, peopleByUid: peopleByUid);
    if (export == null) continue;
    if (!exportEventOverlapsWindow(export, window)) continue;
    mapped.add(export);
  }
  return mapped;
}

int compareExportEvents(ExportEvent a, ExportEvent b) {
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  if (byTitle != 0) return byTitle;
  return a.id.compareTo(b.id);
}

List<ExportDaySummary> summarizeExportDays(
  List<ExportEvent> events,
  LondonWindow window,
) {
  final days = <ExportDaySummary>[];
  var date = window.start;
  while (true) {
    final onDay = events.where((event) => exportEventBelongsOnDay(event, date));
    days.add(
      ExportDaySummary(
        date: date,
        tomBusy: tomBusyForDay(events, date),
        eventCount: onDay.length,
      ),
    );
    if (date == window.end) break;
    date = date.addDays(1);
  }
  return days;
}

ScheduleSnapshot buildScheduleSnapshot({
  required DateTime generatedAt,
  required LondonWindow window,
  required List<StoredExportEvent> events,
  List<StoredBirthday> birthdays = const [],
  Map<String, String> namesByUid = const {},
  String? hubId,
}) {
  final peopleByUid = peopleByUidFromProfiles(namesByUid);
  final mapped = [
    ...mapStoredEvents(events, peopleByUid: peopleByUid, window: window),
    ...expandBirthdays(birthdays, window),
  ]..sort(compareExportEvents);
  return ScheduleSnapshot(
    generatedAt: generatedAt.toUtc(),
    windowStart: window.start,
    windowEnd: window.end,
    events: mapped,
    days: summarizeExportDays(mapped, window),
    hubId: hubId,
  );
}

String renderScheduleIcs(ScheduleSnapshot snapshot) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//LoveHub//Schedule Export//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:LoveHub',
    'X-WR-TIMEZONE:$lovehubScheduleTimezone',
    'X-WR-CALDESC:Read-only LoveHub snapshot. Check generatedAt in schedule.json.',
  ];
  final stamp = _icsUtc(snapshot.generatedAt);
  for (final event in snapshot.events) {
    lines.add('BEGIN:VEVENT');
    lines.add('UID:${_icsUid(event.id)}');
    lines.add('DTSTAMP:$stamp');
    if (event.allDay) {
      final start = londonCivilDate(event.start);
      var end = londonCivilDate(event.end);
      if (end.compareTo(start) <= 0) end = start.addDays(1);
      lines.add('DTSTART;VALUE=DATE:${_icsDate(start)}');
      lines.add('DTEND;VALUE=DATE:${_icsDate(end)}');
    } else {
      lines.add('DTSTART:${_icsUtc(event.start)}');
      lines.add('DTEND:${_icsUtc(event.end)}');
    }
    lines.add('SUMMARY:${icsEscape(event.title)}');
    lines.add('STATUS:${event.tentative ? 'TENTATIVE' : 'CONFIRMED'}');
    lines.add('CATEGORIES:${event.category.name.toUpperCase()}');
    lines.add('END:VEVENT');
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(icsFoldLine).join('\r\n')}\r\n';
}

String _icsUid(String id) {
  final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9._@-]+'), '-');
  return 'lovehub-$safe@lovehub';
}

String _icsUtc(DateTime instant) {
  final utc = instant.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}

String _icsDate(LondonDate date) {
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

String icsEscape(String raw) {
  return raw
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');
}

/// RFC 5545 line folding at 75 octets.
String icsFoldLine(String line) {
  final units = line.codeUnits;
  if (units.length <= 75) return line;
  final buffer = StringBuffer();
  var start = 0;
  var width = 75;
  while (start < units.length) {
    var end = start + width;
    if (end > units.length) end = units.length;
    if (start > 0) buffer.write('\r\n ');
    buffer.write(String.fromCharCodes(units.sublist(start, end)));
    start = end;
    width = 74;
  }
  return buffer.toString();
}

String scheduleExportReadme({
  required String outDir,
  required String commandHint,
}) {
  final maxDocs = scheduleExportMaxDocuments;
  return [
    '# LoveHub schedule export',
    '',
    'Read-only snapshot of the household calendar, refreshed once a day.',
    '',
    'These files are written atomically (temp file, then rename) into:',
    '',
    '  $outDir/schedule.json',
    '  $outDir/schedule.ics',
    '  $outDir/README.md',
    '',
    'They are a copy for other bots to read. Nothing here can write back to',
    'LoveHub. If the files look stale, check `generatedAt` in schedule.json',
    'before planning around them.',
    '',
    '## How to refresh',
    '',
    '  $commandHint',
    '',
    'Default window: today through today+56 days, Europe/London.',
    '',
    '## schedule.json',
    '',
    '- `generatedAt` - when this copy was built, as an ISO UTC timestamp.',
    '- `timezone` - always `"Europe/London"`.',
    '- `windowStart` / `windowEnd` - inclusive civil dates in that timezone.',
    '- `hubId` - the LoveHub hub this copy came from.',
    '- `events` - every event that belongs in the window, including meal-plan',
    '  dinners (`category` `"meal"`) and yearly birthday recurrences expanded',
    '  from the hub birthdays list.',
    '  - `id`, `title`',
    '  - `start`, `end` - ISO-8601 with a Europe/London offset (`+00:00` or `+01:00`)',
    '  - `allDay` - boolean',
    '  - `person` - `tom`, `maria`, or `shared`',
    '  - `category` - `work`, `personal`, `birthday`, `meal`, or `other`',
    '    (the app\'s `"general"` category is exported as `personal`)',
    '  - `tentative` - boolean (`true` only when the stored status is tentative)',
    '  - `source` - importer name such as `c2-rota`, or `manual`, or `birthday`',
    '- `days` - one row per civil date in the window, including quiet days:',
    '  - `date` - `YYYY-MM-DD`',
    '  - `tomBusy` - `none`, `daytime`, `evening`, or `all-day`',
    '  - `eventCount` - how many exported events belong on that date',
    '',
    '`tomBusy` looks only at Tom\'s work events. Overnight work that ends',
    'before 06:00 stays on the start date (the same rule as the dashboard).',
    'Daytime is 06:00-17:00; evening is 17:00-06:00 the next morning. A day',
    'with both, or an all-day work event, is `all-day`.',
    '',
    'Recurring calendar events are already stored as one document per',
    'occurrence, so this export does not expand them again. Birthdays are',
    'the only series expanded here.',
    '',
    'Events that started more than 14 days before the window are still',
    'included when they belong on a date inside it, because the exporter',
    'reads the events collection (up to $maxDocs documents) and filters',
    'locally.',
    '',
    '## schedule.ics',
    '',
    'A published, read-only iCalendar (`METHOD:PUBLISH`) of the same events.',
    'Timed dates are UTC (`Z`). All-day dates use `VALUE=DATE` with an',
    'exclusive end date. It is a snapshot, not a live subscription.',
    '',
    '## What is left out',
    '',
    'No feed tokens, passwords, email addresses, or account identifiers.',
    'Unknown assignees are exported as `shared` rather than as a uid.',
    '',
  ].join('\n');
}

// Firestore REST (read-only) helpers used by the CLI and covered by tests.

Object? firestoreRestValue(Object? value) {
  if (value is! Map) return null;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('booleanValue')) return value['booleanValue'] == true;
  if (value.containsKey('integerValue')) {
    final raw = value['integerValue'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }
  if (value.containsKey('doubleValue')) {
    final raw = value['doubleValue'];
    if (raw is num) return raw;
    return null;
  }
  if (value.containsKey('timestampValue') &&
      value['timestampValue'] is String) {
    return DateTime.parse(value['timestampValue'] as String).toUtc();
  }
  if (value.containsKey('mapValue')) {
    final map = value['mapValue'];
    if (map is Map && map['fields'] is Map) {
      return firestoreRestFields(
        Map<String, dynamic>.from(map['fields'] as Map),
      );
    }
    return <String, Object?>{};
  }
  if (value.containsKey('arrayValue')) {
    final array = value['arrayValue'];
    if (array is Map && array['values'] is List) {
      return (array['values'] as List).map(firestoreRestValue).toList();
    }
    return const [];
  }
  if (value.containsKey('nullValue')) return null;
  return null;
}

Map<String, Object?> firestoreRestFields(Map<String, dynamic> fields) {
  final out = <String, Object?>{};
  for (final entry in fields.entries) {
    out[entry.key] = firestoreRestValue(entry.value);
  }
  return out;
}

String? firestoreDocumentId(Map<String, dynamic> document) {
  final name = document['name'];
  if (name is! String || name.isEmpty) return null;
  return Uri.decodeComponent(name.split('/').last);
}

StoredExportEvent? storedEventFromRestDocument(Map<String, dynamic> document) {
  final id = firestoreDocumentId(document);
  if (id == null || id.isEmpty) return null;
  final fieldsRaw = document['fields'];
  final fields = fieldsRaw is Map
      ? firestoreRestFields(Map<String, dynamic>.from(fieldsRaw))
      : <String, Object?>{};
  final start = fields['start'];
  if (start is! DateTime) return null;
  final endRaw = fields['end'];
  final end = endRaw is DateTime ? endRaw : start;
  final summary = fields['summary'];
  final category = fields['category'];
  final assignedTo = fields['assignedTo'];
  final status = fields['status'];
  final source = fields['source'];
  return StoredExportEvent(
    id: id,
    summary: summary is String ? summary : 'Untitled Event',
    start: start,
    end: end,
    allDay: fields['allDay'] == true,
    category: category is String ? category : 'general',
    assignedTo: assignedTo is String ? assignedTo : 'shared',
    status: status is String ? status : null,
    source: source is String ? source : null,
  );
}

List<StoredExportEvent> storedEventsFromRestList(Object? decoded) {
  final events = <StoredExportEvent>[];
  for (final document in _restDocuments(decoded)) {
    final event = storedEventFromRestDocument(document);
    if (event != null) events.add(event);
  }
  return events;
}

StoredBirthday? storedBirthdayFromRestDocument(Map<String, dynamic> document) {
  final id = firestoreDocumentId(document);
  if (id == null || id.isEmpty) return null;
  final fieldsRaw = document['fields'];
  final fields = fieldsRaw is Map
      ? firestoreRestFields(Map<String, dynamic>.from(fieldsRaw))
      : <String, Object?>{};
  final name = fields['name'];
  final month = _asInt(fields['month']);
  final day = _asInt(fields['day']);
  if (name is! String || name.trim().isEmpty || month == null || day == null) {
    return null;
  }
  return StoredBirthday(
    id: id,
    name: name,
    month: month,
    day: day,
    year: _asInt(fields['year']),
  );
}

List<StoredBirthday> storedBirthdaysFromRestList(Object? decoded) {
  final birthdays = <StoredBirthday>[];
  for (final document in _restDocuments(decoded)) {
    final birthday = storedBirthdayFromRestDocument(document);
    if (birthday != null) birthdays.add(birthday);
  }
  return birthdays;
}

/// Display names from a hub document's `memberProfiles`, keyed by uid.
Map<String, String> namesByUidFromHubDocument(Map<String, dynamic> document) {
  final fieldsRaw = document['fields'];
  final fields = fieldsRaw is Map
      ? firestoreRestFields(Map<String, dynamic>.from(fieldsRaw))
      : <String, Object?>{};
  final names = <String, String>{};
  void addName(String uid, Object? raw) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return;
    if (raw is String && raw.trim().isNotEmpty) {
      names[trimmed] = raw.trim();
    }
  }

  final profiles = fields['memberProfiles'];
  if (profiles is Map) {
    for (final entry in profiles.entries) {
      final profile = entry.value;
      if (profile is Map) {
        addName(
          entry.key.toString(),
          profile['displayName'] ?? profile['name'],
        );
      }
    }
  }
  return names;
}

List<Map<String, dynamic>> _restDocuments(Object? decoded) {
  if (decoded is List) {
    return [
      for (final row in decoded)
        if (row is Map && row['document'] is Map)
          Map<String, dynamic>.from(row['document'] as Map)
        else if (row is Map && row['name'] is String)
          Map<String, dynamic>.from(row),
    ];
  }
  if (decoded is Map) {
    final documents = decoded['documents'];
    if (documents is List) {
      return [
        for (final row in documents)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
    }
  }
  return const [];
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
