// Bulk-imports Roger's work-calendar JSON into hubs/{hubId}/events.
//
//   dart run tool/import_hub_events.dart --hub <hubId> --file events.json
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
  dart run tool/import_hub_events.dart --dry-run --file events.json

HUB_ID can replace --hub.
Set FIREBASE_ID_TOKEN or FIREBASE_REFRESH_TOKEN to a hub member's credential.
Payload: one event, a JSON array, or {"events":[...]}.
''';

Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final options = _parseArgs(args);
    if (options.help) {
      stdout.writeln(_usage.trim());
      return;
    }

    final raw = await _readPayload(options.file);
    final decoded = jsonDecode(raw);

    String? idToken;
    HubDirectory? directory;
    if (!options.dryRun || _hasCredential()) {
      idToken = await _resolveIdToken(client, required: !options.dryRun);
    }

    if (!options.dryRun) {
      final hubId = options.hubId;
      if (hubId == null) {
        throw EventImportException('Pass --hub <hubId> or set HUB_ID.');
      }
      validateHubId(hubId);
      directory = await _loadDirectory(client, idToken!, hubId);
      final uid = uidFromFirebaseIdToken(idToken);
      requireHubMember(uid: uid, memberUids: directory.memberUids);
      final events = parseEventImport(decoded, members: directory.members);
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
        stdout.writeln('  ${event.docId}  ${event.summary}');
      }
      return;
    }

    if (idToken != null && options.hubId != null) {
      validateHubId(options.hubId!);
      directory = await _loadDirectory(client, idToken, options.hubId!);
      final uid = uidFromFirebaseIdToken(idToken);
      requireHubMember(uid: uid, memberUids: directory.memberUids);
    }

    final events = parseEventImport(
      decoded,
      members: directory?.members ?? const [],
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
        '  ${event.docId}  ${event.assignedTo}  '
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

class _Options {
  const _Options({
    this.hubId,
    this.file,
    this.dryRun = false,
    this.help = false,
  });

  final String? hubId;
  final String? file;
  final bool dryRun;
  final bool help;
}

_Options _parseArgs(List<String> args) {
  String? hub = Platform.environment['HUB_ID']?.trim();
  String? file;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--help':
      case '-h':
        return const _Options(help: true);
      case '--dry-run':
        dryRun = true;
        break;
      case '--hub':
        hub = _next(args, ++i, '--hub');
        break;
      case '--file':
        file = _next(args, ++i, '--file');
        break;
      default:
        if (arg.startsWith('-')) {
          throw EventImportException('Unknown option $arg\n$_usage');
        }
        if (file != null) {
          throw EventImportException('Unexpected argument $arg\n$_usage');
        }
        file = arg;
    }
  }
  if (hub != null && hub.isEmpty) hub = null;
  return _Options(hubId: hub, file: file, dryRun: dryRun);
}

String _next(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw EventImportException('Missing value for $flag');
  }
  return args[index];
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
  List<Map<String, dynamic>> writes,
) async {
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
      throw EventImportException(
        'Firestore commit failed (${response.statusCode}).',
      );
    }
  }
}
