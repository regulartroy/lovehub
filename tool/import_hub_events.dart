// Bulk-imports Roger's work-calendar JSON into hubs/{hubId}/events.
//
//   dart run tool/import_hub_events.dart --hub <hubId> --file events.json
//   dart run tool/import_hub_events.dart --tentative --file rota.json
//   dart run tool/import_hub_events.dart --confirm c2-rota:2026-09-20
//   dart run tool/import_hub_events.dart --dry-run --file events.json
//
// Auth (environment only — never commit these):
//   FIREBASE_ID_TOKEN        hub member ID token
//   FIREBASE_REFRESH_TOKEN   hub member refresh token
//   HUB_ID                   optional stand-in for --hub
//
// See docs/event-import.md.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lovehub/event_import/imported_event.dart';

const _usage = '''
Import work events into a LoveHub hub (idempotent upsert).

  dart run tool/import_hub_events.dart --hub <hubId> --file events.json
  dart run tool/import_hub_events.dart --tentative --file rota.json
  dart run tool/import_hub_events.dart --hub <hubId> --confirm c2-rota:2026-09-20
  dart run tool/import_hub_events.dart --dry-run --file events.json

--tentative marks events that omit status as tentative (a C2 rota dump).
--confirm source:externalId flips that one event to confirmed.
HUB_ID can replace --hub.
Set FIREBASE_ID_TOKEN or FIREBASE_REFRESH_TOKEN to a hub member's credential.
Payload: one event, a JSON array, or {"events":[...]}.
''';

Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final command = parseImportCommand(
      args,
      hubFromEnvironment: Platform.environment['HUB_ID'],
    );
    if (command.help) {
      stdout.writeln(_usage.trim());
      return;
    }
    if (command.confirm.isNotEmpty) {
      await _confirm(client, command);
      return;
    }

    final raw = await _readPayload(command.file);
    final decoded = jsonDecode(raw);

    String? idToken;
    HubDirectory? directory;
    if (!command.dryRun || _hasCredential()) {
      idToken = await _resolveIdToken(client, required: !command.dryRun);
    }

    if (!command.dryRun) {
      final hubId = command.hubId;
      if (hubId == null) {
        throw EventImportException('Pass --hub <hubId> or set HUB_ID.');
      }
      validateHubId(hubId);
      directory = await _loadDirectory(client, idToken!, hubId);
      final uid = uidFromFirebaseIdToken(idToken);
      requireHubMember(uid: uid, memberUids: directory.memberUids);
      final events = parseEventImport(
        decoded,
        members: directory.members,
        defaultStatus: command.defaultStatus,
      );
      if (events.isEmpty) {
        stdout.writeln('No events to import.');
        return;
      }
      final writes = [
        for (final event in events)
          firestoreRestWrite(
            projectId: lovehubFirebaseProjectId,
            hubId: hubId,
            event: event,
            ownerId: uid,
          ),
      ];
      await _commit(client, idToken, writes);
      stdout.writeln(
        'Upserted ${events.length} event${events.length == 1 ? '' : 's'} '
        'into hubs/$hubId/events',
      );
      for (final event in events) {
        stdout.writeln(
          '  ${event.docId}  ${_statusLabel(event.status)}  ${event.summary}',
        );
      }
      return;
    }

    if (idToken != null && command.hubId != null) {
      validateHubId(command.hubId!);
      directory = await _loadDirectory(client, idToken, command.hubId!);
      final uid = uidFromFirebaseIdToken(idToken);
      requireHubMember(uid: uid, memberUids: directory.memberUids);
    }

    final events = parseEventImport(
      decoded,
      members: directory?.members ?? const [],
      defaultStatus: command.defaultStatus,
    );
    stdout.writeln(
      'Dry run: ${events.length} event${events.length == 1 ? '' : 's'} '
      '(nothing written)',
    );
    if (directory == null) {
      stdout.writeln(
        'No hub credential supplied, so assignedTo tokens were left as written.',
      );
    }
    for (final event in events) {
      stdout.writeln(
        '  ${event.docId}  ${_statusLabel(event.status)}  ${event.assignedTo}  '
        '${event.start.toUtc().toIso8601String()}  ${event.summary}',
      );
    }
  } on EventImportException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Invalid JSON: ${error.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}

String _statusLabel(String? status) => status ?? 'confirmed (default)';

Future<void> _confirm(http.Client client, ImportCommand command) async {
  if (command.dryRun) {
    stdout.writeln(
      'Dry run: would confirm ${command.confirm.length} event'
      '${command.confirm.length == 1 ? '' : 's'} (nothing written)',
    );
    for (final target in command.confirm) {
      stdout.writeln('  ${target.docId}  confirmed');
    }
    return;
  }

  final hubId = command.hubId;
  if (hubId == null) {
    throw EventImportException('Pass --hub <hubId> or set HUB_ID.');
  }
  validateHubId(hubId);
  final idToken = await _resolveIdToken(client, required: true);
  final directory = await _loadDirectory(client, idToken, hubId);
  final uid = uidFromFirebaseIdToken(idToken);
  requireHubMember(uid: uid, memberUids: directory.memberUids);
  for (final target in command.confirm) {
    try {
      await _commit(client, idToken, [
        firestoreRestConfirmWrite(
          projectId: lovehubFirebaseProjectId,
          hubId: hubId,
          target: target,
        ),
      ], requireExisting: true);
    } on EventImportException catch (error) {
      throw EventImportException('${target.docId}: ${error.message}');
    }
    stdout.writeln('Confirmed ${target.docId}');
  }
}

bool _hasCredential() {
  final id = Platform.environment['FIREBASE_ID_TOKEN']?.trim() ?? '';
  final refresh = Platform.environment['FIREBASE_REFRESH_TOKEN']?.trim() ?? '';
  return id.isNotEmpty || refresh.isNotEmpty;
}

Future<String> _readPayload(String? file) async {
  if (file != null) return File(file).readAsString();
  if (stdin.hasTerminal) {
    throw EventImportException(
      'Pass --file <events.json> or pipe JSON on stdin.\n$_usage',
    );
  }
  return stdin.transform(utf8.decoder).join();
}

Future<String> _resolveIdToken(
  http.Client client, {
  required bool required,
}) async {
  final direct = Platform.environment['FIREBASE_ID_TOKEN']?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final refresh = Platform.environment['FIREBASE_REFRESH_TOKEN']?.trim();
  if (refresh != null && refresh.isNotEmpty) {
    return _exchangeRefreshToken(client, refresh);
  }
  throw EventImportException(
    required
        ? 'Set FIREBASE_ID_TOKEN or FIREBASE_REFRESH_TOKEN for a hub member. '
              'Do not commit either value.'
        : 'No Firebase credential in the environment.',
  );
}

Future<String> _exchangeRefreshToken(
  http.Client client,
  String refreshToken,
) async {
  final uri = Uri.parse(
    'https://securetoken.googleapis.com/v1/token?key=$lovehubFirebaseWebApiKey',
  );
  final response = await client.post(
    uri,
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw EventImportException(
      'Could not exchange FIREBASE_REFRESH_TOKEN (${response.statusCode}).',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map || decoded['id_token'] is! String) {
    throw EventImportException('Refresh response did not include an ID token.');
  }
  return decoded['id_token'] as String;
}

Future<HubDirectory> _loadDirectory(
  http.Client client,
  String idToken,
  String hubId,
) async {
  final hub = await _getDocument(client, idToken, 'hubs/$hubId');
  if (hub == null) {
    throw EventImportException('Hub $hubId was not found.');
  }
  final directory = parseHubDirectory(hub);
  if (directory.memberUids.isEmpty) {
    throw EventImportException('Hub $hubId has no members.');
  }

  final names = Map<String, String>.from(directory.displayNames);
  for (final uid in directory.memberUids) {
    if ((names[uid] ?? '').trim().isNotEmpty) continue;
    final user = await _getDocument(client, idToken, 'users/$uid');
    if (user == null) continue;
    final displayName = parseUserDisplayName(user);
    if (displayName != null) names[uid] = displayName;
  }
  return HubDirectory(memberUids: directory.memberUids, displayNames: names);
}

Future<Map<String, dynamic>?> _getDocument(
  http.Client client,
  String idToken,
  String path,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/$path',
  );
  final response = await client.get(
    uri,
    headers: {'Authorization': 'Bearer $idToken'},
  );
  if (response.statusCode == 404) return null;
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw EventImportException(
      'Could not read $path (${response.statusCode}).',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    throw EventImportException('Unexpected Firestore response for $path.');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<void> _commit(
  http.Client client,
  String idToken,
  List<Map<String, dynamic>> writes, {
  bool requireExisting = false,
}) async {
  const chunkSize = 400;
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents:commit',
  );
  for (var i = 0; i < writes.length; i += chunkSize) {
    final end = i + chunkSize > writes.length ? writes.length : i + chunkSize;
    final response = await client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'writes': writes.sublist(i, end)}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final missing =
          requireExisting &&
          (response.body.contains('NOT_FOUND') ||
              response.body.contains('FAILED_PRECONDITION'));
      throw EventImportException(
        missing
            ? 'No imported event to confirm. Import it first.'
            : 'Firestore commit failed (${response.statusCode}).',
      );
    }
  }
}
