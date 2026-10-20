import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Calendar day [offset] days after [day], in local calendar terms.
///
/// `day.add(Duration(days: n))` adds 24-hour blocks, so across the October
/// clock change (a 25-hour day) it lands at 23:00 the same day and the day
/// after shows up twice. Use the calendar constructor instead.
DateTime calendarDayOffset(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

DateTime? _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

/// Makes one raw event map safe for every view, or returns null to skip it.
///
/// - no usable `start` -> skipped (logged)
/// - `end` missing or not a date -> removed (views treat it as start)
/// - `end` before `start` (seen on an all-day event saved across the DST
///   change) -> clamped to `start`, so it shows on its start day only
SafeEvent sanitizeEventMap(Map<String, dynamic> raw, {String? id}) {
  final start = _asDate(raw['start']);
  if (start == null) {
    return SafeEvent.skip('no start');
  }
  final data = Map<String, dynamic>.from(raw);
  final end = _asDate(raw['end']);
  if (raw['end'] != null && end == null) {
    data.remove('end');
  } else if (end != null && end.isBefore(start)) {
    data['end'] = raw['start'];
    return SafeEvent(data, fixed: 'end before start');
  }
  return SafeEvent(data);
}

class SafeEvent {
  const SafeEvent(this.data, {this.fixed});
  const SafeEvent.skip(String reason) : data = null, fixed = reason;
  final Map<String, dynamic>? data;
  final String? fixed;
}

/// Sanitizes a batch of event maps. One bad doc never breaks the batch:
/// anything that throws or has no start is skipped with a debug log.
final Set<String> _logged = {};

void _logOnce(String key, String message) {
  if (_logged.add(key)) debugPrint(message);
}

List<Map<String, dynamic>> sanitizeEventMaps(
  Iterable<Map<String, dynamic>> raw, {
  String Function(Map<String, dynamic>)? idOf,
}) {
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    final id = idOf?.call(e) ?? e['id']?.toString() ?? '?';
    try {
      final safe = sanitizeEventMap(e, id: id);
      if (safe.fixed != null) {
        _logOnce(
          '$id/${safe.fixed}',
          'LoveHub: event $id ${safe.data == null ? "skipped" : "fixed"}: ${safe.fixed}',
        );
      }
      if (safe.data != null) out.add(safe.data!);
    } catch (err) {
      _logOnce('$id/err', 'LoveHub: event $id skipped: $err');
    }
  }
  return out;
}

/// Runs [build]; on any error logs it and returns null, so a single broken
/// slide/card cannot stop the others from being built.
T? guardedBuild<T>(String what, T Function() build) {
  try {
    return build();
  } catch (err, st) {
    debugPrint('LoveHub: $what failed: $err\n$st');
    return null;
  }
}
