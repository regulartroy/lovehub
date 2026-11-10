import 'dart:convert';

import 'imported_event.dart';
import 'london_date.dart';

/// Live Concorde rota feed. GET with `Authorization: Bearer`.
const c2RotaFeedUrl =
    'https://us-central1-concorde2-e8b96.cloudfunctions.net/tomRotaFeed';

/// Production token file on the shared computer. Override the path with
/// `--token-file` or `TOM_ROTA_FEED_TOKEN_FILE`. Never commit the contents.
const defaultTomRotaTokenFile = '/home/box/secrets/tom_rota_feed_token';

const c2RotaSource = 'c2-rota';
const c2RotaAuditCollection = 'c2RotaSyncAudit';

const c2RotaPriorDays = 14;
const c2RotaNextDays = 90;
const c2RotaDefaultMaxConfirms = 12;
const c2RotaDefaultMaxDeletes = 8;
const c2RotaAbsoluteMaxConfirms = 40;
const c2RotaAbsoluteMaxDeletes = 40;
const c2RotaMaxFeedDays = 500;
const c2RotaMaxScopedEvents = 500;
const c2RotaMaxFeedAge = Duration(hours: 6);
const c2RotaMaxFutureSkew = Duration(minutes: 5);
const c2CommitMaxAttempts = 3;

/// Scope that `gcloud auth application-default login` grants and that the
/// Cloud Firestore REST API accepts. The sync tool asks the official ADC
/// client library for this scope and does not mint a token itself.
const c2RotaFirestoreScope = 'https://www.googleapis.com/auth/cloud-platform';

/// Printed when Application Default Credentials are missing or refused.
/// Names the one-time setup. Does not include a token.
const c2RotaAdcSetup = '''
Firestore for this job uses Application Default Credentials from the Google client library.
This process does not read the Firebase CLI login cache, does not exchange a stored refresh token, and does not ask gcloud to print a token.

One-time setup, as the Google account that can read and write Cloud Firestore on lovehub-26107. Do not create a service-account key:
  gcloud auth application-default login
  gcloud auth application-default set-quota-project lovehub-26107

A firebase login by itself is not used.''';

const _auditIdPattern = r'^c2sync-\d{8}T\d{9}Z-[0-9a-f]{8}$';

class C2RotaFeedException implements Exception {
  C2RotaFeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class C2RotaArgsException implements Exception {
  C2RotaArgsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class C2RotaWriteException implements Exception {
  C2RotaWriteException(this.message, {required this.exitCode});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

class C2RotaAuthException implements Exception {
  C2RotaAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Setup text plus a short library detail. Drops the detail when it could
/// carry a token or a private key.
String c2RotaAdcUnavailableMessage(Object? detail) {
  final extra = _safeAuthDetail(detail);
  if (extra == null) return c2RotaAdcSetup.trim();
  return '${c2RotaAdcSetup.trim()}\n$extra';
}

String? _safeAuthDetail(Object? detail) {
  if (detail == null) return null;
  final text = detail.toString().trim();
  if (text.isEmpty || text.length > 300) return null;
  final lower = text.toLowerCase();
  const withheld = [
    'ya29',
    'refresh_token',
    'access_token',
    'private_key',
    'client_secret',
    'bearer ',
  ];
  for (final marker in withheld) {
    if (lower.contains(marker)) return null;
  }
  return text;
}

enum C2TomState { working, notWorking, undecided }

enum C2ShowStatus { on, cancelled }

enum C2RotaActionKind {
  confirm,
  delete,
  keepTentative,
  keepConfirmed,
  skip,
  unmatchedFeed,
}

class C2FeedDay {
  const C2FeedDay({
    required this.date,
    required this.show,
    required this.showStatus,
    required this.tom,
    this.role,
    this.loadIn,
    this.finish,
  });

  final LondonDate date;
  final String show;
  final C2ShowStatus showStatus;
  final C2TomState tom;
  final String? role;
  final String? loadIn;
  final String? finish;

  String get tomWire => switch (tom) {
    C2TomState.working => 'working',
    C2TomState.notWorking => 'not_working',
    C2TomState.undecided => 'undecided',
  };

  String get statusWire => switch (showStatus) {
    C2ShowStatus.on => 'on',
    C2ShowStatus.cancelled => 'cancelled',
  };
}

class C2RotaFeed {
  const C2RotaFeed({
    required this.generatedAt,
    required this.days,
    this.warnings = const [],
  });

  final DateTime generatedAt;
  final List<C2FeedDay> days;

  /// Rows skipped while parsing (empty off-days, unknown status). Not fatal.
  final List<String> warnings;
}

/// One hub event as read for reconciliation. Personal events are included
/// so the planner can count them as out of scope and prove it left them alone.
class C2StoredEvent {
  const C2StoredEvent({
    required this.docId,
    this.source,
    this.externalId,
    this.summary,
    this.startUtc,
    this.status,
    this.updateTime,
    this.restFields,
  });

  final String docId;
  final String? source;
  final String? externalId;
  final String? summary;
  final DateTime? startUtc;
  final String? status;
  final String? updateTime;

  /// Firestore REST `fields` map, kept so a delete can be recreated.
  final Map<String, dynamic>? restFields;

  C2StoredEvent withStatus(String? status) {
    return C2StoredEvent(
      docId: docId,
      source: source,
      externalId: externalId,
      summary: summary,
      startUtc: startUtc,
      status: status,
      updateTime: updateTime,
      restFields: restFields,
    );
  }
}

class C2RotaAction {
  const C2RotaAction({
    required this.kind,
    required this.reason,
    this.docId,
    this.summary,
    this.date,
    this.show,
    this.tom,
    this.feedStatus,
    this.event,
    this.day,
  });

  final C2RotaActionKind kind;
  final String reason;
  final String? docId;
  final String? summary;
  final String? date;
  final String? show;
  final String? tom;
  final String? feedStatus;
  final C2StoredEvent? event;
  final C2FeedDay? day;
}

class C2RotaPlan {
  const C2RotaPlan({
    required this.generatedAt,
    required this.window,
    required this.actions,
    required this.outOfScope,
    required this.importedCount,
    required this.maxConfirms,
    required this.maxDeletes,
    required this.staleReason,
    required this.blockReason,
  });

  final DateTime generatedAt;
  final LondonWindow window;
  final List<C2RotaAction> actions;
  final int outOfScope;
  final int importedCount;
  final int maxConfirms;
  final int maxDeletes;
  final String? staleReason;
  final String? blockReason;

  List<C2RotaAction> get confirms =>
      actions.where((a) => a.kind == C2RotaActionKind.confirm).toList();

  List<C2RotaAction> get deletes =>
      actions.where((a) => a.kind == C2RotaActionKind.delete).toList();

  bool get hasMutations => confirms.isNotEmpty || deletes.isNotEmpty;

  bool get preconditionsReady =>
      confirms.every(_ready) && deletes.every(_ready);

  /// True when an apply may build a commit. A no-op plan is ready.
  bool get canCommit =>
      blockReason == null && (!hasMutations || preconditionsReady);

  String get planKey {
    final lines = <String>[
      for (final action in [...confirms, ...deletes])
        '${action.kind.name}:${action.docId}',
    ]..sort();
    return lines.join('|');
  }
}

bool _ready(C2RotaAction action) {
  final event = action.event;
  if (event == null) return false;
  final updateTime = event.updateTime?.trim() ?? '';
  if (updateTime.isEmpty || event.restFields == null) return false;
  return true;
}

class C2ReconcileCommand {
  const C2ReconcileCommand({
    required this.help,
    required this.apply,
    required this.hubId,
    required this.feedFile,
    required this.eventsFile,
    required this.tokenFile,
    required this.rollbackId,
    required this.auditDir,
    required this.jsonOut,
    required this.maxConfirms,
    required this.maxDeletes,
    required this.now,
  });

  final bool help;
  final bool apply;
  final String? hubId;
  final String? feedFile;
  final String? eventsFile;
  final String tokenFile;
  final String? rollbackId;
  final String? auditDir;
  final String? jsonOut;
  final int maxConfirms;
  final int maxDeletes;
  final DateTime? now;

  bool get offlineFixture =>
      !apply && rollbackId == null && feedFile != null && eventsFile != null;
}

/// `true` only for an explicit stored tentative status. Missing, confirmed,
/// and unknown values display as confirmed in the app and must not be
/// changed by this job.
bool c2IsTentativeStatus(Object? raw) {
  if (raw is! String) return false;
  return raw.trim().toLowerCase() == eventStatusTentative;
}

bool c2IsConfirmedStatus(Object? raw) {
  if (raw is! String) return false;
  return raw.trim().toLowerCase() == eventStatusConfirmed;
}

/// Show slug used to pair a feed row with an existing id suffix or title.
///
/// `Junebabies (Bar)` becomes `junebabies-bar`. A leading `the-` is removed
/// by [c2CanonicalShowSlug] so `The Allergies` and `Allergies` agree.
String c2ShowSlug(String raw) {
  var slug = raw.trim().toLowerCase();
  if (slug.isEmpty) return '';
  slug = slug.replaceAll('&', ' and ');
  slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  slug = slug.replaceAll(RegExp(r'-{2,}'), '-');
  if (slug.startsWith('-')) slug = slug.substring(1);
  if (slug.endsWith('-')) slug = slug.substring(0, slug.length - 1);
  return slug;
}

String c2CanonicalShowSlug(String slug) {
  if (slug.startsWith('the-') && slug.length > 4) return slug.substring(4);
  return slug;
}

/// Title after a leading `C2 —` / `C2 -` / `C2:`, then the canonical slug.
String? c2SummaryShowSlug(String? summary) {
  if (summary == null) return null;
  var text = summary.trim();
  if (text.isEmpty) return null;
  final prefixed = RegExp(
    r'^c2\s*[-—–:]\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (prefixed != null) text = prefixed.group(1)!.trim();
  final slug = c2CanonicalShowSlug(c2ShowSlug(text));
  return slug.isEmpty ? null : slug;
}

/// Raw bearer token from a secret file. The message never echoes [raw].
String parseFeedToken(String raw) {
  var token = raw.trim();
  final bearer = RegExp(r'^bearer\s+', caseSensitive: false);
  if (bearer.hasMatch(token)) {
    token = token.replaceFirst(bearer, '').trim();
  }
  const unusable =
      'Feed token file is unusable. Expected one raw bearer token.';
  if (token.isEmpty || token.length < 16 || token.length > 4096) {
    throw C2RotaFeedException(unusable);
  }
  if (RegExp(r'\s').hasMatch(token)) throw C2RotaFeedException(unusable);
  final upper = token.toUpperCase();
  if (upper.contains('PRIVATE KEY') || upper.contains('BEGIN ')) {
    throw C2RotaFeedException(
      'Feed token file looks like a private key. Refusing it.',
    );
  }
  if (token.startsWith('{') || token.startsWith('[')) {
    throw C2RotaFeedException(
      'Feed token file looks like JSON. Expected a raw bearer token.',
    );
  }
  return token;
}

String redactSecret(String text, String secret) {
  final trimmed = secret.trim();
  if (trimmed.length < 4) return text;
  return text.replaceAll(trimmed, '[redacted]');
}

/// Feed URL the job is allowed to call. Query strings and other hosts are refused
/// so a bearer token cannot be sent anywhere else.
Uri requireC2RotaFeedUri(String raw) {
  final uri = Uri.parse(raw);
  final allowed =
      uri.scheme == 'https' &&
      uri.host == 'us-central1-concorde2-e8b96.cloudfunctions.net' &&
      uri.path == '/tomRotaFeed' &&
      !uri.hasQuery &&
      !uri.hasFragment;
  if (!allowed) {
    throw C2RotaFeedException(
      'Refusing feed URL that is not the Concorde tomRotaFeed endpoint.',
    );
  }
  return uri;
}

Object decodeC2FeedHttpBody({required int statusCode, required String body}) {
  if (statusCode >= 300 && statusCode < 400) {
    throw C2RotaFeedException(
      'Feed endpoint redirected ($statusCode); refusing to follow.',
    );
  }
  if (statusCode != 200) {
    throw C2RotaFeedException('Feed request failed ($statusCode).');
  }
  try {
    final decoded = jsonDecode(body);
    if (decoded == null) {
      throw C2RotaFeedException('Feed response was not a JSON object.');
    }
    return decoded;
  } on C2RotaFeedException {
    rethrow;
  } on FormatException {
    throw C2RotaFeedException('Feed response was not JSON.');
  }
}

bool c2CommitShouldRetry(int statusCode, int attemptIndex) {
  if (attemptIndex >= c2CommitMaxAttempts - 1) return false;
  return statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503;
}

bool c2CommitConflict(int statusCode, String body) {
  if (statusCode == 409) return true;
  final failed =
      body.contains('FAILED_PRECONDITION') || body.contains('NOT_FOUND');
  if (statusCode == 400 || statusCode == 412) return failed;
  return failed && statusCode >= 400;
}

/// Parses the live feed. Structural problems throw and must abort the run
/// before any event is matched. An empty day list is unusable: absence of
/// shows is not treated as a cancellation.
///
/// Empty `show` rows (off-days) and unknown `status` values are skipped with
/// a warning. `postponed` is treated like `cancelled`.
C2RotaFeed parseC2RotaFeed(Object? payload) {
  if (payload is! Map) {
    throw C2RotaFeedException(
      'Feed must be a JSON object with generatedAt and days.',
    );
  }
  final map = Map<String, dynamic>.from(payload);
  final generatedRaw = map['generatedAt'];
  if (generatedRaw is! String || generatedRaw.trim().isEmpty) {
    throw C2RotaFeedException(
      'Feed generatedAt must be an ISO-8601 timestamp.',
    );
  }
  late final DateTime generatedAt;
  try {
    generatedAt = DateTime.parse(generatedRaw.trim()).toUtc();
  } on FormatException {
    throw C2RotaFeedException('Feed generatedAt is not a valid timestamp.');
  }
  final daysRaw = map['days'];
  if (daysRaw is! List) {
    throw C2RotaFeedException('Feed days must be an array.');
  }
  if (daysRaw.isEmpty) {
    throw C2RotaFeedException(
      'Feed days is empty. Refusing to treat that as cancellations.',
    );
  }
  if (daysRaw.length > c2RotaMaxFeedDays) {
    throw C2RotaFeedException(
      'Feed has ${daysRaw.length} days, above the $c2RotaMaxFeedDays bound.',
    );
  }

  final days = <C2FeedDay>[];
  final warnings = <String>[];
  final seen = <String>{};
  for (var i = 0; i < daysRaw.length; i++) {
    final parsed = _parseFeedDay(daysRaw[i], i);
    if (parsed.warning != null) {
      warnings.add(parsed.warning!);
    }
    final day = parsed.day;
    if (day == null) continue;
    final key = '${day.date.ymd}|${c2CanonicalShowSlug(c2ShowSlug(day.show))}';
    if (!seen.add(key)) {
      throw C2RotaFeedException(
        'Feed lists "${day.show}" more than once on ${day.date.ymd}.',
      );
    }
    days.add(day);
  }
  if (days.isEmpty) {
    throw C2RotaFeedException(
      'Feed days is empty after skipping off-days and unknown statuses. '
      'Refusing to treat that as cancellations.',
    );
  }
  return C2RotaFeed(
    generatedAt: generatedAt,
    days: days,
    warnings: List.unmodifiable(warnings),
  );
}

class _ParsedFeedDay {
  const _ParsedFeedDay({this.day, this.warning});

  final C2FeedDay? day;
  final String? warning;
}

_ParsedFeedDay _parseFeedDay(Object? raw, int index) {
  if (raw is! Map) {
    throw C2RotaFeedException('days[$index] must be an object.');
  }
  final map = Map<String, dynamic>.from(raw);
  final dateRaw = map['date'];
  if (dateRaw is! String) {
    throw C2RotaFeedException('days[$index].date must be YYYY-MM-DD.');
  }
  final date = tryParseCivilDate(dateRaw);
  if (date == null) {
    throw C2RotaFeedException('days[$index].date must be YYYY-MM-DD.');
  }
  final showRaw = map['show'];
  if (showRaw is! String) {
    throw C2RotaFeedException('days[$index].show must be a string.');
  }
  if (showRaw.trim().isEmpty) {
    return _ParsedFeedDay(
      warning: 'days[$index] ${date.ymd}: empty show skipped (off-day)',
    );
  }
  if (showRaw.trim().length > 200) {
    throw C2RotaFeedException('days[$index].show must be a non-empty name.');
  }
  final show = showRaw.trim();
  if (c2ShowSlug(show).isEmpty) {
    throw C2RotaFeedException('days[$index].show has no matchable name.');
  }
  final status = _parseShowStatus(map['status'], index);
  if (status == null) {
    final rawStatus = map['status'];
    final label = rawStatus is String ? rawStatus.trim() : '$rawStatus';
    return _ParsedFeedDay(
      warning:
          'days[$index] ${date.ymd} "$show": unknown status "$label"; skipped',
    );
  }
  return _ParsedFeedDay(
    day: C2FeedDay(
      date: date,
      show: show,
      showStatus: status,
      tom: _parseTom(map['tom'], index),
      role: _optionalText(map['role'], 'days[$index].role'),
      loadIn: _optionalText(map['loadIn'], 'days[$index].loadIn'),
      finish: _optionalText(map['finish'], 'days[$index].finish'),
    ),
  );
}

/// `on`, `cancelled`, and `postponed` (treated as cancelled). Unknown strings
/// return null so the row can be skipped with a warning.
C2ShowStatus? _parseShowStatus(Object? raw, int index) {
  if (raw is! String) {
    throw C2RotaFeedException(
      'days[$index].status must be a string.',
    );
  }
  switch (raw.trim().toLowerCase()) {
    case 'on':
      return C2ShowStatus.on;
    case 'cancelled':
    case 'postponed':
      return C2ShowStatus.cancelled;
    default:
      return null;
  }
}

C2TomState _parseTom(Object? raw, int index) {
  if (raw is! String) {
    throw C2RotaFeedException(
      'days[$index].tom must be "working", "not_working", or "undecided".',
    );
  }
  switch (raw.trim().toLowerCase()) {
    case 'working':
      return C2TomState.working;
    case 'not_working':
      return C2TomState.notWorking;
    case 'undecided':
      return C2TomState.undecided;
    default:
      throw C2RotaFeedException(
        'days[$index].tom must be "working", "not_working", or "undecided".',
      );
  }
}

String? _optionalText(Object? raw, String label) {
  if (raw == null) return null;
  if (raw is! String) {
    throw C2RotaFeedException('$label must be a string or null.');
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Imported C2 document: `source == c2-rota` and the Firestore id is the
/// stable `c2-rota:{externalId}` id. Anything else is out of scope.
bool isImportedC2RotaDoc(C2StoredEvent event) {
  final source = event.source?.trim();
  final externalId = event.externalId?.trim();
  if (source != c2RotaSource || externalId == null || externalId.isEmpty) {
    return false;
  }
  try {
    return event.docId == eventImportDocId(c2RotaSource, externalId);
  } on EventImportException {
    return false;
  }
}

class _Identity {
  const _Identity({
    required this.date,
    required this.suffixSlug,
    required this.summarySlug,
  });

  final LondonDate date;
  final String? suffixSlug;
  final String? summarySlug;
}

class _Scoped {
  const _Scoped.ready(this.event, this.identity) : skipReason = null;
  const _Scoped.skip(this.event, this.skipReason) : identity = null;

  final C2StoredEvent event;
  final _Identity? identity;
  final String? skipReason;
}

_Scoped _scope(C2StoredEvent event) {
  final externalId = event.externalId!.trim();
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})(?:$|-(.+))$',
  ).firstMatch(externalId);
  if (match == null) {
    return _Scoped.skip(event, 'id has no Europe/London show date');
  }
  final date = tryParseCivilDate(match.group(1)!);
  if (date == null) {
    return _Scoped.skip(event, 'id date is not a calendar date');
  }
  String? suffixSlug;
  final suffix = match.group(2);
  if (suffix != null) {
    suffixSlug = c2CanonicalShowSlug(c2ShowSlug(suffix));
    if (suffixSlug.isEmpty) {
      return _Scoped.skip(event, 'id show suffix is empty');
    }
  }
  if (event.startUtc == null) {
    return _Scoped.skip(event, 'missing start; left untouched');
  }
  final startDate = londonCivilDate(event.startUtc!);
  if (startDate != date) {
    return _Scoped.skip(
      event,
      'Europe/London start ${startDate.ymd} does not match id date ${date.ymd}',
    );
  }
  return _Scoped.ready(
    event,
    _Identity(
      date: date,
      suffixSlug: suffixSlug,
      summarySlug: c2SummaryShowSlug(event.summary),
    ),
  );
}

bool _rowMatches(_Identity identity, C2FeedDay day) {
  if (identity.date != day.date) return false;
  final show = c2CanonicalShowSlug(c2ShowSlug(day.show));
  if (show.isEmpty) return false;
  if (identity.suffixSlug != null) {
    if (identity.suffixSlug != show) return false;
    final summary = identity.summarySlug;
    if (summary != null && summary != show) return false;
    return true;
  }
  final summary = identity.summarySlug;
  if (summary == null) return false;
  return summary == show;
}

C2RotaPlan planC2RotaReconcile({
  required C2RotaFeed feed,
  required List<C2StoredEvent> events,
  required DateTime now,
  int maxConfirms = c2RotaDefaultMaxConfirms,
  int maxDeletes = c2RotaDefaultMaxDeletes,
}) {
  final window = londonReconcileWindow(
    now,
    priorDays: c2RotaPriorDays,
    nextDays: c2RotaNextDays,
  );
  final staleReason = _staleReason(feed.generatedAt, now);

  final imported = <C2StoredEvent>[];
  var outOfScope = 0;
  for (final event in events) {
    if (isImportedC2RotaDoc(event)) {
      imported.add(event);
    } else {
      outOfScope++;
    }
  }

  final today = londonCivilDate(now);
  final actions = <C2RotaAction>[
    for (final warning in feed.warnings)
      C2RotaAction(kind: C2RotaActionKind.skip, reason: warning),
  ];

  if (imported.length > c2RotaMaxScopedEvents) {
    return C2RotaPlan(
      generatedAt: feed.generatedAt,
      window: window,
      actions: const [],
      outOfScope: outOfScope,
      importedCount: imported.length,
      maxConfirms: maxConfirms,
      maxDeletes: maxDeletes,
      staleReason: staleReason,
      blockReason:
          'imported c2-rota events (${imported.length}) exceed '
          '$c2RotaMaxScopedEvents; nothing written',
    );
  }

  final ready = <_Scoped>[];
  for (final event in imported) {
    final scoped = _scope(event);
    if (scoped.identity == null) {
      actions.add(
        C2RotaAction(
          kind: C2RotaActionKind.skip,
          reason: scoped.skipReason ?? 'left untouched',
          docId: event.docId,
          summary: event.summary,
          event: event,
        ),
      );
      continue;
    }
    if (!window.contains(scoped.identity!.date)) {
      actions.add(
        C2RotaAction(
          kind: C2RotaActionKind.skip,
          reason:
              'outside the prior-$c2RotaPriorDays/next-$c2RotaNextDays window',
          docId: event.docId,
          summary: event.summary,
          date: scoped.identity!.date.ymd,
          event: event,
        ),
      );
      continue;
    }
    ready.add(scoped);
  }

  final inWindowDays = <C2FeedDay>[];
  var ignoredFeedRows = 0;
  for (final day in feed.days) {
    if (!window.contains(day.date)) {
      ignoredFeedRows++;
      continue;
    }
    inWindowDays.add(day);
  }

  if (inWindowDays.isEmpty) {
    return _finish(
      feed: feed,
      window: window,
      actions: actions,
      outOfScope: outOfScope,
      importedCount: imported.length,
      maxConfirms: maxConfirms,
      maxDeletes: maxDeletes,
      staleReason: staleReason,
      extraBlock:
          'feed has no shows inside $window (Europe/London); nothing written',
    );
  }

  final hits = <int, List<_Scoped>>{};
  for (var i = 0; i < inWindowDays.length; i++) {
    hits[i] = [
      for (final scoped in ready)
        if (_rowMatches(scoped.identity!, inWindowDays[i])) scoped,
    ];
  }
  final rowsByEvent = <String, Set<int>>{};
  for (final entry in hits.entries) {
    for (final scoped in entry.value) {
      rowsByEvent.putIfAbsent(scoped.event.docId, () => {}).add(entry.key);
    }
  }

  final matchedIds = <String>{};
  for (var i = 0; i < inWindowDays.length; i++) {
    final day = inWindowDays[i];
    final rowHits = hits[i]!;
    if (rowHits.isEmpty) {
      actions.add(
        C2RotaAction(
          kind: C2RotaActionKind.unmatchedFeed,
          reason: 'no imported c2-rota event for this show; not created',
          date: day.date.ymd,
          show: day.show,
          tom: day.tomWire,
          feedStatus: day.statusWire,
          day: day,
        ),
      );
      continue;
    }
    final ambiguous =
        rowHits.length != 1 ||
        rowHits.any((scoped) => rowsByEvent[scoped.event.docId]!.length != 1);
    if (ambiguous) {
      for (final scoped in rowHits) {
        if (!matchedIds.add('ambiguous:${scoped.event.docId}')) continue;
        actions.add(
          C2RotaAction(
            kind: C2RotaActionKind.skip,
            reason:
                'ambiguous match for ${day.show} on ${day.date.ymd}; left untouched',
            docId: scoped.event.docId,
            summary: scoped.event.summary,
            date: day.date.ymd,
            show: day.show,
            event: scoped.event,
            day: day,
          ),
        );
      }
      continue;
    }
    final scoped = rowHits.single;
    matchedIds.add(scoped.event.docId);
    actions.add(_decision(day, scoped.event, today: today));
  }

  for (final scoped in ready) {
    if (matchedIds.contains(scoped.event.docId)) continue;
    if (matchedIds.contains('ambiguous:${scoped.event.docId}')) continue;
    actions.add(
      C2RotaAction(
        kind: C2RotaActionKind.skip,
        reason: 'no feed row matched this show; left untouched',
        docId: scoped.event.docId,
        summary: scoped.event.summary,
        date: scoped.identity!.date.ymd,
        event: scoped.event,
      ),
    );
  }

  if (ignoredFeedRows > 0) {
    actions.add(
      C2RotaAction(
        kind: C2RotaActionKind.skip,
        reason: '$ignoredFeedRows feed row(s) outside $window ignored',
      ),
    );
  }

  return _finish(
    feed: feed,
    window: window,
    actions: actions,
    outOfScope: outOfScope,
    importedCount: imported.length,
    maxConfirms: maxConfirms,
    maxDeletes: maxDeletes,
    staleReason: staleReason,
  );
}

C2RotaAction _decision(
  C2FeedDay day,
  C2StoredEvent event, {
  required LondonDate today,
}) {
  final tentative = c2IsTentativeStatus(event.status);
  final remove =
      day.showStatus == C2ShowStatus.cancelled ||
      day.tom == C2TomState.notWorking;
  final base = C2RotaAction(
    kind: C2RotaActionKind.skip,
    reason: '',
    docId: event.docId,
    summary: event.summary,
    date: day.date.ymd,
    show: day.show,
    tom: day.tomWire,
    feedStatus: day.statusWire,
    event: event,
    day: day,
  );
  if (remove) {
    if (tentative) {
      // Past history stays as stored. Deletes apply only to today and future
      // Europe/London dates. Confirming a past worked show is still allowed.
      if (day.date < today) {
        return C2RotaAction(
          kind: C2RotaActionKind.keepTentative,
          reason: 'before today; not deleted',
          docId: base.docId,
          summary: base.summary,
          date: base.date,
          show: base.show,
          tom: base.tom,
          feedStatus: base.feedStatus,
          event: event,
          day: day,
        );
      }
      final why = day.showStatus == C2ShowStatus.cancelled
          ? 'show cancelled'
          : 'tom=not_working';
      return C2RotaAction(
        kind: C2RotaActionKind.delete,
        reason: why,
        docId: base.docId,
        summary: base.summary,
        date: base.date,
        show: base.show,
        tom: base.tom,
        feedStatus: base.feedStatus,
        event: event,
        day: day,
      );
    }
    final why = day.showStatus == C2ShowStatus.cancelled
        ? 'left confirmed; show cancelled'
        : 'left confirmed; tom=not_working';
    return C2RotaAction(
      kind: C2RotaActionKind.keepConfirmed,
      reason: why,
      docId: base.docId,
      summary: base.summary,
      date: base.date,
      show: base.show,
      tom: base.tom,
      feedStatus: base.feedStatus,
      event: event,
      day: day,
    );
  }
  if (day.tom == C2TomState.working && day.showStatus == C2ShowStatus.on) {
    if (tentative) {
      return C2RotaAction(
        kind: C2RotaActionKind.confirm,
        reason: 'tom=working status=on',
        docId: base.docId,
        summary: base.summary,
        date: base.date,
        show: base.show,
        tom: base.tom,
        feedStatus: base.feedStatus,
        event: event,
        day: day,
      );
    }
    return C2RotaAction(
      kind: C2RotaActionKind.keepConfirmed,
      reason: 'already confirmed',
      docId: base.docId,
      summary: base.summary,
      date: base.date,
      show: base.show,
      tom: base.tom,
      feedStatus: base.feedStatus,
      event: event,
      day: day,
    );
  }
  if (tentative) {
    return C2RotaAction(
      kind: C2RotaActionKind.keepTentative,
      reason: 'tom=undecided',
      docId: base.docId,
      summary: base.summary,
      date: base.date,
      show: base.show,
      tom: base.tom,
      feedStatus: base.feedStatus,
      event: event,
      day: day,
    );
  }
  return C2RotaAction(
    kind: C2RotaActionKind.keepConfirmed,
    reason: 'left confirmed; tom=undecided',
    docId: base.docId,
    summary: base.summary,
    date: base.date,
    show: base.show,
    tom: base.tom,
    feedStatus: base.feedStatus,
    event: event,
    day: day,
  );
}

String? _staleReason(DateTime generatedAt, DateTime now) {
  final generated = generatedAt.toUtc();
  final clock = now.toUtc();
  if (generated.isAfter(clock.add(c2RotaMaxFutureSkew))) {
    return 'generatedAt is more than ${c2RotaMaxFutureSkew.inMinutes} minutes '
        'ahead of this clock';
  }
  if (clock.difference(generated) > c2RotaMaxFeedAge) {
    return 'generatedAt is older than ${c2RotaMaxFeedAge.inHours} hours';
  }
  return null;
}

C2RotaPlan _finish({
  required C2RotaFeed feed,
  required LondonWindow window,
  required List<C2RotaAction> actions,
  required int outOfScope,
  required int importedCount,
  required int maxConfirms,
  required int maxDeletes,
  required String? staleReason,
  String? extraBlock,
}) {
  final sorted = [...actions]..sort(_compareActions);
  final confirms = sorted
      .where((a) => a.kind == C2RotaActionKind.confirm)
      .length;
  final deletes = sorted.where((a) => a.kind == C2RotaActionKind.delete).length;
  final blocks = <String>[
    if (extraBlock != null) extraBlock,
    if (staleReason != null) 'feed is stale ($staleReason)',
    if (confirms > maxConfirms || deletes > maxDeletes)
      'batch would confirm $confirms and delete $deletes, '
          'above the cap of $maxConfirms confirms / $maxDeletes deletes; '
          'nothing written',
  ];
  return C2RotaPlan(
    generatedAt: feed.generatedAt,
    window: window,
    actions: sorted,
    outOfScope: outOfScope,
    importedCount: importedCount,
    maxConfirms: maxConfirms,
    maxDeletes: maxDeletes,
    staleReason: staleReason,
    blockReason: blocks.isEmpty ? null : blocks.join('; '),
  );
}

int _compareActions(C2RotaAction a, C2RotaAction b) {
  final byDate = (a.date ?? '9999').compareTo(b.date ?? '9999');
  if (byDate != 0) return byDate;
  final byId = (a.docId ?? '').compareTo(b.docId ?? '');
  if (byId != 0) return byId;
  return a.kind.index.compareTo(b.kind.index);
}

String renderC2RotaPlan(
  C2RotaPlan plan, {
  required String hubId,
  required bool applying,
}) {
  final buffer = StringBuffer()
    ..writeln(
      applying ? 'C2 rota reconcile: apply' : 'C2 rota reconcile: dry-run',
    )
    ..writeln('hub: $hubId')
    ..writeln('feed generatedAt: ${plan.generatedAt.toUtc().toIso8601String()}')
    ..writeln('window: ${plan.window} (Europe/London)')
    ..writeln('imported c2-rota events: ${plan.importedCount}')
    ..writeln('other events ignored: ${plan.outOfScope}');
  if (plan.staleReason != null) {
    buffer.writeln('STALE: ${plan.staleReason}');
  }
  buffer.writeln();
  for (final action in plan.actions) {
    buffer.writeln(_renderAction(action));
  }
  buffer
    ..writeln()
    ..writeln(
      'writes: ${plan.confirms.length} confirm, ${plan.deletes.length} delete '
      '(caps ${plan.maxConfirms} confirm / ${plan.maxDeletes} delete)',
    );
  if (plan.blockReason != null) {
    buffer.writeln('apply refused: ${plan.blockReason}');
  } else if (!applying) {
    buffer.writeln('nothing written');
    if (plan.hasMutations && !plan.preconditionsReady) {
      buffer.writeln(
        'these events have no Firestore updateTime; a live dry-run reads it '
        'before --apply',
      );
    }
  } else if (!plan.hasMutations) {
    buffer.writeln('no changes');
  }
  return buffer.toString();
}

String _renderAction(C2RotaAction action) {
  final label = switch (action.kind) {
    C2RotaActionKind.confirm => 'CONFIRM',
    C2RotaActionKind.delete => 'DELETE',
    C2RotaActionKind.keepTentative => 'KEEP',
    C2RotaActionKind.keepConfirmed => 'KEEP',
    C2RotaActionKind.skip => 'SKIP',
    C2RotaActionKind.unmatchedFeed => 'NOEVENT',
  };
  final id = action.docId ?? action.date ?? '-';
  final title = action.summary ?? action.show ?? '';
  final detail = switch (action.kind) {
    C2RotaActionKind.confirm => 'tentative -> confirmed',
    C2RotaActionKind.keepTentative => 'left tentative (${action.reason})',
    _ => action.reason,
  };
  final bits = <String>[
    label.padRight(8),
    id,
    if (title.isNotEmpty) title,
    if (detail.isNotEmpty) detail,
  ];
  return bits.join('  ');
}

Map<String, Object?> c2RotaPlanJson(C2RotaPlan plan) {
  Map<String, Object?> brief(C2RotaAction action) => {
    'kind': action.kind.name,
    'id': action.docId,
    'date': action.date,
    'show': action.show,
    'summary': action.summary,
    'reason': action.reason,
  };
  return {
    'canCommit': plan.canCommit,
    'blockReason': plan.blockReason,
    'stale': plan.staleReason != null,
    'generatedAt': plan.generatedAt.toUtc().toIso8601String(),
    'window': {'start': plan.window.start.ymd, 'end': plan.window.end.ymd},
    'confirms': [for (final action in plan.confirms) action.docId],
    'deletes': [for (final action in plan.deletes) action.docId],
    'actions': [for (final action in plan.actions) brief(action)],
  };
}

String c2RotaAuditId(DateTime appliedAt, String planKey) {
  final utc = appliedAt.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  final stamp =
      '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
      'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}${ms}Z';
  final suffix = _fnv32(planKey).toRadixString(16).padLeft(8, '0');
  final id = 'c2sync-$stamp-$suffix';
  if (!RegExp(_auditIdPattern).hasMatch(id)) {
    throw StateError('Could not build a reconcile audit id.');
  }
  return id;
}

bool isC2RotaAuditId(String raw) =>
    RegExp(_auditIdPattern).hasMatch(raw.trim());

int _fnv32(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// Atomic commit: status patches, deletes, and the rollback audit together.
/// Throws when the plan is blocked or a mutation has no snapshot.
List<Map<String, dynamic>> c2RotaCommitWrites({
  required String projectId,
  required String hubId,
  required C2RotaPlan plan,
  required String auditId,
  required DateTime appliedAt,
}) {
  validateHubId(hubId);
  if (!isC2RotaAuditId(auditId)) {
    throw StateError('Audit id is not a c2 rota reconcile id.');
  }
  if (plan.blockReason != null) {
    throw StateError('Refusing to build writes: ${plan.blockReason}');
  }
  if (!plan.hasMutations) return const [];
  if (!plan.preconditionsReady) {
    throw StateError(
      'Refusing to build writes without updateTime and a before-image.',
    );
  }

  final mutations = [...plan.confirms, ...plan.deletes]
    ..sort((a, b) => a.docId!.compareTo(b.docId!));
  final writes = <Map<String, dynamic>>[
    for (final action in mutations) _mutationWrite(projectId, hubId, action),
    _auditWrite(
      projectId: projectId,
      hubId: hubId,
      auditId: auditId,
      plan: plan,
      mutations: mutations,
      appliedAt: appliedAt,
      kind: 'c2-rota-reconcile',
      reverts: null,
    ),
  ];
  return writes;
}

Map<String, dynamic> _mutationWrite(
  String projectId,
  String hubId,
  C2RotaAction action,
) {
  final name = _eventName(projectId, hubId, action.docId!);
  final updateTime = action.event!.updateTime!;
  if (action.kind == C2RotaActionKind.delete) {
    return {
      'delete': name,
      'currentDocument': {'updateTime': updateTime},
    };
  }
  return {
    'update': {
      'name': name,
      'fields': {
        'status': {'stringValue': eventStatusConfirmed},
      },
    },
    'updateMask': {
      'fieldPaths': ['status'],
    },
    'currentDocument': {'updateTime': updateTime},
  };
}

Map<String, dynamic> _auditWrite({
  required String projectId,
  required String hubId,
  required String auditId,
  required C2RotaPlan? plan,
  required List<C2RotaAction> mutations,
  required DateTime appliedAt,
  required String kind,
  required String? reverts,
}) {
  final fields = <String, dynamic>{
    'kind': {'stringValue': kind},
    'hubId': {'stringValue': hubId},
    'appliedAt': {'timestampValue': appliedAt.toUtc().toIso8601String()},
    if (plan != null)
      'feedGeneratedAt': {
        'timestampValue': plan.generatedAt.toUtc().toIso8601String(),
      },
    if (reverts != null) 'reverts': {'stringValue': reverts},
    'planKey': {'stringValue': plan?.planKey ?? reverts ?? ''},
    'confirmCount': {'integerValue': '${plan?.confirms.length ?? 0}'},
    'deleteCount': {'integerValue': '${plan?.deletes.length ?? 0}'},
    'changesJson': {'stringValue': jsonEncode(_changeRecords(mutations))},
  };
  return {
    'update': {'name': _auditName(projectId, hubId, auditId), 'fields': fields},
    'updateMask': {'fieldPaths': fields.keys.toList()},
  };
}

List<Map<String, Object?>> _changeRecords(List<C2RotaAction> mutations) {
  return [
    for (final action in mutations)
      {
        'op': action.kind == C2RotaActionKind.delete ? 'delete' : 'confirm',
        'docId': action.docId,
        'summary': action.summary,
        'date': action.date,
        'show': action.show,
        'tom': action.tom,
        'feedStatus': action.feedStatus,
        'beforeStatus': action.event?.status,
        'updateTime': action.event?.updateTime,
        'beforeFields': action.event?.restFields,
      },
  ];
}

String _eventName(String projectId, String hubId, String docId) {
  return 'projects/$projectId/databases/(default)/documents/'
      'hubs/$hubId/events/$docId';
}

String _auditName(String projectId, String hubId, String auditId) {
  return 'projects/$projectId/databases/(default)/documents/'
      'hubs/$hubId/$c2RotaAuditCollection/$auditId';
}

class C2AuditChange {
  const C2AuditChange({
    required this.op,
    required this.docId,
    required this.beforeFields,
    required this.beforeStatus,
  });

  final String op;
  final String docId;
  final Map<String, dynamic> beforeFields;
  final String? beforeStatus;
}

class C2RotaAudit {
  const C2RotaAudit({
    required this.runId,
    required this.hubId,
    required this.kind,
    required this.changes,
  });

  final String runId;
  final String hubId;
  final String kind;
  final List<C2AuditChange> changes;
}

class C2RollbackAction {
  const C2RollbackAction({
    required this.op,
    required this.docId,
    required this.reason,
    this.fields,
    this.updateTime,
  });

  /// `restoreStatus` or `recreate`. Rollback never deletes.
  final String op;
  final String docId;
  final String reason;
  final Map<String, dynamic>? fields;
  final String? updateTime;
}

class C2RollbackPlan {
  const C2RollbackPlan({required this.actions, required this.blockReason});

  final List<C2RollbackAction> actions;
  final String? blockReason;

  List<C2RollbackAction> get writes =>
      actions.where((action) => action.fields != null).toList();
}

List<C2StoredEvent> c2EventsFromRunQuery(Object? decoded) {
  if (decoded is! List) {
    throw C2RotaFeedException('Unexpected Firestore query response.');
  }
  final events = <C2StoredEvent>[];
  for (final row in decoded) {
    if (row is! Map) continue;
    final document = row['document'];
    if (document == null) continue;
    if (document is! Map) {
      throw C2RotaFeedException('Unexpected Firestore query document.');
    }
    events.add(c2EventFromRestDocument(Map<String, dynamic>.from(document)));
  }
  return events;
}

C2StoredEvent c2EventFromRestDocument(Map<String, dynamic> document) {
  final name = document['name'];
  if (name is! String || !name.contains('/events/')) {
    throw C2RotaFeedException('Firestore document name is missing.');
  }
  final id = Uri.decodeComponent(name.split('/').last);
  final fieldsRaw = document['fields'];
  final fields = fieldsRaw is Map
      ? Map<String, dynamic>.from(fieldsRaw)
      : <String, dynamic>{};
  String? stringField(String key) {
    final value = fields[key];
    if (value is Map && value['stringValue'] is String) {
      return value['stringValue'] as String;
    }
    return null;
  }

  DateTime? timestampField(String key) {
    final value = fields[key];
    if (value is Map && value['timestampValue'] is String) {
      return DateTime.parse(value['timestampValue'] as String).toUtc();
    }
    return null;
  }

  final updateTime = document['updateTime'];
  return C2StoredEvent(
    docId: id,
    source: stringField('source'),
    externalId: stringField('externalId'),
    summary: stringField('summary'),
    startUtc: timestampField('start'),
    status: stringField('status'),
    updateTime: updateTime is String ? updateTime : null,
    restFields: fields,
  );
}

List<C2StoredEvent> parseC2EventFixture(Object? decoded) {
  if (decoded is! List) {
    throw C2RotaFeedException('Events file must be a JSON array.');
  }
  final events = <C2StoredEvent>[];
  for (var i = 0; i < decoded.length; i++) {
    final item = decoded[i];
    if (item is! Map) {
      throw C2RotaFeedException('events[$i] must be an object.');
    }
    final map = Map<String, dynamic>.from(item);
    if (map.containsKey('fields') && map.containsKey('name')) {
      events.add(c2EventFromRestDocument(map));
      continue;
    }
    final idRaw = map['id'] ?? map['docId'];
    if (idRaw is! String || idRaw.trim().isEmpty) {
      throw C2RotaFeedException('events[$i].id is required.');
    }
    DateTime? start;
    final startRaw = map['start'];
    if (startRaw != null) {
      if (startRaw is! String) {
        throw C2RotaFeedException(
          'events[$i].start must be an ISO-8601 string.',
        );
      }
      try {
        start = DateTime.parse(startRaw.trim()).toUtc();
      } on FormatException {
        throw C2RotaFeedException('events[$i].start is not a timestamp.');
      }
    }
    final status = map['status'];
    if (status != null && status is! String) {
      throw C2RotaFeedException('events[$i].status must be a string.');
    }
    events.add(
      C2StoredEvent(
        docId: idRaw.trim(),
        source: map['source'] is String
            ? (map['source'] as String).trim()
            : null,
        externalId: map['externalId'] is String
            ? (map['externalId'] as String).trim()
            : null,
        summary: map['summary'] is String ? map['summary'] as String : null,
        startUtc: start,
        status: status as String?,
        updateTime: map['updateTime'] is String
            ? map['updateTime'] as String
            : null,
        restFields: map['restFields'] is Map
            ? Map<String, dynamic>.from(map['restFields'] as Map)
            : null,
      ),
    );
  }
  return events;
}

C2RotaAudit parseC2RotaAuditDocument({
  required String runId,
  required Map<String, dynamic> document,
}) {
  if (!isC2RotaAuditId(runId)) {
    throw C2RotaFeedException('Rollback id is not a c2 rota audit id.');
  }
  final fields = document['fields'];
  if (fields is! Map) {
    throw C2RotaFeedException('Audit document has no fields.');
  }
  final map = Map<String, dynamic>.from(fields);
  String? stringField(String key) {
    final value = map[key];
    if (value is Map && value['stringValue'] is String) {
      return value['stringValue'] as String;
    }
    return null;
  }

  final kind = stringField('kind');
  final hubId = stringField('hubId');
  final changesJson = stringField('changesJson');
  if (kind != 'c2-rota-reconcile' || hubId == null || changesJson == null) {
    throw C2RotaFeedException(
      'Audit $runId is not an applied c2 rota reconcile record.',
    );
  }
  validateHubId(hubId);
  late final Object? decoded;
  try {
    decoded = jsonDecode(changesJson);
  } on FormatException {
    throw C2RotaFeedException('Audit $runId changes could not be read.');
  }
  if (decoded is! List) {
    throw C2RotaFeedException('Audit $runId changes could not be read.');
  }
  final changes = <C2AuditChange>[];
  for (final item in decoded) {
    if (item is! Map) {
      throw C2RotaFeedException('Audit $runId changes could not be read.');
    }
    final change = Map<String, dynamic>.from(item);
    final op = change['op'];
    final docId = change['docId'];
    final before = change['beforeFields'];
    if (op is! String || docId is! String || before is! Map) {
      throw C2RotaFeedException('Audit $runId is missing a before-image.');
    }
    if (op != 'confirm' && op != 'delete') {
      throw C2RotaFeedException('Audit $runId has an unknown change.');
    }
    final beforeStatus = change['beforeStatus'];
    changes.add(
      C2AuditChange(
        op: op,
        docId: docId,
        beforeFields: Map<String, dynamic>.from(before),
        beforeStatus: beforeStatus is String ? beforeStatus : null,
      ),
    );
  }
  return C2RotaAudit(runId: runId, hubId: hubId, kind: kind!, changes: changes);
}

C2RollbackPlan planC2RotaRollback({
  required C2RotaAudit audit,
  required List<C2StoredEvent> currentEvents,
}) {
  final current = {for (final event in currentEvents) event.docId: event};
  final actions = <C2RollbackAction>[];
  for (final change in audit.changes) {
    if (!isImportedC2RotaDoc(
      C2StoredEvent(
        docId: change.docId,
        source: _restString(change.beforeFields, 'source'),
        externalId: _restString(change.beforeFields, 'externalId'),
      ),
    )) {
      actions.add(
        C2RollbackAction(
          op: 'skip',
          docId: change.docId,
          reason: 'before-image is not an imported c2-rota event',
        ),
      );
      continue;
    }
    final live = current[change.docId];
    if (change.op == 'confirm') {
      if (live == null) {
        actions.add(
          C2RollbackAction(
            op: 'skip',
            docId: change.docId,
            reason: 'event is missing; status was not restored',
          ),
        );
        continue;
      }
      if (!c2IsConfirmedStatus(live.status) || !isImportedC2RotaDoc(live)) {
        actions.add(
          C2RollbackAction(
            op: 'skip',
            docId: change.docId,
            reason: 'event is no longer a confirmed imported c2-rota event',
          ),
        );
        continue;
      }
      if (!c2IsTentativeStatus(change.beforeStatus)) {
        actions.add(
          C2RollbackAction(
            op: 'skip',
            docId: change.docId,
            reason: 'before-image was not tentative',
          ),
        );
        continue;
      }
      final updateTime = live.updateTime?.trim() ?? '';
      if (updateTime.isEmpty) {
        actions.add(
          C2RollbackAction(
            op: 'skip',
            docId: change.docId,
            reason: 'missing updateTime; status was not restored',
          ),
        );
        continue;
      }
      actions.add(
        C2RollbackAction(
          op: 'restoreStatus',
          docId: change.docId,
          reason: 'status confirmed -> tentative',
          fields: {
            'status': {'stringValue': eventStatusTentative},
          },
          updateTime: updateTime,
        ),
      );
      continue;
    }
    if (live != null) {
      actions.add(
        C2RollbackAction(
          op: 'skip',
          docId: change.docId,
          reason: 'event already exists; not recreated',
        ),
      );
      continue;
    }
    actions.add(
      C2RollbackAction(
        op: 'recreate',
        docId: change.docId,
        reason: 'recreate deleted tentative event',
        fields: change.beforeFields,
      ),
    );
  }
  return C2RollbackPlan(actions: actions, blockReason: null);
}

String? _restString(Map<String, dynamic> fields, String key) {
  final value = fields[key];
  if (value is Map && value['stringValue'] is String) {
    return value['stringValue'] as String;
  }
  return null;
}

List<Map<String, dynamic>> c2RollbackCommitWrites({
  required String projectId,
  required String hubId,
  required C2RollbackPlan plan,
  required String sourceAuditId,
  required String rollbackAuditId,
  required DateTime appliedAt,
}) {
  validateHubId(hubId);
  if (!isC2RotaAuditId(sourceAuditId) || !isC2RotaAuditId(rollbackAuditId)) {
    throw StateError('Rollback audit id is not valid.');
  }
  if (plan.blockReason != null) {
    throw StateError('Refusing rollback: ${plan.blockReason}');
  }
  final writes = <Map<String, dynamic>>[];
  for (final action in plan.writes) {
    final name = _eventName(projectId, hubId, action.docId);
    if (action.op == 'recreate') {
      writes.add({
        'update': {'name': name, 'fields': action.fields},
        'updateMask': {'fieldPaths': action.fields!.keys.toList()},
        'currentDocument': {'exists': false},
      });
      continue;
    }
    if (action.op == 'restoreStatus') {
      writes.add({
        'update': {'name': name, 'fields': action.fields},
        'updateMask': {
          'fieldPaths': ['status'],
        },
        'currentDocument': {'updateTime': action.updateTime},
      });
    }
  }
  if (writes.isEmpty) return const [];
  final fields = <String, dynamic>{
    'kind': {'stringValue': 'c2-rota-reconcile-rollback'},
    'hubId': {'stringValue': hubId},
    'reverts': {'stringValue': sourceAuditId},
    'appliedAt': {'timestampValue': appliedAt.toUtc().toIso8601String()},
    'changesJson': {
      'stringValue': jsonEncode([
        for (final action in plan.writes)
          {'op': action.op, 'docId': action.docId, 'reason': action.reason},
      ]),
    },
  };
  writes.add({
    'update': {
      'name': _auditName(projectId, hubId, rollbackAuditId),
      'fields': fields,
    },
    'updateMask': {'fieldPaths': fields.keys.toList()},
  });
  return writes;
}

C2ReconcileCommand parseC2ReconcileArgs(
  List<String> args, {
  Map<String, String> environment = const {},
}) {
  var help = false;
  var apply = false;
  var dryRun = false;
  String? hub = _trimmed(environment['HUB_ID']);
  String? feedFile;
  String? eventsFile;
  var tokenFile =
      _trimmed(environment['TOM_ROTA_FEED_TOKEN_FILE']) ??
      defaultTomRotaTokenFile;
  String? rollbackId;
  String? auditDir;
  String? jsonOut;
  var maxConfirms = c2RotaDefaultMaxConfirms;
  var maxDeletes = c2RotaDefaultMaxDeletes;
  DateTime? now;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--help':
      case '-h':
        help = true;
        break;
      case '--apply':
        apply = true;
        break;
      case '--dry-run':
        dryRun = true;
        break;
      case '--hub':
        hub = _next(args, ++i, '--hub');
        break;
      case '--feed-file':
        feedFile = _next(args, ++i, '--feed-file');
        break;
      case '--events-file':
        eventsFile = _next(args, ++i, '--events-file');
        break;
      case '--token-file':
        tokenFile = _next(args, ++i, '--token-file');
        break;
      case '--rollback':
        rollbackId = _next(args, ++i, '--rollback');
        break;
      case '--audit-dir':
        auditDir = _next(args, ++i, '--audit-dir');
        break;
      case '--json-out':
        jsonOut = _next(args, ++i, '--json-out');
        break;
      case '--max-confirms':
        maxConfirms = _boundedInt(
          _next(args, ++i, '--max-confirms'),
          '--max-confirms',
          c2RotaAbsoluteMaxConfirms,
        );
        break;
      case '--max-deletes':
        maxDeletes = _boundedInt(
          _next(args, ++i, '--max-deletes'),
          '--max-deletes',
          c2RotaAbsoluteMaxDeletes,
        );
        break;
      case '--now':
        now = _parseNow(_next(args, ++i, '--now'));
        break;
      default:
        throw C2RotaArgsException('Unknown option $arg');
    }
  }

  if (help) {
    return C2ReconcileCommand(
      help: true,
      apply: false,
      hubId: hub,
      feedFile: feedFile,
      eventsFile: eventsFile,
      tokenFile: tokenFile,
      rollbackId: rollbackId,
      auditDir: auditDir,
      jsonOut: jsonOut,
      maxConfirms: maxConfirms,
      maxDeletes: maxDeletes,
      now: now,
    );
  }
  if (apply && dryRun) {
    throw C2RotaArgsException('Pass either --apply or --dry-run.');
  }
  if (apply && now != null) {
    throw C2RotaArgsException('--now is for a fixture dry-run, not --apply.');
  }
  if (apply && eventsFile != null) {
    throw C2RotaArgsException(
      '--apply reads events from Firestore. --events-file is dry-run only.',
    );
  }
  if (rollbackId != null && (feedFile != null || eventsFile != null)) {
    throw C2RotaArgsException(
      '--rollback does not take a feed or events file.',
    );
  }
  if (rollbackId != null && !isC2RotaAuditId(rollbackId)) {
    throw C2RotaArgsException(
      '--rollback expects an audit id like c2sync-20261108T120000000Z-0123abcd.',
    );
  }
  final resolvedHub = _trimmed(hub);
  if (resolvedHub == null) {
    throw C2RotaArgsException('Pass --hub <hubId> or set HUB_ID.');
  }
  try {
    validateHubId(resolvedHub);
  } on EventImportException catch (error) {
    throw C2RotaArgsException(error.message);
  }
  return C2ReconcileCommand(
    help: false,
    apply: apply,
    hubId: resolvedHub,
    feedFile: feedFile,
    eventsFile: eventsFile,
    tokenFile: tokenFile,
    rollbackId: rollbackId,
    auditDir: auditDir,
    jsonOut: jsonOut,
    maxConfirms: maxConfirms,
    maxDeletes: maxDeletes,
    now: now,
  );
}

String _next(List<String> args, int index, String flag) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw C2RotaArgsException('Missing value for $flag');
  }
  return args[index];
}

int _boundedInt(String raw, String flag, int absoluteMax) {
  final value = int.tryParse(raw.trim());
  if (value == null || value < 0 || value > absoluteMax) {
    throw C2RotaArgsException(
      '$flag must be an integer from 0 to $absoluteMax.',
    );
  }
  return value;
}

DateTime _parseNow(String raw) {
  try {
    return DateTime.parse(raw.trim()).toUtc();
  } on FormatException {
    throw C2RotaArgsException('--now must be an ISO-8601 timestamp.');
  }
}

String? _trimmed(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}
