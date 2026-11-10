// Europe/London civil dates.
//
// BST starts at 01:00 UTC on the last Sunday of March and ends at 01:00 UTC
// on the last Sunday of October (the rule in force since 2002). No timezone
// database is required.

class LondonDate {
  const LondonDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  String get ymd {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  LondonDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return LondonDate(shifted.year, shifted.month, shifted.day);
  }

  int compareTo(LondonDate other) => ymd.compareTo(other.ymd);

  bool operator <(LondonDate other) => compareTo(other) < 0;

  bool operator >(LondonDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is LondonDate && other.ymd == ymd;

  @override
  int get hashCode => ymd.hashCode;

  @override
  String toString() => ymd;
}

/// Inclusive civil-date window the Concorde feed is allowed to speak for.
class LondonWindow {
  const LondonWindow({required this.start, required this.end});

  final LondonDate start;
  final LondonDate end;

  bool contains(LondonDate date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;

  @override
  String toString() => '$start .. $end';
}

/// `YYYY-MM-DD` that is a real calendar day, otherwise null.
LondonDate? tryParseCivilDate(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return LondonDate(year, month, day);
}

/// Whether [instant] falls in British Summer Time.
bool londonIsBst(DateTime instant) {
  final utc = instant.toUtc();
  final start = _londonTransition(utc.year, 3);
  final end = _londonTransition(utc.year, 10);
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// Civil date of [instant] in Europe/London.
LondonDate londonCivilDate(DateTime instant) {
  final utc = instant.toUtc();
  final shifted = londonIsBst(utc) ? utc.add(const Duration(hours: 1)) : utc;
  return LondonDate(shifted.year, shifted.month, shifted.day);
}

/// Today-14 through today+90, inclusive, on the London calendar.
LondonWindow londonReconcileWindow(
  DateTime now, {
  int priorDays = 14,
  int nextDays = 90,
}) {
  final today = londonCivilDate(now);
  return LondonWindow(
    start: today.addDays(-priorDays),
    end: today.addDays(nextDays),
  );
}

DateTime _londonTransition(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0);
  final sunday = last.day - (last.weekday % 7);
  return DateTime.utc(year, month, sunday, 1);
}
