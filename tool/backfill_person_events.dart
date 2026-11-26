// Dry-run-first backfill of person-owned events into users/{uid}/events.
//
//   dart run tool/backfill_person_events.dart
//   dart run tool/backfill_person_events.dart --apply
//
// Reads sharedHubs/{hub}/events (default: Burroni, Tom and Paddy, Concorde 2)
// and writes only users/{uid}/events. Never writes to sharedHubs, hubs,
// userEvents, or firestore.rules. Default is dry-run.
//
// Firestore: Application Default Credentials via package:googleapis_auth.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/event_import/person_event_backfill.dart';
import 'package:lovehub/event_import/schedule_export.dart'
    hide firestoreRestValue;
import 'package:lovehub/services/hub_collection.dart';

const _defaultHubs = [
  defaultBurroniHubId,
  'EJZWvXNbW3YopoKvBsch',
  'SdiQFN2Iemqvfr91XA9V',
];

const _usage = '''
Backfill person-owned events into users/{uid}/events.

  dart run tool/backfill_person_events.dart
  dart run tool/backfill_person_events.dart --apply
  dart run tool/backfill_person_events.dart --hub <hubId> --hub <hubId>

Default is dry-run (nothing written). --apply upserts only
users/{uid}/events. Live sharedHubs documents are never written.
c2-rota conflicts prefer Burroni. Shared/meal/joint events stay on the hub
and are not copied (the 28 Nov date day stays Burroni-shared).
''';

class _BackfillCommand {
  const _BackfillCommand({
    required this.apply,
    required this.help,
    required this.hubIds,
  });

  final bool apply;
  final bool help;
  final List<String> hubIds;
}

Future<void> main(List<String> args) async {
  try {
    final command = _parse(args);
    if (command.help) {
      stdout.writeln(_usage.trim());
      return;
    }
    await _run(command);
  } on C2RotaAuthException catch (error) {
    stderr.writeln(error.message);
    exitCode = 4;
  } on FormatException {
    stderr.writeln('Invalid JSON from Firestore.');
    exitCode = 1;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln('Firestore request timed out.');
    exitCode = 1;
  } on SocketException {
    stderr.writeln('Could not reach Firestore.');
    exitCode = 1;
  }
}

_BackfillCommand _parse(List<String> args) {
  var apply = false;
  var dryRun = false;
  var help = false;
  final hubs = <String>[];
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
        if (i + 1 >= args.length) {
          throw ArgumentError('Missing value for --hub');
        }
        hubs.add(args[++i]);
        break;
      default:
        throw ArgumentError('Unknown option $arg');
    }
  }
  if (apply && dryRun) {
    throw ArgumentError('Pass either --apply or --dry-run.');
  }
  return _BackfillCommand(
    apply: apply,
    help: help,
    hubIds: hubs.isEmpty ? _defaultHubs : hubs,
  );
}

Future<void> _run(_BackfillCommand command) async {
  final client = await _firestoreClient();
  try {
    final candidates = <PersonBackfillCandidate>[];
    for (final hubId in command.hubIds) {
      final docs = await _listDocuments(
        client,
        '$kHubsCollection/${Uri.encodeComponent(hubId)}/events',
      );
      for (final doc in docs) {
        final id = firestoreDocumentId(doc);
        if (id == null || id.isEmpty) continue;
        final fieldsRaw = doc['fields'];
        final fields = fieldsRaw is Map
            ? firestoreRestFields(Map<String, dynamic>.from(fieldsRaw))
            : <String, Object?>{};
        DateTime? updateTime;
        final rawUpdate = doc['updateTime'];
        if (rawUpdate is String) {
          updateTime = DateTime.tryParse(rawUpdate)?.toUtc();
        }
        candidates.add(
          PersonBackfillCandidate(
            hubId: hubId,
            eventId: id,
            fields: fields,
            updateTime: updateTime,
          ),
        );
      }
    }

    final plan = planPersonEventBackfill(candidates);
    _printPlan(command, plan);

    if (!command.apply) return;
    if (plan.writes.isEmpty) {
      stdout.writeln('Nothing to write.');
      return;
    }
    await _commitWrites(client, plan);
    stdout.writeln(
      'Wrote ${plan.writes.length} documents to users/{uid}/events.',
    );
    await _verify(client, plan);
  } finally {
    client.close();
  }
}

void _printPlan(_BackfillCommand command, PersonBackfillPlan plan) {
  stdout.writeln(
    command.apply
        ? 'Person event backfill: apply'
        : 'Person event backfill: dry-run',
  );
  stdout.writeln('writes: ${plan.writes.length}');
  stdout.writeln('skipped joint/shared: ${plan.skippedJoint.length}');
  stdout.writeln('skipped (no owner): ${plan.skippedNoOwner.length}');
  final counts = plan.countsByOwner.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in counts) {
    stdout.writeln('  users/${entry.key}/events: ${entry.value}');
  }
  final conflicts = plan.writes.where((w) => w.losers.isNotEmpty).toList();
  stdout.writeln('conflicts resolved: ${conflicts.length}');
  for (final write in conflicts.take(20)) {
    stdout.writeln(
      '  ${write.eventId}  ${write.reason}  from ${write.fromHubId}  '
      'status=${write.fields['status']}  '
      'beat ${write.losers.map((l) => l.hubId).join(',')}',
    );
  }

  const driftedC2 = [
    'c2-rota:2026-11-18',
    'c2-rota:2026-11-19',
    'c2-rota:2026-11-23',
    'c2-rota:2026-11-24',
    'c2-rota:2026-11-29',
    'c2-rota:2026-12-01',
    'c2-rota:2026-12-06',
  ];
  stdout.writeln(
    'c2-rota writes: ${plan.writes.where((w) => w.eventId.startsWith('c2-rota:')).length}',
  );
  stdout.writeln(
    'spot-check drifted c2-rota (Burroni should win as confirmed):',
  );
  for (final id in driftedC2) {
    PersonBackfillSelection? write;
    for (final candidate in plan.writes) {
      if (candidate.eventId == id) {
        write = candidate;
        break;
      }
    }
    if (write == null) {
      stdout.writeln('  $id: MISSING from plan');
    } else {
      stdout.writeln(
        '  $id  status=${write.fields['status']}  '
        'from ${write.fromHubId}  ${write.reason}  '
        'summary=${write.fields['summary']}',
      );
    }
  }

  PersonBackfillSelection? electric;
  for (final write in plan.writes) {
    if (write.eventId == 'c2-rota:2026-12-06') {
      electric = write;
      break;
    }
  }
  if (electric != null) {
    stdout.writeln(
      'spot-check 6 Dec Electric Six: users/${electric.ownerUid}/events/${electric.eventId} '
      'status=${electric.fields['status']} from ${electric.fromHubId} (${electric.reason})',
    );
  } else {
    stdout.writeln('spot-check 6 Dec Electric Six: NOT in person-store plan');
  }

  final dateDay = plan.skippedJoint.where(
    (c) => c.eventId == 'renoir:2026-11-28-date-day',
  );
  if (dateDay.isNotEmpty) {
    stdout.writeln(
      'spot-check 28 Nov Date day: skipped as hub-shared in '
      '${dateDay.map((c) => c.hubId).join(', ')} (not copied to a person store, not in Paddy)',
    );
  } else {
    stdout.writeln('spot-check 28 Nov Date day: not found in joint skip list');
  }
}

Future<void> _commitWrites(http.Client client, PersonBackfillPlan plan) async {
  const maxBatch = 400;
  final writes = [for (final item in plan.writes) _writeFor(item)];
  for (var i = 0; i < writes.length; i += maxBatch) {
    final end = i + maxBatch > writes.length ? writes.length : i + maxBatch;
    await _commit(client, writes.sublist(i, end));
  }
}

Map<String, dynamic> _writeFor(PersonBackfillSelection item) {
  final fields = <String, dynamic>{};
  for (final entry in item.fields.entries) {
    if (entry.value == null) continue;
    fields[entry.key] = firestoreRestValue(entry.value);
  }
  final name = firestoreEventDocumentName(
    projectId: lovehubFirebaseProjectId,
    eventId: item.eventId,
    personStoreUserId: item.ownerUid,
  );
  return {
    'update': {'name': name, 'fields': fields},
    'updateMask': {'fieldPaths': fields.keys.toList()},
  };
}

Future<void> _verify(http.Client client, PersonBackfillPlan plan) async {
  const driftedC2 = [
    'c2-rota:2026-11-18',
    'c2-rota:2026-11-19',
    'c2-rota:2026-11-23',
    'c2-rota:2026-11-24',
    'c2-rota:2026-11-29',
    'c2-rota:2026-12-01',
    'c2-rota:2026-12-06',
  ];
  for (final id in driftedC2) {
    PersonBackfillSelection? item;
    for (final write in plan.writes) {
      if (write.eventId == id) {
        item = write;
        break;
      }
    }
    if (item == null) {
      stdout.writeln('verify $id: MISSING from plan');
      continue;
    }
    final path =
        'users/${Uri.encodeComponent(item.ownerUid)}/events/${Uri.encodeComponent(item.eventId)}';
    final doc = await _getDocument(client, path);
    if (doc == null) {
      stdout.writeln('verify $id: MISSING after write');
      continue;
    }
    final fields = firestoreRestFields(
      Map<String, dynamic>.from(doc['fields'] as Map? ?? {}),
    );
    stdout.writeln(
      'verify $id: status=${fields['status']} summary=${fields['summary']}',
    );
  }
  final owners = plan.countsByOwner.keys;
  var copiedDateDay = false;
  for (final owner in owners) {
    final doc = await _getDocument(
      client,
      'users/${Uri.encodeComponent(owner)}/events/renoir:2026-11-28-date-day',
    );
    if (doc != null) copiedDateDay = true;
  }
  stdout.writeln(
    copiedDateDay
        ? 'verify Date day: unexpectedly present in a person store'
        : 'verify Date day: not in any backfilled person store',
  );
}

Future<AutoRefreshingAuthClient> _firestoreClient() async {
  try {
    return await clientViaApplicationDefaultCredentials(
      scopes: const [c2RotaFirestoreScope],
    );
  } catch (_) {
    throw C2RotaAuthException(c2RotaAdcUnavailableMessage(null));
  }
}

Map<String, String> _firestoreHeaders({bool json = false}) {
  return {
    if (json) 'Content-Type': 'application/json',
    'x-goog-user-project': lovehubFirebaseProjectId,
  };
}

void _refuse(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    throw C2RotaAuthException(
      c2RotaAdcUnavailableMessage(
        'Cloud Firestore refused the Application Default Credential ($statusCode).',
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> _listDocuments(
  http.Client client,
  String path,
) async {
  final items = <Map<String, dynamic>>[];
  String? pageToken;
  var pages = 0;
  while (true) {
    pages += 1;
    if (pages > 50) {
      throw ArgumentError('Stopped after too many Firestore pages for $path.');
    }
    final uri =
        Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
          '/databases/(default)/documents/$path',
        ).replace(
          queryParameters: {
            'pageSize': '300',
            if (pageToken != null) 'pageToken': pageToken,
          },
        );
    final response = await client.get(uri, headers: _firestoreHeaders());
    if (response.statusCode == 404) return items;
    _refuse(response.statusCode);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ArgumentError('Could not list $path (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['documents'] is List) {
      for (final row in decoded['documents'] as List) {
        if (row is Map) items.add(Map<String, dynamic>.from(row));
      }
    }
    if (decoded is! Map) break;
    final next = decoded['nextPageToken'];
    if (next is! String || next.isEmpty) break;
    pageToken = next;
  }
  return items;
}

Future<Map<String, dynamic>?> _getDocument(
  http.Client client,
  String path,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents/$path',
  );
  final response = await client.get(uri, headers: _firestoreHeaders());
  if (response.statusCode == 404) return null;
  _refuse(response.statusCode);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ArgumentError('Could not read $path (${response.statusCode}).');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) return null;
  return Map<String, dynamic>.from(decoded);
}

Future<void> _commit(
  http.Client client,
  List<Map<String, dynamic>> writes,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$lovehubFirebaseProjectId'
    '/databases/(default)/documents:commit',
  );
  final response = await client.post(
    uri,
    headers: _firestoreHeaders(json: true),
    body: jsonEncode({'writes': writes}),
  );
  _refuse(response.statusCode);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ArgumentError('Firestore commit failed (${response.statusCode}).');
  }
}
