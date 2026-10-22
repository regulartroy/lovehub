import 'package:flutter/material.dart';

/// How long a check-off Undo snackbar stays up.
const Duration kUndoSnackBarDuration = Duration(seconds: 4);

/// The deferred write after a check-off. A touch longer than the snackbar
/// so Undo is always pressable while it is visible.
const Duration kUndoCommitDelay = Duration(milliseconds: 4500);

/// App-wide messenger key so navigation can clear a stale Undo.
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a short "checked off" snackbar with an Undo action.
///
/// Since Flutter 3.29 a SnackBar with an action defaults to `persist: true`
/// and never auto-dismisses, which is why Undo used to linger. This forces
/// `persist: false`, replaces any current snackbar instead of queueing,
/// and hides on a tap anywhere outside it.
void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  Color? actionColor,
  SnackBarBehavior? behavior,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: TapRegion(
        onTapOutside: (_) => messenger.hideCurrentSnackBar(),
        child: Text(message),
      ),
      duration: kUndoSnackBarDuration,
      persist: false,
      behavior: behavior,
      dismissDirection: DismissDirection.horizontal,
      action: SnackBarAction(
        label: 'UNDO',
        textColor: actionColor,
        onPressed: onUndo,
      ),
    ),
  );
}

/// Clears snackbars when a route is pushed or popped, so an Undo from one
/// page never follows you to the next.
class SnackBarClearingObserver extends NavigatorObserver {
  SnackBarClearingObserver([GlobalKey<ScaffoldMessengerState>? key])
    : _key = key ?? appScaffoldMessengerKey;

  final GlobalKey<ScaffoldMessengerState> _key;

  void _clear(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    _key.currentState?.clearSnackBars();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _clear(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _clear(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _clear(newRoute);
}
