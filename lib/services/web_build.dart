/// Firebase project that hosts LoveHub (`love-hub` Hosting target).
const kLovehubFirebaseProjectId = 'lovehub-26107';

/// Compile-time id of this web build.
///
/// Release deploys pass it with `--dart-define=BUILD_ID=...` (see
/// `tool/deploy_hosting.sh`). An empty value means a dev session
/// (`flutter run`) and the update check stays quiet.
const kWebBuildId = String.fromEnvironment('BUILD_ID');

/// Firestore document the deploy script updates after Hosting goes out.
///
/// Signed-in users may read it. Clients must not write it.
const kWebBuildStampPath = 'appMeta/web';

const kWebBuildIdField = 'buildId';
const kWebBuildUpdatedAtField = 'updatedAt';

/// How often an open browser re-reads [kWebBuildStampPath] if the snapshot
/// listener has gone quiet. Wall tablets stay on this cadence.
const kWebUpdateCheckInterval = Duration(minutes: 10);

/// `buildId` from an `appMeta/web` snapshot, or null when it is missing.
String? buildIdFromFields(Map<String, dynamic>? data) {
  if (data == null) return null;
  final raw = data[kWebBuildIdField];
  if (raw is! String) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}
