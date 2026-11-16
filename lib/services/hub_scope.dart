import 'package:flutter/widgets.dart';

/// Ties a section's widget subtree to one hub.
///
/// When [hubId] changes, the old subtree (and every State, stream
/// subscription, cached stream and in-memory list inside it) is disposed and
/// a fresh one is built for the new hub. Nothing from the previous hub can
/// leak through, and each section starts from its own loading state.
///
/// When [hubId] stays the same, the subtree keeps its state as usual.
class HubScoped extends StatelessWidget {
  const HubScoped({
    super.key,
    required this.hubId,
    required this.section,
    required this.child,
  });

  final String? hubId;

  /// Distinguishes sibling sections so their keys never collide.
  final String section;

  final Widget child;

  static Key keyFor(String? hubId, String section) =>
      ValueKey<String>('hub:${hubId ?? '-'}:$section');

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: keyFor(hubId, section), child: child);
}
