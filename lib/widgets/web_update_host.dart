import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/web_build.dart';
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
    this.checkInterval = kWebUpdateCheckInterval,
    this.compactBelow = DashboardTheme.compactBreakpoint,
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

  /// Null skips the periodic re-read. Production uses 10 minutes.
  final Duration? checkInterval;

  /// Width below this is the phone prompt. Matches the dashboard.
  final double compactBelow;

  @override
  State<WebUpdateHost> createState() => _WebUpdateHostState();
}

class _WebUpdateHostState extends State<WebUpdateHost>
    with WidgetsBindingObserver {
  StreamSubscription<String?>? _remoteSub;
  StreamSubscription<void>? _focusSub;
  Timer? _timer;
  String? _remoteId;
  var _listening = false;

  /// Auto-reloads already fired for these ids in this page load.
  final Set<String> _autoReloaded = <String>{};

  bool get _enabled => widget.enabled ?? kIsWeb;

  WebUpdateAttemptStore get _attempts =>
      widget.attempts ?? const SessionWebUpdateAttemptStore();

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    _listening = true;
    WidgetsBinding.instance.addObserver(this);
    widget.sheetOpen?.addListener(_rebuild);
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
    }
    _remoteSub?.cancel();
    _focusSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _rebuild() {
    if (mounted) setState(() {});
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
    if (id.isEmpty) return;
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
      (widget.reload ?? reloadWebPage)();
    } catch (_) {
      // A failed navigation falls through to the chip on the next frame.
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final decision = _decision(context);
    if (decision.action == WebUpdateAction.reload) {
      final id = decision.remoteBuildId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _reload(id, fromUser: false);
      });
    }
    final showChip = decision.action == WebUpdateAction.prompt;
    return Stack(
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
      ],
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
