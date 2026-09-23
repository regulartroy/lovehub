import 'package:flutter/material.dart';

/// Tentative switch on the create/edit event sheet.
///
/// Same tile style as All Day. On writes `status: tentative`. Off writes
/// explicit `status: confirmed`.
class EventTentativeField extends StatelessWidget {
  const EventTentativeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  static const Key fieldKey = ValueKey('event-form-tentative');

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: fieldKey,
      title: const Text('Tentative'),
      value: value,
      activeThumbColor: Colors.pink,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }
}

/// The create/edit sheet writes `status` on hub event documents.
///
/// New birthdays and virtual birthday rows live on the birthdays collection,
/// which has no status field, so the switch stays hidden there.
bool eventFormWritesStatus({
  String? existingEventId,
  required String category,
}) {
  if (existingEventId != null) {
    final id = existingEventId.trim();
    return id.isNotEmpty && !id.startsWith('bday_');
  }
  return category != 'birthday';
}
