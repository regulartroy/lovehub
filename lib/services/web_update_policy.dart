/// What an open browser should do when the hosted build id changes.
enum WebUpdateAction {
  /// Remote id matches, or there is nothing safe to act on.
  none,

  /// Show the non-blocking "Update ready" chip. Reload only if tapped.
  prompt,

  /// Wall-tablet / large layout: reload once, with no prompt.
  reload,
}

class WebUpdateDecision {
  const WebUpdateDecision({required this.action, this.remoteBuildId = ''});

  final WebUpdateAction action;
  final String remoteBuildId;
}

/// Remembers remote ids this browser already tried to load.
///
/// A bad stamp must not reload forever. Session storage is the web
/// implementation; tests use [MemoryWebUpdateAttemptStore].
abstract class WebUpdateAttemptStore {
  const WebUpdateAttemptStore();

  Set<String> read();

  void remember(String buildId);
}

class MemoryWebUpdateAttemptStore extends WebUpdateAttemptStore {
  final Set<String> _ids = <String>{};

  @override
  Set<String> read() => Set<String>.from(_ids);

  @override
  void remember(String buildId) {
    final id = buildId.trim();
    if (id.isEmpty) return;
    _ids.add(id);
  }
}

/// Decides whether a newer Hosting build should prompt or reload.
///
/// [isCompactLayout] is the dashboard phone split (width under 700): phones
/// are compact, the wall tablet is not. A create/edit sheet or other popup
/// forces a prompt even on a tablet so an in-progress edit is not wiped.
///
/// Empty or missing remote ids never reload. An empty local id is a dev
/// build that was not passed `--dart-define=BUILD_ID`, and it stays quiet.
/// An id already present in [alreadyAttemptedIds] is not auto-reloaded again.
WebUpdateDecision decideWebUpdate({
  required String localBuildId,
  required String? remoteBuildId,
  required bool isCompactLayout,
  required bool sheetOrModalOpen,
  required Set<String> alreadyAttemptedIds,
}) {
  final remote = remoteBuildId?.trim() ?? '';
  if (remote.isEmpty) {
    return const WebUpdateDecision(action: WebUpdateAction.none);
  }
  final local = localBuildId.trim();
  if (local.isEmpty || local == remote) {
    return const WebUpdateDecision(action: WebUpdateAction.none);
  }
  if (isCompactLayout ||
      sheetOrModalOpen ||
      alreadyAttemptedIds.contains(remote)) {
    return WebUpdateDecision(
      action: WebUpdateAction.prompt,
      remoteBuildId: remote,
    );
  }
  return WebUpdateDecision(
    action: WebUpdateAction.reload,
    remoteBuildId: remote,
  );
}
