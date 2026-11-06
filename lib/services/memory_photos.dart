import 'dart:math';

/// One gallery photo the wall dashboard can show.
///
/// [url] is what the image widget loads. [serverUrl] is the Firestore value,
/// kept so an in-memory download-URL refresh is not thrown away when the
/// photos listener delivers the same document again. Nothing here writes
/// Firestore or sends the bytes through another host.
class MemoryPhoto {
  const MemoryPhoto({
    required this.id,
    required this.url,
    this.storagePath,
    String? serverUrl,
  }) : serverUrl = serverUrl ?? url;

  final String id;
  final String url;
  final String serverUrl;
  final String? storagePath;
}

/// Firestore `hubs/{hub}/photos` rows, without a Firestore import.
typedef MemoryPhotoDoc = ({String id, Map<String, dynamic> data});

/// Storage paths this app uploads. Anything else is not refreshed.
String? canonicalHubPhotoStoragePath(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty || value.contains('\\') || value.contains('://')) {
    return null;
  }
  if (value.startsWith('/')) return null;
  final segments = value.split('/');
  if (segments.length != 4) return null;
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return null;
  }
  if (segments[0] != 'hubs' || segments[2] != 'photos') return null;
  return value;
}

/// Reads the fields the dashboard actually stores. Empty and non-string URLs
/// are skipped. [storagePath] is kept only when it is a string; the deck
/// drops paths that are not a hub photo object before any Storage read.
List<MemoryPhoto> memoryPhotosFromDocs(Iterable<MemoryPhotoDoc> docs) {
  final photos = <MemoryPhoto>[];
  for (final doc in docs) {
    final rawUrl = doc.data['url'];
    if (rawUrl is! String) continue;
    final url = rawUrl.trim();
    if (url.isEmpty) continue;
    final rawPath = doc.data['storagePath'];
    photos.add(
      MemoryPhoto(
        id: doc.id,
        url: url,
        storagePath: rawPath is String ? rawPath : null,
      ),
    );
  }
  return photos;
}

/// What the dashboard should do after a memory photo fails to paint.
sealed class MemoryPhotoStep {
  const MemoryPhotoStep();
}

/// Duplicate or stale error. Do not rebuild and do not read Storage.
class MemoryPhotoIgnore extends MemoryPhotoStep {
  const MemoryPhotoIgnore();
}

/// Show [url] once. The caller rebuilds a single image widget.
class MemoryPhotoShow extends MemoryPhotoStep {
  const MemoryPhotoShow(this.url);
  final String url;
}

/// Stop this turn. The next scheduled rotation may try one photo.
class MemoryPhotoHold extends MemoryPhotoStep {
  const MemoryPhotoHold();
}

/// Read this object's download URL at most once. Not a byte proxy.
class MemoryPhotoRefresh extends MemoryPhotoStep {
  const MemoryPhotoRefresh({
    required this.storagePath,
    required this.epoch,
    required this.fromServerUrl,
  });

  final String storagePath;
  final int epoch;
  final String fromServerUrl;
}

/// Picks dashboard memories and decides how a failed load recovers.
///
/// The wall tablet was leaving the error on screen until a later rebuild, and
/// that rebuild could paint a URL chosen after the previous frame. This deck
/// moves on to another memory immediately, but only a few times, then waits
/// for the normal two-minute rotation. A Firebase download URL is refreshed
/// at most once per object per session and once per turn, in memory only.
class MemoryPhotoDeck {
  MemoryPhotoDeck({
    this.maxSkipsPerTurn = 3,
    this.maxRefreshesPerTurn = 1,
    int Function(int length)? pickIndex,
    Random? random,
  }) {
    final rng = random ?? Random();
    _pickIndex = pickIndex ?? rng.nextInt;
  }

  final int maxSkipsPerTurn;
  final int maxRefreshesPerTurn;
  late final int Function(int length) _pickIndex;

  final List<MemoryPhoto> _photos = [];
  final Set<String> _failedThisTurn = {};
  final Set<String> _needsEvict = {};
  final Set<String> _refreshedPaths = {};
  final Map<String, String> _displayUrlByPath = {};
  final Map<String, String> _serverUrlByPath = {};

  String? _currentUrl;
  bool _holdingError = false;
  bool _refreshInFlight = false;
  int _skipsUsed = 0;
  int _refreshesUsed = 0;
  int _epoch = 0;

  String? get currentUrl => _currentUrl;
  bool get hasPhotos => _photos.isNotEmpty;
  bool get holdingError => _holdingError;
  int get refreshedPathCount => _refreshedPaths.length;

  /// Replaces the catalog from a photos snapshot.
  ///
  /// Keeps the current memory when it is still in the catalog so an unrelated
  /// snapshot does not rotate the wall or clear a held error. A refreshed
  /// download URL is reapplied when Firestore still has the old one.
  void setPhotos(List<MemoryPhoto> incoming) {
    final next = <MemoryPhoto>[];
    final seen = <String>{};
    for (final photo in incoming) {
      final serverUrl = photo.url.trim();
      if (serverUrl.isEmpty) continue;
      final path = canonicalHubPhotoStoragePath(photo.storagePath);
      var display = serverUrl;
      if (path != null) {
        final mapped = _displayUrlByPath[path];
        final fromServer = _serverUrlByPath[path];
        if (mapped != null && fromServer != null) {
          if (serverUrl == fromServer) {
            display = mapped;
          } else if (serverUrl != mapped) {
            _displayUrlByPath.remove(path);
            _serverUrlByPath.remove(path);
            _refreshedPaths.remove(path);
          }
        }
      }
      if (!seen.add(display)) continue;
      next.add(
        MemoryPhoto(
          id: photo.id,
          url: display,
          serverUrl: serverUrl,
          storagePath: path,
        ),
      );
    }

    _photos
      ..clear()
      ..addAll(next);

    if (next.isEmpty) {
      _bumpEpoch();
      _currentUrl = null;
      _holdingError = false;
      _failedThisTurn.clear();
      _skipsUsed = 0;
      return;
    }

    final stillShown = next.any((photo) => photo.url == _currentUrl);
    if (stillShown) return;

    _bumpEpoch();
    _failedThisTurn.clear();
    _skipsUsed = 0;
    _holdingError = false;
    _currentUrl = _pickUrl(next);
  }

  /// Scheduled rotation. One new photo, and the skip/refresh budgets reset.
  ///
  /// Returns a URL that already failed, so the caller can drop that one cache
  /// entry before painting. A photo that has not failed returns null and
  /// stays cached.
  String? advance() {
    _bumpEpoch();
    _skipsUsed = 0;
    _refreshesUsed = 0;
    _failedThisTurn.clear();
    _holdingError = false;
    if (_photos.isEmpty) {
      _currentUrl = null;
      return null;
    }
    final next = _pickUrl(_photos, avoid: _currentUrl);
    final evict = _needsEvict.remove(next) ? next : null;
    _currentUrl = next;
    return evict;
  }

  /// The image widget reported [url]. Safe to call again for the same load.
  MemoryPhotoStep onFailed(String url) {
    final failed = url.trim();
    if (failed.isEmpty || failed != _currentUrl) {
      return const MemoryPhotoIgnore();
    }
    if (_refreshInFlight || _failedThisTurn.contains(failed)) {
      return const MemoryPhotoIgnore();
    }
    _failedThisTurn.add(failed);
    _needsEvict.add(failed);

    final photo = _photoForUrl(failed);
    final path = photo?.storagePath;
    if (path != null &&
        !_refreshedPaths.contains(path) &&
        _refreshesUsed < maxRefreshesPerTurn) {
      _refreshesUsed++;
      _refreshedPaths.add(path);
      _refreshInFlight = true;
      return MemoryPhotoRefresh(
        storagePath: path,
        epoch: _epoch,
        fromServerUrl: photo!.serverUrl,
      );
    }
    return _skipOrHold();
  }

  /// Applies a download URL from Storage. Ignores a stale reply if the wall
  /// has already rotated. Does not write the new URL back to Firestore.
  MemoryPhotoStep adoptRefreshedUrl({
    required int epoch,
    required String storagePath,
    required String fromServerUrl,
    required String? newUrl,
  }) {
    final fresh = newUrl?.trim() ?? '';
    if (fresh.isNotEmpty && fresh != fromServerUrl) {
      _displayUrlByPath[storagePath] = fresh;
      _serverUrlByPath[storagePath] = fromServerUrl;
      for (var i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        if (photo.storagePath == storagePath &&
            photo.serverUrl == fromServerUrl) {
          _photos[i] = MemoryPhoto(
            id: photo.id,
            url: fresh,
            serverUrl: photo.serverUrl,
            storagePath: photo.storagePath,
          );
        }
      }
    }

    if (epoch != _epoch) return const MemoryPhotoIgnore();
    _refreshInFlight = false;
    if (fresh.isNotEmpty &&
        fresh != _currentUrl &&
        !_failedThisTurn.contains(fresh)) {
      _currentUrl = fresh;
      _holdingError = false;
      return MemoryPhotoShow(fresh);
    }
    return _skipOrHold();
  }

  MemoryPhoto? _photoForUrl(String url) {
    for (final photo in _photos) {
      if (photo.url == url) return photo;
    }
    return null;
  }

  MemoryPhotoStep _skipOrHold() {
    if (_skipsUsed >= maxSkipsPerTurn) {
      _holdingError = true;
      return const MemoryPhotoHold();
    }
    final choices = _photos
        .where((photo) => !_failedThisTurn.contains(photo.url))
        .toList();
    if (choices.isEmpty) {
      _holdingError = true;
      return const MemoryPhotoHold();
    }
    _skipsUsed++;
    _currentUrl = _pickUrl(choices);
    _holdingError = false;
    return MemoryPhotoShow(_currentUrl!);
  }

  String _pickUrl(List<MemoryPhoto> pool, {String? avoid}) {
    var choices = pool;
    if (avoid != null) {
      final others = pool.where((photo) => photo.url != avoid).toList();
      if (others.isNotEmpty) choices = others;
    }
    var index = _pickIndex(choices.length);
    if (index < 0 || index >= choices.length) {
      index = index.abs() % choices.length;
    }
    return choices[index].url;
  }

  void _bumpEpoch() {
    _epoch++;
    _refreshInFlight = false;
  }
}

/// Loads one replacement for [failedUrl].
///
/// A Storage download-URL read happens only when [MemoryPhotoDeck.onFailed]
/// asks for one. The same failure reported again returns without a read and
/// without [onChanged], so a rebuilding error widget cannot spin.
Future<void> recoverMemoryPhoto({
  required MemoryPhotoDeck deck,
  required String failedUrl,
  required Future<String?> Function(String storagePath) refreshDownloadUrl,
  required void Function(String url) evict,
  required void Function() onChanged,
  Duration refreshTimeout = const Duration(seconds: 8),
}) async {
  final step = deck.onFailed(failedUrl);
  if (step is MemoryPhotoIgnore) return;

  evict(failedUrl);
  if (step is MemoryPhotoRefresh) {
    String? fresh;
    try {
      fresh = await refreshDownloadUrl(
        step.storagePath,
      ).timeout(refreshTimeout);
    } catch (_) {
      fresh = null;
    }
    final follow = deck.adoptRefreshedUrl(
      epoch: step.epoch,
      storagePath: step.storagePath,
      fromServerUrl: step.fromServerUrl,
      newUrl: fresh,
    );
    if (follow is MemoryPhotoIgnore) return;
    onChanged();
    return;
  }
  onChanged();
}

/// Runs [advance] before [rebuild].
///
/// The two-minute timer used to rebuild the slide and only then change the
/// photo URL, so the frame kept the previous picture (often the error).
void commitMemoryRotation({
  required String? Function() advance,
  required void Function(String url) evict,
  required void Function() rebuild,
}) {
  final evictUrl = advance();
  if (evictUrl != null && evictUrl.isNotEmpty) evict(evictUrl);
  rebuild();
}
