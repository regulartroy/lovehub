// Reconcile imported Concorde rota events in the hubs collection (kHubsCollection).
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
// Firestore: Application Default Credentials via package:googleapis_auth.
// The Firebase CLI credential cache is not read. The feed token is never printed.
//
// Firestore MCP (firebase-tools, proxied from firestore.googleapis.com/mcp)
// can update or delete one document with a currentDocument precondition.
// It has no documents:commit tool, so a multi-document reconcile would not
// be atomic. This tool keeps one REST commit instead.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/services/hub_collection.dart';

const _usage = '''
Reconcile imported c2-rota events with the Concorde rota feed.

  dart run tool/reconcile_c2_rota.dart --hub <hubId>
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --apply
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId>
  dart run tool/reconcile_c2_rota.dart --hub <hubId> --rollback <auditId> --apply

Default is dry-run (nothing written). --apply confirms or deletes.
HUB_ID can replace --hub.

Only imported documents are in scope: source c2-rota and id c2-rota:{externalId}.
Tentative + tom=working + status=on is confirmed (including past dates).
Tentative + cancelled/postponed, or tentative + tom=not_working, is deleted
only for today and future Europe/London dates. Past history is left alone.
Undecided stays tentative. Confirmed documents are never changed or deleted.
Empty show rows and unknown statuses are skipped with a warning.
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

Firestore uses Application Default Credentials (googleapis_auth). One-time:
  gcloud auth application-default login
  gcloud auth application-default set-quota-project lovehub-26107
Do not create a service-account key. --events-file and --now cannot be
combined with --apply. Caps default to 12 confirms and 8 deletes
(absolute max 40).
''';

Future<void> main(List<String> args) async {
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
      await _rollback(command);
      return;
    }
    await _reconcile(command);
  } on C2RotaArgsException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on C2RotaFeedException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on C2RotaAuthException catch (error) {
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
  }
}

Future<void> _reconcile(C2ReconcileCommand command) async {
  final hubId = command.hubId!;
  final now = command.now ?? DateTime.now().toUtc();
  final feed = parseC2RotaFeed(await _loadFeed(command));
  AutoRefreshingAuthClient? firestore;
  late final List<C2StoredEvent> events;
  try {
    if (command.eventsFile == null) {
      firestore = await _firestoreClient();
    }
    events = command.eventsFile != null
        ? parseC2EventFixture(_readJsonFile(command.eventsFile!))
        : await _queryEvents(firestore!, hubId);
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
    await _commit(firestore!, writes);
    stdout.writeln(
      'Applied audit $kHubsCollection/$hubId/$c2RotaAuditCollection/$auditId',
    );
  } finally {
    firestore?.close();
  }
}

Future<void> _rollback(C2ReconcileCommand command) async {
  final hubId = command.hubId!;
  final auditId = command.rollbackId!;
  final firestore = await _firestoreClient();
  try {
    final document = await _getDocument(
      firestore,
      '$kHubsCollection/${Uri.encodeComponent(hubId)}/$c2RotaAuditCollection/${Uri.encodeComponent(auditId)}',
    );
    final audit = parseC2RotaAuditDocument(runId: auditId, document: document);
    if (audit.hubId != hubId) {
      throw C2RotaFeedException('Audit $auditId belongs to a different hub.');
    }
    final current = await _queryEvents(firestore, hubId);
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
    await _commit(firestore, writes);
    stdout.writeln(
      'Applied rollback $kHubsCollection/$hubId/$c2RotaAuditCollection/$rollbackId',
    );
  } finally {
    firestore.close();
  }
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

Future<AutoRefreshingAuthClient> _firestoreClient() async {
  try {
    return await clientViaApplicationDefaultCredentials(
      scopes: const [c2RotaFirestoreScope],
    );
  } catch (_) {
    // The library's last error on a normal computer is the GCE metadata
    // probe. The setup text is the actionable failure. Do not print it:
    // it is not a credential, and it hides the missing-login cause.
    throw C2RotaAuthException(c2RotaAdcUnavailableMessage(null));
  }
}

Map<String, String> _firestoreHeaders({bool json = false}) {
  return {
    if (json) 'Content-Type': 'application/json',
    'x-goog-user-project': lovehubFirebaseProjectId,
  };
}

void _refuseFirestoreStatus(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    throw C2RotaAuthException(
      c2RotaAdcUnavailableMessage(
        'Cloud Firestore refused the Application Default Credential ($statusCode).',
      ),
    );
  }
}

Future<List<C2StoredEvent>> _queryEvents(
  http.Client client,
  String hubId,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/$kHubsCollection/${Uri.encodeComponent(hubId)}:runQuery',
  );
  final response = await client.post(
    uri,
    headers: _firestoreHeaders(json: true),
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
  _refuseFirestoreStatus(response.statusCode);
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
  String path,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/$path',
  );
  final response = await client.get(uri, headers: _firestoreHeaders());
  if (response.statusCode == 404) {
    throw C2RotaFeedException('Audit document was not found.');
  }
  _refuseFirestoreStatus(response.statusCode);
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
      headers: _firestoreHeaders(json: true),
      body: body,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _refuseFirestoreStatus(response.statusCode);
    if (c2CommitShouldRetry(response.statusCode, attempt)) {
      await Future<void>.delayed(Duration(milliseconds: 400 << attempt));
      continue;
    }
    if (c2CommitConflict(response.statusCode, response.body)) {
      throw C2RotaWriteException(
        'Firestore rejected the batch because a document changed since it '
        'was read. Nothing was written. The next run reads again.',
        exitCode: 3,
      );
    }
    var detail = '';
    try {
      final err = jsonDecode(response.body);
      if (err is Map && err['error'] is Map) {
        detail = ': ${(err['error'] as Map)['message']}';
      }
    } catch (_) {}
    throw C2RotaWriteException(
      'Firestore commit failed (${response.statusCode})$detail. Nothing was written.',
      exitCode: 1,
    );
  }
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
