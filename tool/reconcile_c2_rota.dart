// Reconcile imported Concorde rota events in hubs/{hubId}/events.
//
//   dart run tool/reconcile_c2_rota.dart --hub <hubId> --feed-file feed.json --events-file events.json --now 2026-11-08T12:00:00Z
//   dart run tool/reconcile_c2_rota.dart --hub <hubId>
//   dart run tool/reconcile_c2_rota.dart --hub <hubId> --apply
//   dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId>
//   dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId> --apply
//
// Default is dry-run. --apply writes. See docs/c2-rota-reconcile.md.
//
// Feed token: file path only (default /home/box/secrets/tom_rota_feed_token).
// Firestore: firebase login, FIREBASE_TOKEN, GOOGLE_ACCESS_TOKEN, or gcloud.
// No service-account file. The token is never printed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/firebase_cli_auth.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/services/web_build_stamp.dart';

const _usage = '''
Reconcile imported c2-rota events with the Concorde rota feed.

  dart run tool/reconcile_c2_rota.dart --hub <hubId>
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --apply
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId>
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId> --apply

Default is dry-run (nothing written). --apply confirms or deletes.
HUB_ID can replace --hub.

Only imported documents are in scope: source c2-rota and id c2-rota:{externalId}.
Tentative + tom=working + status=on is confirmed.
Tentative + cancelled, or tentative + tom=not_working, is deleted.
Undecided stays tentative. Confirmed documents are never changed or deleted.
A show is matched on its own, not by date alone. Missing, empty, stale, or
invalid feeds write nothing. Ambiguous matches are skipped.

Feed token file (the token itself is never an argument):
  /home/box/secrets/tom_rota_feed_token
  --token-file <path>    or TOM_ROTA_FEED_TOKEN_FILE

Credential-free review:
  dart run tool/reconcile_c2_rota.dart --hub <hubId> \\
    --feed-file tool/c2_rota_feed_example.json \\
    --events-file tool/c2_rota_events_example.json \\
    --now 2026-11-08T12:00:00Z

Firestore auth is the existing firebase login (or GOOGLE_ACCESS_TOKEN /
FIREBASE_TOKEN / gcloud). --events-file and --now cannot be combined with
--apply. Caps default to 12 confirms and 8 deletes (absolute max 40).
''';

Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final command = parseC2ReconcileArgs(
      args,
      environment: Platform.environment,
    );
    if (command.help) {
      stdout.writeln(_usage.trim());
      return;
    }
    if (command.rollbackId != null) {
      await _rollback(client, command);
      return;
    }
    await _reconcile(client, command);
  } on C2RotaArgsException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on C2RotaFeedException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on FirebaseCliAuthException catch (error) {
    stderr.writeln(error.message);
    exitCode = 4;
  } on C2RotaWriteException catch (error) {
    stderr.writeln(error.message);
    exitCode = error.exitCode;
  } on FormatException {
    stderr.writeln('Invalid JSON.');
    exitCode = 2;
  } on TimeoutException {
    stderr.writeln('Feed request timed out.');
    exitCode = 2;
  } on SocketException {
    stderr.writeln('Could not reach the rota feed.');
    exitCode = 2;
  } on HttpException {
    stderr.writeln('Feed request failed.');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read ${error.path ?? 'a local file'}.');
    exitCode = 1;
  } finally {
    client.close();
  }
}

Future<void> _reconcile(http.Client client, C2ReconcileCommand command) async {
  final hubId = command.hubId!;
  final now = command.now ?? DateTime.now().toUtc();
  final feed = parseC2RotaFeed(await _loadFeed(command));
  final events = command.eventsFile != null
      ? parseC2EventFixture(_readJsonFile(command.eventsFile!))
      : await _queryEvents(client, hubId, await _googleAccessToken(client));
  final plan = planC2RotaReconcile(
    feed: feed,
    events: events,
    now: now,
    maxConfirms: command.maxConfirms,
    maxDeletes: command.maxDeletes,
  );
  stdout.write(renderC2RotaPlan(plan, hubId: hubId, applying: command.apply));
  _writePlanFiles(command, plan);

  if (!command.apply) {
    exitCode = plan.blockReason == null ? 0 : 2;
    return;
  }
  if (!plan.canCommit) {
    exitCode = 2;
    return;
  }
  if (!plan.hasMutations) return;

  final appliedAt = DateTime.now().toUtc();
  final auditId = c2RotaAuditId(appliedAt, plan.planKey);
  final writes = c2RotaCommitWrites(
    projectId: lovehubFirebaseProjectId,
    hubId: hubId,
    plan: plan,
    auditId: auditId,
    appliedAt: appliedAt,
  );
  _writePendingAudit(command, auditId, writes);
  await _commit(client, await _googleAccessToken(client), writes);
  stdout.writeln('Applied audit hubs/$hubId/$c2RotaAuditCollection/$auditId');
}

Future<void> _rollback(http.Client client, C2ReconcileCommand command) async {
  final hubId = command.hubId!;
  final auditId = command.rollbackId!;
  final access = await _googleAccessToken(client);
  final document = await _getDocument(
    client,
    access,
    'hubs/${Uri.encodeComponent(hubId)}/$c2RotaAuditCollection/${Uri.encodeComponent(auditId)}',
  );
  final audit = parseC2RotaAuditDocument(runId: auditId, document: document);
  if (audit.hubId != hubId) {
    throw C2RotaFeedException('Audit $auditId belongs to a different hub.');
  }
  final current = await _queryEvents(client, hubId, access);
  final plan = planC2RotaRollback(audit: audit, currentEvents: current);
  stdout.writeln(
    command.apply ? 'C2 rota rollback: apply' : 'C2 rota rollback: dry-run',
  );
  stdout.writeln('hub: $hubId');
  stdout.writeln('reverts: $auditId');
  for (final action in plan.actions) {
    stdout.writeln('${action.op}  ${action.docId}  ${action.reason}');
  }
  stdout.writeln('rollback writes: ${plan.writes.length}');
  if (!command.apply || plan.writes.isEmpty) {
    stdout.writeln('nothing written');
    return;
  }
  final appliedAt = DateTime.now().toUtc();
  final rollbackId = c2RotaAuditId(appliedAt, 'rollback:$auditId');
  final writes = c2RollbackCommitWrites(
    projectId: lovehubFirebaseProjectId,
    hubId: hubId,
    plan: plan,
    sourceAuditId: auditId,
    rollbackAuditId: rollbackId,
    appliedAt: appliedAt,
  );
  await _commit(client, access, writes);
  stdout.writeln(
    'Applied rollback hubs/$hubId/$c2RotaAuditCollection/$rollbackId',
  );
}

Future<Object?> _loadFeed(C2ReconcileCommand command) async {
  if (command.feedFile != null) return _readJsonFile(command.feedFile!);
  final token = _loadFeedToken(command.tokenFile);
  return _fetchFeed(token);
}

String _loadFeedToken(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw C2RotaFeedException('Feed token file was not found at $path.');
  }
  try {
    return parseFeedToken(file.readAsStringSync());
  } on FileSystemException {
    throw C2RotaFeedException('Could not read the feed token file at $path.');
  }
}

Future<Object?> _fetchFeed(String token) async {
  final uri = requireC2RotaFeedUri(c2RotaFeedUrl);
  final io = HttpClient();
  try {
    io.connectionTimeout = const Duration(seconds: 20);
    final request = await io.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'lovehub-c2-rota-reconcile',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    return decodeC2FeedHttpBody(statusCode: response.statusCode, body: body);
  } finally {
    io.close(force: true);
  }
}

Object? _readJsonFile(String path) {
  return jsonDecode(File(path).readAsStringSync());
}

Future<List<C2StoredEvent>> _queryEvents(
  http.Client client,
  String hubId,
  String accessToken,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/hubs/${Uri.encodeComponent(hubId)}:runQuery',
  );
  final response = await client.post(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'events'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'source'},
            'op': 'EQUAL',
            'value': {'stringValue': c2RotaSource},
          },
        },
      },
    }),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw C2RotaFeedException(
      'Could not read c2-rota events (${response.statusCode}).',
    );
  }
  final decoded = jsonDecode(response.body);
  return c2EventsFromRunQuery(decoded);
}

Future<Map<String, dynamic>> _getDocument(
  http.Client client,
  String accessToken,
  String path,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/$path',
  );
  final response = await client.get(
    uri,
    headers: {'Authorization': 'Bearer $accessToken'},
  );
  if (response.statusCode == 404) {
    throw C2RotaFeedException('Audit document was not found.');
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw C2RotaFeedException(
      'Could not read the audit document (${response.statusCode}).',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    throw C2RotaFeedException('Unexpected audit response.');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<void> _commit(
  http.Client client,
  String accessToken,
  List<Map<String, dynamic>> writes,
) async {
  if (writes.isEmpty) return;
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents:commit',
  );
  final body = jsonEncode({'writes': writes});
  for (var attempt = 0; attempt < c2CommitMaxAttempts; attempt++) {
    final response = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final redacted = redactSecret(response.body, accessToken);
    if (c2CommitShouldRetry(response.statusCode, attempt)) {
      await Future<void>.delayed(Duration(milliseconds: 400 << attempt));
      continue;
    }
    if (c2CommitConflict(response.statusCode, redacted)) {
      throw C2RotaWriteException(
        'Firestore rejected the batch because a document changed since it '
        'was read. Nothing was written. The next run reads again.',
        exitCode: 3,
      );
    }
    throw C2RotaWriteException(
      'Firestore commit failed (${response.statusCode}). Nothing was written.',
      exitCode: 1,
    );
  }
}

Future<String> _googleAccessToken(http.Client client) {
  return selectFirebaseCliAccessToken(
    environment: Platform.environment,
    now: DateTime.now(),
    storedTokens: _readCliConfig(),
    readGcloudAccessToken: _gcloudAccessToken,
    exchangeRefreshToken: (refresh) => _exchangeRefreshToken(client, refresh),
  );
}

FirebaseCliTokens? _readCliConfig() {
  for (final path in firebaseCliConfigCandidates(Platform.environment)) {
    final file = File(path);
    if (!file.existsSync()) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      throw FirebaseCliAuthException('Could not read $path.');
    }
    if (decoded is! Map) {
      throw FirebaseCliAuthException('Could not read $path.');
    }
    return parseFirebaseCliConfig(Map<String, dynamic>.from(decoded));
  }
  return null;
}

Future<String?> _gcloudAccessToken() async {
  try {
    final result = await Process.run('gcloud', ['auth', 'print-access-token']);
    if (result.exitCode != 0) return null;
    final token = '${result.stdout}'.trim();
    if (token.isEmpty || token.contains('\n')) return null;
    return token;
  } on ProcessException {
    return null;
  }
}

Future<String> _exchangeRefreshToken(
  http.Client client,
  String refreshToken,
) async {
  final clientId = _envOr('FIREBASE_CLIENT_ID', firebaseToolsOauthClientId);
  final clientSecret = _envOr(
    'FIREBASE_CLIENT_SECRET',
    firebaseToolsOauthClientSecret,
  );
  final response = await client.post(
    Uri.parse('https://oauth2.googleapis.com/token'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
      'client_secret': clientSecret,
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw FirebaseCliAuthException(
      'Could not refresh the Firebase CLI credential '
      '(${response.statusCode}). Run `firebase login` again.',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map || decoded['access_token'] is! String) {
    throw FirebaseCliAuthException(
      'Token refresh did not return an access token.',
    );
  }
  final access = (decoded['access_token'] as String).trim();
  if (access.isEmpty) {
    throw FirebaseCliAuthException(
      'Token refresh did not return an access token.',
    );
  }
  return access;
}

String _envOr(String name, String fallback) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) return fallback;
  return value;
}

void _writePlanFiles(C2ReconcileCommand command, C2RotaPlan plan) {
  final jsonOut = command.jsonOut;
  if (jsonOut != null) {
    _writeText(jsonOut, _pretty(c2RotaPlanJson(plan)));
  }
  final auditDir = command.auditDir;
  if (auditDir == null) return;
  _writeText('$auditDir/plan.json', _pretty(c2RotaPlanJson(plan)));
}

void _writePendingAudit(
  C2ReconcileCommand command,
  String auditId,
  List<Map<String, dynamic>> writes,
) {
  final auditDir = command.auditDir;
  if (auditDir == null || writes.isEmpty) return;
  final update = writes.last['update'];
  if (update is! Map) return;
  final fields = update['fields'];
  if (fields is! Map) return;
  final changes = fields['changesJson'];
  if (changes is! Map || changes['stringValue'] is! String) return;
  _writeText(
    '$auditDir/pending-$auditId.json',
    changes['stringValue'] as String,
  );
}

void _writeText(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _pretty(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}
