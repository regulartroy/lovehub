// Read-only export of a LoveHub hub schedule to a shared folder.
//
//   dart run tool/export_schedule.dart --hub <hubId>
//   dart run tool/export_schedule.dart --hub <hubId> --out-dir /home/box/shared/lovehub --days 56
//
// Reads Firestore through Application Default Credentials via
// package:googleapis_auth. Never writes to Firestore. Never prints tokens.
// The Firebase CLI credential cache is not read.
//
// One-time setup, same as tool/reconcile_c2_rota.dart:
//   gcloud auth application-default login
//   gcloud auth application-default set-quota-project lovehub-26107

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/event_import/schedule_export.dart';

const _usage = '''
Export a read-only LoveHub schedule snapshot for other household bots.

  dart run tool/export_schedule.dart --hub <hubId>
  dart run tool/export_schedule.dart --hub <hubId> --out-dir /home/box/shared/lovehub --days 56

HUB_ID can replace --hub. Default out-dir is /home/box/shared/lovehub.
Default window is today through today+56 days, Europe/London.

Writes schedule.json, schedule.ics, and README.md atomically (temp file,
then rename). This tool only reads Firestore. It has no write or --apply
flag.

Firestore uses Application Default Credentials (googleapis_auth). One-time:
  gcloud auth application-default login
  gcloud auth application-default set-quota-project lovehub-26107
Do not create a service-account key.
''';

Future<void> main(List<String> args) async {
  try {
    final command = parseScheduleExportArgs(
      args,
      environment: Platform.environment,
    );
    if (command.help) {
      stdout.writeln(_usage.trim());
      return;
    }
    await _export(command);
  } on ScheduleExportArgsException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on ScheduleExportException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on C2RotaAuthException catch (error) {
    stderr.writeln(error.message);
    exitCode = 4;
  } on FormatException {
    stderr.writeln('Invalid JSON from Firestore.');
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln('Firestore request timed out.');
    exitCode = 1;
  } on SocketException {
    stderr.writeln('Could not reach Firestore.');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('Could not write ${error.path ?? 'the export files'}.');
    exitCode = 1;
  }
}

Future<void> _export(ScheduleExportCommand command) async {
  final hubId = command.hubId!;
  final now = command.now ?? DateTime.now().toUtc();
  final window = scheduleExportWindow(now, days: command.days);
  final client = await _firestoreClient();
  try {
    final hub = await _getDocument(
      client,
      'hubs/${Uri.encodeComponent(hubId)}',
    );
    if (hub == null) {
      throw ScheduleExportException('Hub $hubId was not found.');
    }
    final namesByUid = namesByUidFromHubDocument(hub);
    final events = await _listCollection(
      client,
      'hubs/${Uri.encodeComponent(hubId)}/events',
      storedEventsFromRestList,
    );
    final birthdays = await _listCollection(
      client,
      'hubs/${Uri.encodeComponent(hubId)}/birthdays',
      storedBirthdaysFromRestList,
    );
    final snapshot = buildScheduleSnapshot(
      generatedAt: DateTime.now().toUtc(),
      window: window,
      events: events,
      birthdays: birthdays,
      namesByUid: namesByUid,
      hubId: hubId,
    );
    final jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(snapshot.toJson());
    final icsText = renderScheduleIcs(snapshot);
    final readme = scheduleExportReadme(
      outDir: command.outDir,
      commandHint:
          'tool/export_schedule.sh --hub $hubId --out-dir ${command.outDir}',
    );
    writeScheduleExportFiles(
      outDir: command.outDir,
      jsonText: jsonText,
      icsText: icsText,
      readmeText: readme,
    );
    stdout.writeln(
      'Exported ${snapshot.events.length} events '
      '${snapshot.windowStart.ymd} .. ${snapshot.windowEnd.ymd} '
      'to ${command.outDir}',
    );
  } finally {
    client.close();
  }
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

void _refuseFirestoreStatus(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    throw C2RotaAuthException(
      c2RotaAdcUnavailableMessage(
        'Cloud Firestore refused the Application Default Credential ($statusCode).',
      ),
    );
  }
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
  _refuseFirestoreStatus(response.statusCode);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ScheduleExportException(
      'Could not read $path (${response.statusCode}).',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    throw ScheduleExportException('Unexpected Firestore response for $path.');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<List<T>> _listCollection<T>(
  http.Client client,
  String path,
  List<T> Function(Object? decoded) parse,
) async {
  final items = <T>[];
  String? pageToken;
  var pages = 0;
  while (true) {
    pages += 1;
    if (pages > 50) {
      throw ScheduleExportException(
        'Stopped after too many Firestore pages for $path.',
      );
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
    _refuseFirestoreStatus(response.statusCode);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ScheduleExportException(
        'Could not list $path (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    items.addAll(parse(decoded));
    if (items.length > scheduleExportMaxDocuments) {
      throw ScheduleExportException(
        'Refusing to export more than $scheduleExportMaxDocuments documents from $path.',
      );
    }
    if (decoded is! Map) break;
    final next = decoded['nextPageToken'];
    if (next is! String || next.isEmpty) break;
    pageToken = next;
  }
  return items;
}

void writeScheduleExportFiles({
  required String outDir,
  required String jsonText,
  required String icsText,
  required String readmeText,
}) {
  final dir = Directory(outDir);
  dir.createSync(recursive: true);
  writeFileAtomically(File('${dir.path}/schedule.json'), jsonText);
  writeFileAtomically(File('${dir.path}/schedule.ics'), icsText);
  writeFileAtomically(File('${dir.path}/README.md'), readmeText);
  makeExportReadable(dir);
}

void writeFileAtomically(File file, String contents) {
  file.parent.createSync(recursive: true);
  final tmp = File(
    '${file.path}.tmp.$pid.${DateTime.now().toUtc().microsecondsSinceEpoch}',
  );
  try {
    tmp.writeAsStringSync(contents);
    tmp.renameSync(file.path);
  } catch (_) {
    if (tmp.existsSync()) {
      tmp.deleteSync();
    }
    rethrow;
  }
}

void makeExportReadable(Directory dir) {
  Process.runSync('chmod', ['a+rX', dir.path]);
  for (final name in ['schedule.json', 'schedule.ics', 'README.md']) {
    final file = File('${dir.path}/$name');
    if (file.existsSync()) {
      Process.runSync('chmod', ['a+r', file.path]);
    }
  }
}
