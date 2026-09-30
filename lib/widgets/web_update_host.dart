import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/web_build.dart';
import '../services/web_resume.dart';
import '../services/web_update_platform.dart';
import '../services/web_update_policy.dart';
import 'dashboard/dashboard_theme.dart';

/// True while a dialog, bottom sheet, or other popup is the current route.
///
/// Page pushes (Calendar, Dashboard, and the rest) do not count. Create and
/// edit flows in LoveHub are sheets, and those should block a quiet reload.
abstract class WebUpdateSheetSignal implements Listenable {
  bool get isOpen;
}

class WebUpdateSheetTracker extends NavigatorObserver
    with ChangeNotifier
    implements WebUpdateSheetSignal {
  int _open = 0;
  bool _disposed = false;

  @override
  bool get isOpen => _open > 0;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isBlocking(route)) _change(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isBlocking(route)) _change(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isBlocking(route)) _change(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    var delta = 0;
    if (oldRoute != null && _isBlocking(oldRoute)) delta -= 1;
    if (newRoute != null && _isBlocking(newRoute)) delta += 1;
    if (delta != 0) _change(delta);
  }

  void _change(int delta) {
    final next = _open + delta;
    _open = next < 0 ? 0 : next;
    if (!_disposed) notifyListeners();
  }

  bool _isBlocking(Route<dynamic> route) {
    return route is PopupRoute && route is! PageRoute;
  }
}

/// Watches the hosted build id on web and either reloads or shows a chip.
///
/// Off web this is a no-op. Checks run from the Firestore listener, window
/// focus, app resume, and [checkInterval] — not from ordinary taps.
///
/// Every reload (quiet tablet reload or a tap on the chip) first covers the
/// app with [WebUpdateSplash], saves where the app is via [handoff], then
/// reloads after [splashDelay]. On the next page load `web/index.html` and
/// this host keep the same splash up until the restored screen calls
/// [WebResumeController.markReady], then fade it away.
class WebUpdateHost extends StatefulWidget {
  const WebUpdateHost({
    super.key,
    required this.child,
    this.enabled,
    this.localBuildId = kWebBuildId,
    this.sheetOpen,
    this.remoteUpdates,
    this.fetchRemote,
    this.focusEvents,
    this.reload,
    this.attempts,
    this.handoff,
    this.resume,
    this.checkInterval = kWebUpdateCheckInterval,
    this.compactBelow = DashboardTheme.compactBreakpoint,
    this.splashDelay = const Duration(milliseconds: 900),
    this.resumeSplashTimeout = const Duration(seconds: 10),
    this.reloadFallback = const Duration(seconds: 20),
  });

  final Widget child;

  /// Null follows [kIsWeb]. Tests pass true to exercise the UI on the VM.
  final bool? enabled;

  final String localBuildId;
  final WebUpdateSheetSignal? sheetOpen;

  /// Snapshot stream of the remote build id. Null stays idle (tests that
  /// only care about layout can omit it).
  final Stream<String?>? remoteUpdates;

  /// Focus, resume, and the periodic timer call this. Production passes
  /// a Firestore get.
  final Future<String?> Function()? fetchRemote;

  /// Defaults to browser window focus on web, and an empty stream elsewhere.
  final Stream<void>? focusEvents;

  /// Defaults to `location.reload()` on web.
  final void Function()? reload;

  /// Defaults to sessionStorage on web.
  final WebUpdateAttemptStore? attempts;

  /// Carries the splash flag and saved location across the reload.
  /// Defaults to sessionStorage on web.
  final WebUpdateHandoff? handoff;

  /// Current location and post-reload state. Defaults to
  /// [WebResumeController.instance].
  final WebResumeController? resume;

  /// Null skips the periodic re-read. Production uses 10 minutes.
  final Duration? checkInterval;

  /// Width below this is the phone prompt. Matches the dashboard.
  final double compactBelow;

  /// How long the "Installing update" splash shows before the page reloads.
  /// [Duration.zero] reloads in the same frame (tests).
  final Duration splashDelay;

  /// After an update reload, the splash fades by itself after this long even
  /// if no screen reports ready (e.g. sign-in needed, slow network).
  final Duration resumeSplashTimeout;

  /// If the page is still here this long after asking the browser to reload,
  /// drop the splash and clear the handoff. The chip takes over.
  final Duration reloadFallback;

  @override
  State<WebUpdateHost> createState() => _WebUpdateHostState();
}

class _WebUpdateHostState extends State<WebUpdateHost>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _remoteSub;
  StreamSubscription<void>? _focusSub;
  Timer? _timer;
  Timer? _reloadTimer;
  Timer? _fallbackTimer;
  Timer? _resumeTimer;
  String? _remoteId;
  var _listening = false;

  /// Splash is in the tree. [_splashFading] animates it out, then removes it.
  var _splashVisible = false;
  var _splashFading = false;

  /// A reload is under way; ignore further reload requests and hide the chip.
  var _installing = false;

  /// Auto-reloads already fired for these ids in this page load.
  final Set<String> _autoReloaded = <String>{};

  bool get _enabled => widget.enabled ?? kIsWeb;

  WebUpdateAttemptStore get _attempts =>
      widget.attempts ?? const SessionWebUpdateAttemptStore();

  WebUpdateHandoff get _handoff =>
      widget.handoff ?? const SessionWebUpdateHandoff();

  WebResumeController get _resume =>
      widget.resume ?? WebResumeController.instance;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    _listening = true;
    WidgetsBinding.instance.addObserver(this);
    widget.sheetOpen?.addListener(_rebuild);
    final resume = _resume;
    if (resume.resumingFromUpdate && !resume.ready) {
      _splashVisible = true;
      resume.addListener(_onResumeChanged);
      _resumeTimer = Timer(widget.resumeSplashTimeout, _fadeSplash);
    }
    final updates = widget.remoteUpdates;
    if (updates != null) {
      _remoteSub = updates.listen(_setRemote, onError: (_, _) {});
    }
    _focusSub = (widget.focusEvents ?? webWindowFocusEvents()).listen(
      (_) => _refresh(),
      onError: (_, _) {},
    );
    final interval = widget.checkInterval;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => _refresh());
    }
  }

  @override
  void dispose() {
    if (_listening) {
      WidgetsBinding.instance.removeObserver(this);
      widget.sheetOpen?.removeListener(_rebuild);
      _resume.removeListener(_onResumeChanged);
    }
    _remoteSub?.cancel();
    _focusSub?.cancel();
    _timer?.cancel();
    _reloadTimer?.cancel();
    _fallbackTimer?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onResumeChanged() {
    if (_resume.ready) _fadeSplash();
  }

  /// Fades the post-reload splash. Never interrupts an update in progress.
  void _fadeSplash() {
    _resumeTimer?.cancel();
    _resume.removeListener(_onResumeChanged);
    if (!mounted || _installing || !_splashVisible || _splashFading) return;
    setState(() => _splashFading = true);
  }

  void _onSplashFadeEnd() {
    if (!mounted || !_splashFading || _installing) return;
    setState(() {
      _splashVisible = false;
      _splashFading = false;
    });
  }

  void _setRemote(String? id) {
    if (!mounted) return;
    final trimmed = id?.trim();
    final normalized = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (_remoteId == normalized) return;
    setState(() => _remoteId = normalized);
  }

  Future<void> _refresh() async {
    final fetch = widget.fetchRemote;
    if (!_enabled || fetch == null) return;
    try {
      _setRemote(await fetch());
    } catch (_) {
      // Keep the last known id. The next focus or tick tries again.
    }
  }

  WebUpdateDecision _decision(BuildContext context) {
    return decideWebUpdate(
      localBuildId: widget.localBuildId,
      remoteBuildId: _remoteId,
      isCompactLayout: MediaQuery.sizeOf(context).width < widget.compactBelow,
      sheetOrModalOpen: widget.sheetOpen?.isOpen ?? false,
      alreadyAttemptedIds: {..._attempts.read(), ..._autoReloaded},
    );
  }

  void _reload(String remoteBuildId, {required bool fromUser}) {
    final id = remoteBuildId.trim();
    if (id.isEmpty || _installing) return;
    if (!fromUser) {
      if (_autoReloaded.contains(id)) return;
      _autoReloaded.add(id);
    }
    // Persist before navigating so a cached page cannot loop on this id.
    try {
      _attempts.remember(id);
    } catch (_) {
      // sessionStorage can throw; the in-memory id still blocks another auto-reload.
    }
    try {
      final now = DateTime.now();
      _handoff.begin(
        installingFlag: '${now.millisecondsSinceEpoch}',
        resumeJson: _resume.snapshot(now: now).encode(),
      );
    } catch (_) {
      // Without the handoff the reload still works; it just starts fresh.
    }
    _resumeTimer?.cancel();
    if (widget.splashDelay > Duration.zero) _warmSplashLogo();
    if (mounted) {
      setState(() {
        _installing = true;
        _splashVisible = true;
        _splashFading = false;
      });
    }
    if (widget.splashDelay <= Duration.zero) {
      _navigate();
    } else {
      _reloadTimer = Timer(widget.splashDelay, _navigate);
    }
  }

  /// Starts decoding the logo so it is ready during [WebUpdateHost.splashDelay].
  void _warmSplashLogo() {
    try {
      final stream = const AssetImage(
        kWebUpdateSplashLogo,
      ).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) => stream.removeListener(listener),
        onError: (_, _) => stream.removeListener(listener),
      );
      stream.addListener(listener);
    } catch (_) {}
  }

  void _navigate() {
    try {
      (widget.reload ?? reloadWebPage)();
    } catch (_) {
      // A failed navigation falls through to the fallback below.
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(widget.reloadFallback, () {
      // Still on this page: the browser did not reload. Put the app back
      // and let the chip offer the update (the id is already attempted).
      try {
        _handoff.clear();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _installing = false;
        _splashVisible = false;
        _splashFading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final decision = _decision(context);
    if (decision.action == WebUpdateAction.reload && !_installing) {
      final id = decision.remoteBuildId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reload(id, fromUser: false);
      });
    }
    final showChip = decision.action == WebUpdateAction.prompt && !_installing;
    final remote = _remoteId;
    final local = widget.localBuildId.trim();
    final canInstall =
        remote != null && local.isNotEmpty && remote != local && !_installing;
    return WebUpdateScope(
      enabled: true,
      localBuildId: local,
      remoteBuildId: remote,
      installing: _installing,
      onInstall: canInstall ? () => _reload(remote, fromUser: true) : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (showChip)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              right: 12,
              child: Center(
                child: _UpdateReadyChip(
                  onTap: () => _reload(decision.remoteBuildId, fromUser: true),
                ),
              ),
            ),
          if (_splashVisible)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _splashFading ? 0 : 1,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                onEnd: _onSplashFadeEnd,
                child: AbsorbPointer(
                  absorbing: !_splashFading,
                  child: const WebUpdateSplash(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Build ids for the version line in Settings.
///
/// Present under [WebUpdateHost] on web. Null off web or in a widget tree
/// without the host.
class WebUpdateScope extends InheritedWidget {
  const WebUpdateScope({
    super.key,
    required this.enabled,
    required this.localBuildId,
    required this.remoteBuildId,
    required this.installing,
    required this.onInstall,
    required super.child,
  });

  final bool enabled;

  /// Id compiled into the running app. Empty for a dev build.
  final String localBuildId;

  /// Latest id stamped in `appMeta/web`. Null until it has been read.
  final String? remoteBuildId;

  final bool installing;

  /// Starts the splash + reload flow. Null when already up to date.
  final VoidCallback? onInstall;

  static WebUpdateScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebUpdateScope>();

  @override
  bool updateShouldNotify(WebUpdateScope oldWidget) =>
      enabled != oldWidget.enabled ||
      localBuildId != oldWidget.localBuildId ||
      remoteBuildId != oldWidget.remoteBuildId ||
      installing != oldWidget.installing ||
      (onInstall == null) != (oldWidget.onInstall == null);
}

/// Logo used by [WebUpdateSplash] (same file as the login screen).
const kWebUpdateSplashLogo = 'assets/logo.png';

/// Loads and decodes the splash logo so the splash never shows without it.
///
/// `main()` awaits this (bounded by [timeout]) only after an update reload,
/// while the pre-Flutter splash in `web/index.html` is still on screen.
Future<void> precacheWebUpdateSplashLogo({
  Duration timeout = const Duration(seconds: 2),
}) async {
  final done = Completer<void>();
  try {
    final stream = const AssetImage(
      kWebUpdateSplashLogo,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish() {
      if (!done.isCompleted) done.complete();
      stream.removeListener(listener);
    }

    listener = ImageStreamListener(
      (_, _) => finish(),
      onError: (_, _) => finish(),
    );
    stream.addListener(listener);
    await done.future.timeout(timeout, onTimeout: () {});
  } catch (_) {
    // The splash falls back to fading the logo in.
  }
}

/// Full-screen "Installing update" cover. Matches the pre-Flutter version in
/// `web/index.html` (white, 120px logo, text, small spinner) so the reload
/// reads as one continuous splash.
class WebUpdateSplash extends StatelessWidget {
  const WebUpdateSplash({super.key});

  static const text = 'Installing update…';

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('web-update-splash'),
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              kWebUpdateSplashLogo,
              width: 120,
              height: 120,
              fit: BoxFit.contain,
              frameBuilder: (context, child, frame, sync) {
                if (sync) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: child,
                );
              },
              errorBuilder: (_, _, _) => const Icon(
                Icons.favorite_rounded,
                size: 96,
                color: Color(0xFFE91E63),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              text,
              style: TextStyle(
                color: Color(0xFFE91E63),
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFE91E63),
                backgroundColor: Color(0xFFFFE4E1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateReadyChip extends StatelessWidget {
  const _UpdateReadyChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE91E63),
      elevation: 4,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        key: const ValueKey('web-update-ready'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Update ready',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
