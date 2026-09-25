import 'web_build.dart';

/// Args for `tool/stamp_web_build.dart`.
class WebBuildStampCommand {
  const WebBuildStampCommand({
    required this.buildId,
    required this.dryRun,
    required this.help,
  });

  final String buildId;
  final bool dryRun;
  final bool help;
}

class WebBuildStampArgsException implements Exception {
  WebBuildStampArgsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `--build-id` wins over [buildIdFromEnvironment] (`BUILD_ID`).
WebBuildStampCommand parseWebBuildStampArgs(
  List<String> args, {
  String? buildIdFromEnvironment,
}) {
  var dryRun = false;
  var help = false;
  String? buildId;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      help = true;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--build-id') {
      if (i + 1 >= args.length) {
        throw WebBuildStampArgsException('Missing value for --build-id.');
      }
      buildId = args[++i];
    } else if (arg.startsWith('--build-id=')) {
      buildId = arg.substring('--build-id='.length);
    } else {
      throw WebBuildStampArgsException('Unknown argument: $arg');
    }
  }
  final resolved = (buildId ?? buildIdFromEnvironment ?? '').trim();
  if (!help && resolved.isEmpty) {
    throw WebBuildStampArgsException(
      'Pass --build-id or set BUILD_ID to the same value passed to '
      'flutter build web --dart-define=BUILD_ID=... .',
    );
  }
  return WebBuildStampCommand(buildId: resolved, dryRun: dryRun, help: help);
}

/// Tokens stored by `firebase login` in configstore `firebase-tools.json`.
class FirebaseCliTokens {
  const FirebaseCliTokens({
    this.accessToken,
    this.refreshToken,
    this.expiresAtMs,
  });

  final String? accessToken;
  final String? refreshToken;

  /// Epoch milliseconds from `tokens.expires_at`.
  final int? expiresAtMs;
}

FirebaseCliTokens parseFirebaseCliConfig(Map<String, dynamic> json) {
  final tokens = json['tokens'];
  if (tokens is! Map) return const FirebaseCliTokens();
  return FirebaseCliTokens(
    accessToken: _nonEmpty(tokens['access_token']),
    refreshToken: _nonEmpty(tokens['refresh_token']),
    expiresAtMs: _epochMs(tokens['expires_at']),
  );
}

/// Access token still valid for at least a minute, otherwise null.
String? usableFirebaseCliAccessToken(
  FirebaseCliTokens tokens, {
  required DateTime now,
}) {
  final access = tokens.accessToken;
  final expiresAtMs = tokens.expiresAtMs;
  if (access == null || expiresAtMs == null) return null;
  final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAtMs, isUtc: true);
  if (!expiry.isAfter(now.toUtc().add(const Duration(seconds: 60)))) {
    return null;
  }
  return access;
}

/// One Firestore `commit` write for `appMeta/web`.
///
/// Call this with a Google OAuth access token (Firebase CLI / gcloud / IAM).
/// Security rules deny client SDK writes; Admin and IAM credentials bypass them.
Map<String, dynamic> webBuildStampCommitWrite({
  required String projectId,
  required String buildId,
  required DateTime updatedAt,
}) {
  final id = buildId.trim();
  if (id.isEmpty) {
    throw ArgumentError('BUILD_ID is empty.');
  }
  if (id.contains('/') || id.contains('\n')) {
    throw ArgumentError('BUILD_ID must be a single path segment.');
  }
  return {
    'update': {
      'name':
          'projects/$projectId/databases/(default)/documents/$kWebBuildStampPath',
      'fields': {
        kWebBuildIdField: {'stringValue': id},
        kWebBuildUpdatedAtField: {
          'timestampValue': firestoreTimestamp(updatedAt),
        },
      },
    },
    'updateMask': {
      'fieldPaths': [kWebBuildIdField, kWebBuildUpdatedAtField],
    },
  };
}

/// Firestore REST `timestampValue` (UTC, millisecond precision).
String firestoreTimestamp(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.'
      '${ms}Z';
}

String? _nonEmpty(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

int? _epochMs(Object? raw) {
  if (raw is! num) return null;
  final value = raw.toInt();
  // firebase-tools stores epoch milliseconds. Treat smaller values as seconds.
  if (value > 0 && value < 1000000000000) return value * 1000;
  return value;
}
