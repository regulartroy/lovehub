import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../theme/calendar_colors.dart';

/// What a calendar chip tap should do for this event.
enum EventChipStatusAction { confirm, markTentative, edit }

/// Tentative chips confirm. Confirmed hub events can be marked tentative.
/// Virtual birthdays still open the editor.
EventChipStatusAction eventChipStatusAction(EventModel event) {
  if (event.isTentative) return EventChipStatusAction.confirm;
  if (canMarkEventTentativeFromChip(eventId: event.id, status: event.status)) {
    return EventChipStatusAction.markTentative;
  }
  return EventChipStatusAction.edit;
}

/// Primary label for confirming a tentative shift.
///
/// Narrow phones use the shorter line so the button stays one row.
String tentativeConfirmActionLabel(double screenWidth) {
  if (screenWidth < 360) return "I'm working this";
  return "Confirm I'm working this";
}

/// Confirm / keep actions for one tentative event.
///
/// [eventId] is the Firestore document id (`source:externalId` for imports).
class TentativeEventActions extends StatelessWidget {
  const TentativeEventActions({
    super.key,
    required this.eventId,
    required this.onConfirm,
    required this.onKeep,
    this.busy = false,
    this.dark = false,
    this.onEdit,
  });

  final String eventId;
  final VoidCallback? onConfirm;
  final VoidCallback? onKeep;
  final VoidCallback? onEdit;
  final bool busy;

  /// Light calendar sheets use dark ink. LOOK AHEAD glass uses [dark].
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final label = tentativeConfirmActionLabel(MediaQuery.sizeOf(context).width);
    final confirmFill = dark ? CalendarColors.lightInk : CalendarColors.darkInk;
    final confirmInk = dark ? CalendarColors.darkInk : CalendarColors.lightInk;
    final keepInk = dark ? Colors.white70 : const Color(0xFF5A564E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: ValueKey('tentative-event-confirm-$eventId'),
          onPressed: busy ? null : onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: confirmFill,
            foregroundColor: confirmInk,
            disabledBackgroundColor: confirmFill.withValues(alpha: 0.6),
            minimumSize: const Size.fromHeight(46),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: confirmInk,
                  ),
                )
              : Text(label, textAlign: TextAlign.center),
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            key: ValueKey('tentative-event-keep-$eventId'),
            onPressed: busy ? null : onKeep,
            style: TextButton.styleFrom(foregroundColor: keepInk),
            child: const Text('Keep tentative'),
          ),
        ),
        if (onEdit != null)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: ValueKey('tentative-event-edit-$eventId'),
              onPressed: busy ? null : onEdit,
              style: TextButton.styleFrom(foregroundColor: keepInk),
              child: const Text('Edit details'),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet Tom gets when he taps a tentative chip on the Calendar tab.
Future<void> showTentativeEventConfirmSheet({
  required BuildContext context,
  required String eventId,
  required String title,
  String? subtitle,
  String? notes,
  required Future<void> Function() onConfirm,
  VoidCallback? onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFBF7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return TentativeEventConfirmSheet(
        eventId: eventId,
        title: title,
        subtitle: subtitle,
        notes: notes,
        onConfirm: onConfirm,
        onEdit: onEdit,
      );
    },
  );
}

class TentativeEventConfirmSheet extends StatefulWidget {
  const TentativeEventConfirmSheet({
    super.key,
    required this.eventId,
    required this.title,
    this.subtitle,
    this.notes,
    required this.onConfirm,
    this.onEdit,
  });

  final String eventId;
  final String title;
  final String? subtitle;
  final String? notes;
  final Future<void> Function() onConfirm;
  final VoidCallback? onEdit;

  @override
  State<TentativeEventConfirmSheet> createState() =>
      _TentativeEventConfirmSheetState();
}

class _TentativeEventConfirmSheetState
    extends State<TentativeEventConfirmSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't confirm that shift. It's still tentative.";
      });
    }
  }

  void _edit() {
    final edit = widget.onEdit;
    Navigator.of(context).pop();
    edit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes?.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CalendarColors.darkInk,
              ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: const TextStyle(
                  color: Color(0xFF5A564E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8A8680)),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Tentative',
              style: TextStyle(
                color: Color(0xFF8A8680),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 12),
            TentativeEventActions(
              eventId: widget.eventId,
              busy: _busy,
              onConfirm: _confirm,
              onKeep: _busy ? null : () => Navigator.of(context).pop(),
              onEdit: widget.onEdit == null ? null : _edit,
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                key: const ValueKey('tentative-event-confirm-error'),
                style: const TextStyle(
                  color: Color(0xFF9A3B3B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mark / keep actions for one confirmed event. Mirror of [TentativeEventActions].
class MarkEventTentativeActions extends StatelessWidget {
  const MarkEventTentativeActions({
    super.key,
    required this.eventId,
    required this.onMarkTentative,
    required this.onKeep,
    this.busy = false,
    this.onEdit,
  });

  final String eventId;
  final VoidCallback? onMarkTentative;
  final VoidCallback? onKeep;
  final VoidCallback? onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const markFill = CalendarColors.darkInk;
    const markInk = CalendarColors.lightInk;
    const keepInk = Color(0xFF5A564E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: ValueKey('mark-event-tentative-$eventId'),
          onPressed: busy ? null : onMarkTentative,
          style: FilledButton.styleFrom(
            backgroundColor: markFill,
            foregroundColor: markInk,
            disabledBackgroundColor: markFill.withValues(alpha: 0.6),
            minimumSize: const Size.fromHeight(46),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: markInk,
                  ),
                )
              : const Text('Mark tentative', textAlign: TextAlign.center),
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            key: ValueKey('mark-event-keep-$eventId'),
            onPressed: busy ? null : onKeep,
            style: TextButton.styleFrom(foregroundColor: keepInk),
            child: const Text('Keep confirmed'),
          ),
        ),
        if (onEdit != null)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: ValueKey('mark-event-edit-$eventId'),
              onPressed: busy ? null : onEdit,
              style: TextButton.styleFrom(foregroundColor: keepInk),
              child: const Text('Edit details'),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet when a confirmed chip is tapped. Mark tentative, or dismiss.
Future<void> showMarkEventTentativeSheet({
  required BuildContext context,
  required String eventId,
  required String title,
  String? subtitle,
  String? notes,
  required Future<void> Function() onMarkTentative,
  VoidCallback? onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFFFFBF7),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return MarkEventTentativeSheet(
        eventId: eventId,
        title: title,
        subtitle: subtitle,
        notes: notes,
        onMarkTentative: onMarkTentative,
        onEdit: onEdit,
      );
    },
  );
}

class MarkEventTentativeSheet extends StatefulWidget {
  const MarkEventTentativeSheet({
    super.key,
    required this.eventId,
    required this.title,
    this.subtitle,
    this.notes,
    required this.onMarkTentative,
    this.onEdit,
  });

  final String eventId;
  final String title;
  final String? subtitle;
  final String? notes;
  final Future<void> Function() onMarkTentative;
  final VoidCallback? onEdit;

  @override
  State<MarkEventTentativeSheet> createState() =>
      _MarkEventTentativeSheetState();
}

class _MarkEventTentativeSheetState extends State<MarkEventTentativeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _mark() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onMarkTentative();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't mark that shift tentative. It's still confirmed.";
      });
    }
  }

  void _edit() {
    final edit = widget.onEdit;
    Navigator.of(context).pop();
    edit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes?.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CalendarColors.darkInk,
              ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: const TextStyle(
                  color: Color(0xFF5A564E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8A8680)),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Confirmed',
              style: TextStyle(
                color: Color(0xFF8A8680),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 12),
            MarkEventTentativeActions(
              eventId: widget.eventId,
              busy: _busy,
              onMarkTentative: _mark,
              onKeep: _busy ? null : () => Navigator.of(context).pop(),
              onEdit: widget.onEdit == null ? null : _edit,
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                key: const ValueKey('mark-event-tentative-error'),
                style: const TextStyle(
                  color: Color(0xFF9A3B3B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
