import 'dart:async';
import 'dart:js_interop';

import 'web_update_policy.dart';

/// Survives `location.reload()` for this tab, and is cleared when the tab closes.
/// One entry per remote build id stops a bad stamp from reloading forever.
const _attemptKey = 'lovehub.webUpdate.attemptedBuildIds';

@JS('sessionStorage')
external _WebStorage get _sessionStorage;

@JS('location')
external _WebLocation get _location;

@JS('window')
external _WebWindow get _window;

extension type _WebStorage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

extension type _WebLocation._(JSObject _) implements JSObject {
  external void reload();
}

extension type _WebWindow._(JSObject _) implements JSObject {
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

class SessionWebUpdateAttemptStore extends WebUpdateAttemptStore {
  const SessionWebUpdateAttemptStore();

  @override
  Set<String> read() {
    try {
      return _readIds();
    } catch (_) {
      // Private mode can throw. Missing the guard is safer than crashing.
      return <String>{};
    }
  }

  @override
  void remember(String buildId) {
    final id = buildId.trim();
    if (id.isEmpty || id.contains('\n')) return;
    try {
      final ids = _readIds()..add(id);
      _sessionStorage.setItem(_attemptKey, ids.join('\n'));
    } catch (_) {
      // Same as read: keep the in-memory guard even if storage is blocked.
    }
  }
}

Set<String> _readIds() {
  final raw = _sessionStorage.getItem(_attemptKey);
  if (raw == null || raw.isEmpty) return <String>{};
  return raw
      .split('\n')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
}

void reloadWebPage() {
  try {
    _location.reload();
  } catch (_) {
    // The host still records the attempt, so this id is not retried in a loop.
  }
}

/// Fires when the browser window regains focus. Tab visibility is also
/// covered by Flutter's [AppLifecycleState.resumed] on web.
Stream<void> webWindowFocusEvents() {
  late final StreamController<void> controller;
  JSFunction? listener;
  controller = StreamController<void>.broadcast(
    onListen: () {
      if (listener != null) return;
      listener = ((JSAny? _) {
        if (!controller.isClosed) controller.add(null);
      }).toJS;
      _window.addEventListener('focus', listener!);
    },
    onCancel: () {
      final current = listener;
      if (current == null) return;
      _window.removeEventListener('focus', current);
      listener = null;
    },
  );
  return controller.stream;
}
