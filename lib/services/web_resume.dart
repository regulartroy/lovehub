import 'dart:convert';

import 'package:flutter/foundation.dart';

/// sessionStorage key set just before an update reload. Its value is the
/// save time in epoch milliseconds. `web/index.html` reads the same key to
/// show "Installing update…" instead of the normal loader.
const kWebUpdateInstallingKey = 'lovehub.webUpdate.installing';

/// sessionStorage key holding a [WebResumeSnapshot] as JSON.
const kWebUpdateResumeKey = 'lovehub.webUpdate.resume';

/// A handoff older than this is ignored, so a stale flag can never put the
/// splash on an ordinary cold start. Keep in step with `web/index.html`.
const kWebUpdateHandoffMaxAge = Duration(minutes: 5);

/// Top-level tabs in `MainScreen`, in order. Restored indexes are clamped.
const kMainTabCount = 8;

/// Where the app was when an update reload started.
@immutable
class WebResumeSnapshot {
  const WebResumeSnapshot({
    this.tabIndex = 0,
    this.dashboardOpen = false,
    this.dashboardSlide = 0,
    required this.savedAtMs,
  });

  /// Selected bottom tab in `MainScreen` (0 = Home).
  final int tabIndex;

  /// Dashboard (wall) mode was pushed on top of `MainScreen`.
  final bool dashboardOpen;

  /// Carousel slide index inside the dashboard.
  final int dashboardSlide;

  final int savedAtMs;

  Map<String, Object> toJson() => {
    'v': 1,
    'tab': tabIndex,
    'dashboard': dashboardOpen,
    'slide': dashboardSlide,
    'savedAt': savedAtMs,
  };

  String encode() => jsonEncode(toJson());

  /// Null for anything malformed or older than [maxAge]. Never throws.
  static WebResumeSnapshot? decode(
    String? raw, {
    required DateTime now,
    Duration maxAge = kWebUpdateHandoffMaxAge,
  }) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final savedAt = data['savedAt'];
      if (savedAt is! int || !_fresh(savedAt, now, maxAge)) return null;
      final tab = data['tab'];
      final slide = data['slide'];
      return WebResumeSnapshot(
        tabIndex: tab is int ? tab.clamp(0, kMainTabCount - 1) : 0,
        dashboardOpen: data['dashboard'] == true,
        dashboardSlide: slide is int && slide >= 0 ? slide : 0,
        savedAtMs: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WebResumeSnapshot &&
      other.tabIndex == tabIndex &&
      other.dashboardOpen == dashboardOpen &&
      other.dashboardSlide == dashboardSlide &&
      other.savedAtMs == savedAtMs;

  @override
  int get hashCode =>
      Object.hash(tabIndex, dashboardOpen, dashboardSlide, savedAtMs);

  @override
  String toString() =>
      'WebResumeSnapshot(tab: $tabIndex, dashboard: $dashboardOpen, '
      'slide: $dashboardSlide)';
}

/// True when [raw] is a fresh "installing" flag written by an update reload.
bool isFreshInstallingFlag(
  String? raw, {
  required DateTime now,
  Duration maxAge = kWebUpdateHandoffMaxAge,
}) {
  final savedAt = int.tryParse(raw?.trim() ?? '');
  return savedAt != null && _fresh(savedAt, now, maxAge);
}

bool _fresh(int savedAtMs, DateTime now, Duration maxAge) {
  final age = now.millisecondsSinceEpoch - savedAtMs;
  // A little negative skew is fine; anything else is stale or bogus.
  return age > -60000 && age <= maxAge.inMilliseconds;
}

/// Tracks where the app is, and hands a saved location back once after an
/// update reload.
///
/// `MainScreen` reports its tab and the dashboard reports its slide. The
/// update host snapshots this just before reloading. On the next page load
/// `main()` calls [boot] with whatever sessionStorage held, and the screens
/// take the pending location once.
class WebResumeController extends ChangeNotifier {
  WebResumeController();

  /// App-wide instance. Tests may build their own.
  static final WebResumeController instance = WebResumeController();

  int _tabIndex = 0;
  int _dashboards = 0;
  int _dashboardSlide = 0;

  WebResumeSnapshot? _pending;
  bool _resumingFromUpdate = false;
  bool _ready = true;

  int get tabIndex => _tabIndex;
  bool get dashboardOpen => _dashboards > 0;
  int get dashboardSlide => _dashboardSlide;

  /// This page load follows an update reload: show the splash until [ready].
  bool get resumingFromUpdate => _resumingFromUpdate;

  /// The restored screen is in place (or there is nothing to restore).
  bool get ready => _ready;

  /// Location saved before the reload, not yet restored.
  WebResumeSnapshot? get pending => _pending;

  /// Call once at startup with the raw sessionStorage values (already
  /// removed from storage by the caller). Stale or malformed values are
  /// ignored, so a normal cold start never shows the splash.
  void boot({
    required String? installingFlag,
    required String? resumeJson,
    required DateTime now,
  }) {
    _resumingFromUpdate = isFreshInstallingFlag(installingFlag, now: now);
    _pending = _resumingFromUpdate
        ? WebResumeSnapshot.decode(resumeJson, now: now)
        : null;
    _ready = !_resumingFromUpdate;
  }

  void setTab(int index) {
    _tabIndex = index;
  }

  void dashboardOpened(int slide) {
    _dashboards += 1;
    _dashboardSlide = slide < 0 ? 0 : slide;
  }

  void dashboardSlideChanged(int slide) {
    if (_dashboards == 0) return;
    _dashboardSlide = slide < 0 ? 0 : slide;
  }

  void dashboardClosed() {
    if (_dashboards > 0) _dashboards -= 1;
    if (_dashboards == 0) _dashboardSlide = 0;
  }

  /// Current location, for the update host to save before a reload.
  WebResumeSnapshot snapshot({DateTime? now}) {
    return WebResumeSnapshot(
      tabIndex: _tabIndex,
      dashboardOpen: dashboardOpen,
      dashboardSlide: dashboardOpen ? _dashboardSlide : 0,
      savedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  /// Returns the saved location once, then forgets it.
  WebResumeSnapshot? takePending() {
    final value = _pending;
    _pending = null;
    return value;
  }

  /// The resumed screen is showing. Fades the splash. Safe to call often.
  void markReady() {
    if (_ready) return;
    _ready = true;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _tabIndex = 0;
    _dashboards = 0;
    _dashboardSlide = 0;
    _pending = null;
    _resumingFromUpdate = false;
    _ready = true;
  }
}
