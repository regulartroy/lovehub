// Writes the web BUILD_ID to Firestore `appMeta/web` after a Hosting deploy.
//
// Use the same id that was baked into the Flutter build:
//
//   flutter build web --release --dart-define=BUILD_ID="$BUILD_ID"
//   firebase deploy --only hosting:love-hub,firestore:rules --project lovehub-26107
//   dart run tool/stamp_web_build.dart --build-id "$BUILD_ID"
//
// `tool/deploy_hosting.sh` does those three steps in order. Stamp after
// Hosting is live so an open tablet reloads onto the new files.
//
// Auth (never commit these):
//   GOOGLE_ACCESS_TOKEN     Google OAuth access token with Firestore IAM access
//   FIREBASE_TOKEN          refresh token from `firebase login:ci`
//   firebase login          otherwise the CLI configstore refresh token is used
//   gcloud                  `gcloud auth print-access-token` is the last resort
//
// A Firebase Auth ID token cannot write this doc. Security rules deny client
// writes; CLI / IAM credentials bypass rules.
//
// The OAuth client id below is the public Firebase CLI installed-app client
// (firebase-tools src/api.ts). It is not a LoveHub secret. Override with
// FIREBASE_CLIENT_ID and FIREBASE_CLIENT_SECRET if you need to.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lovehub/services/web_build.dart';
import 'package:lovehub/services/web_build_stamp.dart';

const _usage = '''
Stamp Firestore appMeta/web with the web BUILD_ID just deployed.

  dart run tool/stamp_web_build.dart --build-id <id>
  BUILD_ID=<id> dart run tool/stamp_web_build.dart
  dart run tool/stamp_web_build.dart --build-id <id> --dry-run

Pass the same id to:
  flutter build web --release --dart-define=BUILD_ID=<id>

Credentials: GOOGLE_ACCESS_TOKEN, FIREBASE_TOKEN (`firebase login:ci`),
an existing `firebase login`, or gcloud. Do not commit tokens.
''';

/// Public Firebase CLI OAuth client. Not a project secret.
const _defaultCliClientId =
    '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const _defaultCliClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';

Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    final command = parseWebBuildStampArgs(
      args,
      buildIdFromEnvironment: Platform.environment['BUILD_ID'],
    );
    if (command.help) {
      stdout.writeln(_usage.trim());
      return;
    }
    final updatedAt = DateTime.now().toUtc();
    final write = webBuildStampCommitWrite(
      projectId: kLovehubFirebaseProjectId,
      buildId: command.buildId,
      updatedAt: updatedAt,
    );
    if (command.dryRun) {
      stdout.writeln(
        'Dry run: would set $kWebBuildStampPath '
        'buildId=${command.buildId} '
        'updatedAt=${firestoreTimestamp(updatedAt)}',
      );
      return;
    }
    final token = await _resolveAccessToken(client);
    await _commit(client, token, write);
    stdout.writeln('Stamped $kWebBuildStampPath buildId=${command.buildId}');
  } on WebBuildStampArgsException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage.trim());
    exitCode = 1;
  } on _StampException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } finally {
    client.close();
  }
}

Future<String> _resolveAccessToken(http.Client client) async {
  final direct = Platform.environment['GOOGLE_ACCESS_TOKEN']?.trim();
  if (direct != null && direct.isNotEmpty) return direct;

  final firebaseToken = Platform.environment['FIREBASE_TOKEN']?.trim();
  if (firebaseToken != null && firebaseToken.isNotEmpty) {
    return _exchangeRefreshToken(client, firebaseToken);
  }

  final stored = _readCliConfig();
  if (stored != null) {
    final cached = usableFirebaseCliAccessToken(stored, now: DateTime.now());
    if (cached != null) return cached;
    final refresh = stored.refreshToken;
    if (refresh != null) return _exchangeRefreshToken(client, refresh);
  }

  final gcloud = await _gcloudAccessToken();
  if (gcloud != null) return gcloud;

  throw _StampException(
    'No Google credential found. Run `firebase login`, or set '
    'GOOGLE_ACCESS_TOKEN / FIREBASE_TOKEN. Do not commit either value. '
    'A Firebase Auth user token cannot write $kWebBuildStampPath.',
  );
}

FirebaseCliTokens? _readCliConfig() {
  for (final file in _cliConfigFiles()) {
    if (!file.existsSync()) continue;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw _StampException('Could not read ${file.path}.');
    }
    return parseFirebaseCliConfig(Map<String, dynamic>.from(decoded));
  }
  return null;
}

List<File> _cliConfigFiles() {
  final paths = <String>[];
  void add(String path) {
    if (!paths.contains(path)) paths.add(path);
  }

  final xdg = Platform.environment['XDG_CONFIG_HOME']?.trim();
  if (xdg != null && xdg.isNotEmpty) {
    add('$xdg/configstore/firebase-tools.json');
  }
  final home = Platform.environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    add('$home/.config/configstore/firebase-tools.json');
  }
  final profile = Platform.environment['USERPROFILE']?.trim();
  if (profile != null && profile.isNotEmpty) {
    add('$profile/.config/configstore/firebase-tools.json');
  }
  final appData = Platform.environment['APPDATA']?.trim();
  if (appData != null && appData.isNotEmpty) {
    add('$appData/configstore/firebase-tools.json');
  }
  return [for (final path in paths) File(path)];
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
  final clientId =
      Platform.environment['FIREBASE_CLIENT_ID']?.trim().isNotEmpty == true
      ? Platform.environment['FIREBASE_CLIENT_ID']!.trim()
      : _defaultCliClientId;
  final clientSecret =
      Platform.environment['FIREBASE_CLIENT_SECRET']?.trim().isNotEmpty == true
      ? Platform.environment['FIREBASE_CLIENT_SECRET']!.trim()
      : _defaultCliClientSecret;
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
    throw _StampException(
      'Could not refresh the Firebase CLI credential '
      '(${response.statusCode}). Run `firebase login` again.',
    );
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map || decoded['access_token'] is! String) {
    throw _StampException('Token refresh did not return an access token.');
  }
  return decoded['access_token'] as String;
}

Future<void> _commit(
  http.Client client,
  String accessToken,
  Map<String, dynamic> write,
) async {
  final uri = Uri.parse(
    'https://firestore.googleapis.com/v1/projects/$kLovehubFirebaseProjectId'
    '/databases/(default)/documents:commit',
  );
  final response = await client.post(
    uri,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'writes': [write],
    }),
  );
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  final detail = response.body.length > 400
      ? response.body.substring(0, 400)
      : response.body;
  throw _StampException(
    'Could not write $kWebBuildStampPath (${response.statusCode}). '
    'The Google account needs Firestore write access on '
    '$kLovehubFirebaseProjectId. $detail',
  );
}

class _StampException implements Exception {
  _StampException(this.message);

  final String message;

  @override
  String toString() => message;
}
