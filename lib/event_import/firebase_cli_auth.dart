import '../services/web_build_stamp.dart';

/// Public OAuth client shipped in `firebase-tools` (`src/api.ts`).
///
/// This is the installed-app client the Firebase CLI already uses. It is not
/// a LoveHub secret. Override with `FIREBASE_CLIENT_ID` and
/// `FIREBASE_CLIENT_SECRET` when exchanging a refresh token.
const firebaseToolsOauthClientId =
    '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const firebaseToolsOauthClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';

class FirebaseCliAuthException implements Exception {
  FirebaseCliAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Configstore files `firebase login` writes, in the same order as
/// `tool/stamp_web_build.dart`.
List<String> firebaseCliConfigCandidates(Map<String, String> environment) {
  final paths = <String>[];
  void add(String path) {
    if (!paths.contains(path)) paths.add(path);
  }

  final xdg = environment['XDG_CONFIG_HOME']?.trim();
  if (xdg != null && xdg.isNotEmpty) {
    add('$xdg/configstore/firebase-tools.json');
  }
  final home = environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    add('$home/.config/configstore/firebase-tools.json');
  }
  final profile = environment['USERPROFILE']?.trim();
  if (profile != null && profile.isNotEmpty) {
    add('$profile/.config/configstore/firebase-tools.json');
  }
  final appData = environment['APPDATA']?.trim();
  if (appData != null && appData.isNotEmpty) {
    add('$appData/configstore/firebase-tools.json');
  }
  return paths;
}

/// Google access token for Firestore IAM calls.
///
/// Order matches the web-build stamp: `GOOGLE_ACCESS_TOKEN`, then
/// `FIREBASE_TOKEN` (`firebase login:ci`), then the cached `firebase login`
/// token, then that login's refresh token, then `gcloud auth print-access-token`.
/// The thrown message never includes a token.
Future<String> selectFirebaseCliAccessToken({
  required Map<String, String> environment,
  required DateTime now,
  required FirebaseCliTokens? storedTokens,
  required Future<String?> Function() readGcloudAccessToken,
  required Future<String> Function(String refreshToken) exchangeRefreshToken,
}) async {
  final direct = _trimmed(environment['GOOGLE_ACCESS_TOKEN']);
  if (direct != null) return direct;

  final firebaseToken = _trimmed(environment['FIREBASE_TOKEN']);
  if (firebaseToken != null) return exchangeRefreshToken(firebaseToken);

  if (storedTokens != null) {
    final cached = usableFirebaseCliAccessToken(storedTokens, now: now);
    if (cached != null) return cached;
    final refresh = storedTokens.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      return exchangeRefreshToken(refresh);
    }
  }

  final gcloud = await readGcloudAccessToken();
  if (gcloud != null) {
    final token = gcloud.trim();
    if (token.isNotEmpty && !token.contains('\n')) return token;
  }

  throw FirebaseCliAuthException(
    'No Google credential found. Run `firebase login` as the user that '
    'will run this job, or set GOOGLE_ACCESS_TOKEN / FIREBASE_TOKEN. '
    'Do not commit either value. A service-account JSON file is not used.',
  );
}

String? _trimmed(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  return value.isEmpty ? null : value;
}
