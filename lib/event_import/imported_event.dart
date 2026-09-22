import 'dart:convert';

/// Public Firebase web config already shipped in [DefaultFirebaseOptions].
///
/// The API key is a client key, not a service-account secret. Refresh tokens
/// and ID tokens still belong in the environment, never in git.
const lovehubFirebaseProjectId = 'lovehub-26107';
const lovehubFirebaseWebApiKey = 'AIzaSyCaL0oQdTrw2yk-0fAlyBgirOxwQC-G8NU';

/// Sources Roger was given. Any other non-empty string is accepted too.
const knownEventImportSources = ['c2-rota', 'seb', 'rot90s'];

class EventImportException implements Exception {
  EventImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HubMemberRef {
  const HubMemberRef({required this.uid, required this.displayName});

  final String uid;
  final String displayName;
}

class HubDirectory {
  const HubDirectory({required this.memberUids, this.displayNames = const {}});

  final List<String> memberUids;
  final Map<String, String> displayNames;

  List<HubMemberRef> get members => [
    for (final uid in memberUids)
      HubMemberRef(uid: uid, displayName: displayNames[uid] ?? ''),
  ];

  bool containsUid(String uid) => memberUids.contains(uid);
}

/// One v1 work-calendar event, already validated.
class ImportedEvent {
  const ImportedEvent({
    required this.docId,
    required this.source,
    required this.externalId,
    required this.summary,
    required this.start,
    required this.end,
    required this.allDay,
    required this.category,
    required this.assignedTo,
    this.notes,
  });

  final String docId;
  final String source;
  final String externalId;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String category;
  final String assignedTo;
  final String? notes;

  /// Firestore fields for an upsert. [gcalId] is intentionally absent so a
  /// merge does not clear Google Calendar sync on a doc that already has one.
  Map<String, Object?> toImportFields({String? ownerId}) {
    return {
      'summary': summary,
      'start': start,
      'end': end,
      'allDay': allDay,
      'category': category,
      'assignedTo': assignedTo,
      'isLovehubContext': true,
      'source': source,
      'externalId': externalId,
      'notes': notes,
      if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
    };
  }
}

/// Stable Firestore document id for `source:externalId`.
///
/// Legal ids are kept as-is (`c2-rota:2026-09-20`). `/` and control
/// characters are replaced; reserved `.` / `..` / `__*__` ids are prefixed.
String eventImportDocId(String source, String externalId) {
  final raw = '${source.trim()}:${externalId.trim()}';
  final sanitized = _sanitizeDocId(raw);
  if (!_isLegalFirestoreId(sanitized)) {
    throw EventImportException('Could not build a Firestore id from "$raw"');
  }
  return sanitized;
}

String _sanitizeDocId(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune < 32 || rune == 0x2F) {
      buffer.write('_');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  var id = buffer.toString();
  if (id == '.' || id == '..' || RegExp(r'^__.*__$').hasMatch(id)) {
    id = 'import_$id';
  }
  if (id.length > 700) id = id.substring(0, 700);
  return id;
}

bool _isLegalFirestoreId(String id) {
  if (id.isEmpty || id.length > 700) return false;
  if (id == '.' || id == '..') return false;
  if (id.contains('/')) return false;
  if (RegExp(r'^__.*__$').hasMatch(id)) return false;
  return true;
}

/// Map Roger's `tom` / `maria` tokens (or a display name) onto a hub uid.
///
/// Unknown tokens are stored as given so a later colour lookup can still
/// paint Tom blue / Maria yellow.
String resolveAssignedTo(String raw, List<HubMemberRef> members) {
  final value = raw.trim();
  if (value.isEmpty || value.toLowerCase() == 'shared') return 'shared';

  final sorted = [...members]..sort((a, b) => a.uid.compareTo(b.uid));
  for (final member in sorted) {
    if (member.uid == value) return member.uid;
  }

  final token = value.toLowerCase();
  for (final member in sorted) {
    final name = member.displayName.trim().toLowerCase();
    if (name.isEmpty) continue;
    final first = name.split(RegExp(r'\s+')).first;
    if (name == token || first == token) return member.uid;
    if ((token == 'tom' || token == 'maria') && name.contains(token)) {
      return member.uid;
    }
  }
  return value;
}

void requireHubMember({
  required String uid,
  required Iterable<String> memberUids,
}) {
  if (!memberUids.contains(uid)) {
    throw EventImportException(
      'User $uid is not a member of this hub. '
      'Import is limited to hub members.',
    );
  }
}

void validateHubId(String hubId) {
  final id = hubId.trim();
  if (id.isEmpty ||
      id.contains('/') ||
      id == '.' ||
      id == '..' ||
      id.contains('..')) {
    throw EventImportException('hubId is not a valid Firestore document id');
  }
}

/// Accepts one event, a JSON array, or `{"events":[...]}`.
List<ImportedEvent> parseEventImport(
  Object? payload, {
  List<HubMemberRef> members = const [],
}) {
  final list = _eventList(payload);
  final events = <ImportedEvent>[];
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    if (item is! Map) {
      throw EventImportException('events[$i] must be an object');
    }
    events.add(_parseOne(Map<String, dynamic>.from(item), i, members));
  }
  return events;
}

List<Object?> _eventList(Object? payload) {
  if (payload is List) return payload;
  if (payload is Map) {
    final map = Map<String, dynamic>.from(payload);
    if (map.containsKey('events')) {
      final events = map['events'];
      if (events is! List) {
        throw EventImportException('"events" must be an array');
      }
      return events;
    }
    if (map.containsKey('source') || map.containsKey('externalId')) {
      return [map];
    }
  }
  throw EventImportException(
    'Payload must be an event object, an array of events, or {"events":[...]}',
  );
}

ImportedEvent _parseOne(
  Map<String, dynamic> json,
  int index,
  List<HubMemberRef> members,
) {
  final source = _requiredString(json, 'source', index);
  final externalId = _requiredString(json, 'externalId', index);
  final summary = _requiredString(json, 'summary', index);
  final start = _requiredTime(json, 'start', index);
  final end = json.containsKey('end') && json['end'] != null
      ? _requiredTime(json, 'end', index)
      : start;
  if (end.isBefore(start)) {
    throw EventImportException('events[$index].end is before start');
  }

  final assignedRaw = _optionalString(json, 'assignedTo', index) ?? 'shared';
  return ImportedEvent(
    docId: eventImportDocId(source, externalId),
    source: source,
    externalId: externalId,
    summary: summary,
    start: start,
    end: end,
    allDay: _requiredBool(json, 'allDay', index, defaultValue: false),
    category: _optionalString(json, 'category', index) ?? 'general',
    assignedTo: resolveAssignedTo(assignedRaw, members),
    notes: _optionalString(json, 'notes', index),
  );
}

String _requiredString(Map<String, dynamic> json, String key, int index) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw EventImportException('events[$index].$key is required');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String key, int index) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! String) {
    throw EventImportException('events[$index].$key must be a string');
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _requiredBool(
  Map<String, dynamic> json,
  String key,
  int index, {
  required bool defaultValue,
}) {
  if (!json.containsKey(key) || json[key] == null) return defaultValue;
  final value = json[key];
  if (value is! bool) {
    throw EventImportException('events[$index].$key must be a boolean');
  }
  return value;
}

DateTime _requiredTime(Map<String, dynamic> json, String key, int index) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw EventImportException('events[$index].$key is required');
  }
  return parseImportTimestamp(value, label: 'events[$index].$key');
}

/// ISO-8601 with a zone offset, or a date-only all-day value.
///
/// Date-only values are stored as UTC midnight of that civil date, which
/// stays on the same calendar day in Europe/London (GMT and BST).
DateTime parseImportTimestamp(String raw, {String label = 'timestamp'}) {
  final iso = raw.trim();
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (dateOnly != null) {
    final year = int.parse(dateOnly.group(1)!);
    final month = int.parse(dateOnly.group(2)!);
    final day = int.parse(dateOnly.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw EventImportException('$label is not a valid date');
    }
    return parsed;
  }
  if (!RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(iso)) {
    throw EventImportException(
      '$label must be ISO-8601 with a timezone offset (Europe/London)',
    );
  }
  try {
    return DateTime.parse(iso).toUtc();
  } on FormatException {
    throw EventImportException('$label is not a valid ISO-8601 timestamp');
  }
}

String uidFromFirebaseIdToken(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) {
    throw EventImportException('FIREBASE_ID_TOKEN is not a JWT');
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is! Map) {
      throw EventImportException('ID token payload is not an object');
    }
    final uid = decoded['user_id'] ?? decoded['sub'];
    if (uid is! String || uid.isEmpty) {
      throw EventImportException('ID token has no uid');
    }
    return uid;
  } on EventImportException {
    rethrow;
  } catch (_) {
    throw EventImportException('Could not read uid from ID token');
  }
}

/// Reads `members` and `memberProfiles` from a Firestore REST document.
HubDirectory parseHubDirectory(Map<String, dynamic> document) {
  final fields = document['fields'];
  if (fields is! Map) {
    throw EventImportException('Hub document has no fields');
  }
  final map = Map<String, dynamic>.from(fields);
  final uids = <String>[];
  final membersField = map['members'];
  if (membersField is Map) {
    final array = membersField['arrayValue'];
    if (array is Map && array['values'] is List) {
      for (final value in array['values'] as List) {
        if (value is Map && value['stringValue'] is String) {
          final uid = (value['stringValue'] as String).trim();
          if (uid.isNotEmpty) uids.add(uid);
        }
      }
    }
  }

  final names = <String, String>{};
  final profiles = map['memberProfiles'];
  if (profiles is Map && profiles['mapValue'] is Map) {
    final profileFields = (profiles['mapValue'] as Map)['fields'];
    if (profileFields is Map) {
      profileFields.forEach((uid, raw) {
        if (uid is! String || raw is! Map) return;
        final inner = raw['mapValue'];
        if (inner is! Map) return;
        final innerFields = inner['fields'];
        if (innerFields is! Map) return;
        final display = innerFields['displayName'];
        if (display is Map && display['stringValue'] is String) {
          names[uid] = display['stringValue'] as String;
        }
      });
    }
  }
  return HubDirectory(memberUids: uids, displayNames: names);
}

String? parseUserDisplayName(Map<String, dynamic> document) {
  final fields = document['fields'];
  if (fields is! Map) return null;
  final display = fields['displayName'];
  if (display is Map && display['stringValue'] is String) {
    final name = (display['stringValue'] as String).trim();
    return name.isEmpty ? null : name;
  }
  return null;
}

Map<String, dynamic> firestoreRestValue(Object? value) {
  if (value == null) return {'nullValue': null};
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': '$value'};
  if (value is DateTime) {
    return {'timestampValue': value.toUtc().toIso8601String()};
  }
  throw ArgumentError('Unsupported Firestore value: $value');
}

/// One Firestore `commit` write. Update mask omits `gcalId`.
Map<String, dynamic> firestoreRestWrite({
  required String projectId,
  required String hubId,
  required ImportedEvent event,
  String? ownerId,
}) {
  validateHubId(hubId);
  final fields = event.toImportFields(ownerId: ownerId);
  return {
    'update': {
      'name':
          'projects/$projectId/databases/(default)/documents/hubs/$hubId/events/${event.docId}',
      'fields': {
        for (final entry in fields.entries)
          entry.key: firestoreRestValue(entry.value),
      },
    },
    'updateMask': {'fieldPaths': fields.keys.toList()},
  };
}
