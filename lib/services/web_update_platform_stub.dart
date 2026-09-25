import 'dart:async';

import 'web_update_policy.dart';

/// Native and VM builds never persist reload attempts or reload a page.
/// The update host is disabled off web; this exists so the import resolves.
class SessionWebUpdateAttemptStore extends WebUpdateAttemptStore {
  const SessionWebUpdateAttemptStore();

  static final Set<String> _memory = <String>{};

  @override
  Set<String> read() => Set<String>.from(_memory);

  @override
  void remember(String buildId) {
    final id = buildId.trim();
    if (id.isEmpty) return;
    _memory.add(id);
  }
}

void reloadWebPage() {}

Stream<void> webWindowFocusEvents() => const Stream<void>.empty();
