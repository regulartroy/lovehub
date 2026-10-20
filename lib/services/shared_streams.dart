import 'dart:async';

/// Memoized, shared streams for a screen.
///
/// `query.snapshots()` returns a new stream on every call, and a
/// [StreamBuilder] that gets a new stream instance resubscribes. A fresh
/// Firestore listen re-reads every matching doc, so building streams inside
/// `build()` (which reruns on each minute tick) re-read whole collections.
///
/// [watch] creates the source once per key and keeps one underlying
/// subscription; every listener shares it and immediately gets the latest
/// value. Call [dispose] from the owning State.
class SharedStreams {
  /// Total underlying `listen` calls across all caches (debug/tests).
  static int debugSourceListens = 0;

  final Map<String, _Shared<dynamic>> _entries = {};

  /// Number of live underlying subscriptions in this cache.
  int get activeSources => _entries.values.where((e) => e.sub != null).length;

  Stream<T> watch<T>(String key, Stream<T> Function() create) {
    final existing = _entries[key];
    if (existing != null) return existing.stream as Stream<T>;
    final entry = _Shared<T>(create);
    _entries[key] = entry;
    return entry.stream;
  }

  /// Drops (and cancels) entries whose key starts with [prefix] but is not
  /// [keep], e.g. yesterday's week-log stream after rollover.
  void evictPrefix(String prefix, {String? keep}) {
    final stale = _entries.keys
        .where((k) => k.startsWith(prefix) && k != keep)
        .toList();
    for (final k in stale) {
      _entries.remove(k)?.close();
    }
  }

  void dispose() {
    for (final e in _entries.values) {
      e.close();
    }
    _entries.clear();
  }
}

class _Shared<T> {
  _Shared(this._create) {
    stream = Stream<T>.multi((c) {
      if (_has) c.add(_last as T);
      _listeners.add(c);
      sub ??= _listen();
      c.onCancel = () => _listeners.remove(c);
    }, isBroadcast: true);
  }

  final Stream<T> Function() _create;
  late final Stream<T> stream;
  final Set<MultiStreamController<T>> _listeners = {};
  StreamSubscription<T>? sub;
  T? _last;
  bool _has = false;

  StreamSubscription<T> _listen() {
    SharedStreams.debugSourceListens++;
    return _create().listen(
      (v) {
        _last = v;
        _has = true;
        for (final l in _listeners.toList()) {
          l.add(v);
        }
      },
      onError: (Object e, StackTrace s) {
        for (final l in _listeners.toList()) {
          l.addError(e, s);
        }
      },
    );
  }

  void close() {
    sub?.cancel();
    sub = null;
    for (final l in _listeners.toList()) {
      l.close();
    }
    _listeners.clear();
  }
}
