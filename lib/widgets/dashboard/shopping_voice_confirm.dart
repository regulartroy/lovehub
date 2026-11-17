import 'package:flutter/material.dart';

import '../../services/shopping_voice.dart';
import 'dashboard_theme.dart';

/// Large, touch-friendly confirm box for items heard by the dashboard mic.
///
/// Each item can be edited or removed, and more can be typed in. Pops with
/// the final tidied list on Add, or null on Cancel.
class ShoppingVoiceConfirmDialog extends StatefulWidget {
  const ShoppingVoiceConfirmDialog({
    super.key,
    required this.items,
    this.heard = '',
  });

  final List<String> items;
  final String heard;

  static const cardKey = ValueKey('shopping-voice-confirm');
  static const addKey = ValueKey('shopping-voice-confirm-add');
  static const cancelKey = ValueKey('shopping-voice-confirm-cancel');
  static const addRowKey = ValueKey('shopping-voice-confirm-add-row');
  static Key fieldKey(int i) => ValueKey('shopping-voice-confirm-field-$i');
  static Key removeKey(int i) => ValueKey('shopping-voice-confirm-remove-$i');

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> items,
    String heard = '',
  }) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC07070C),
      builder: (_) => ShoppingVoiceConfirmDialog(items: items, heard: heard),
    );
  }

  @override
  State<ShoppingVoiceConfirmDialog> createState() =>
      _ShoppingVoiceConfirmDialogState();
}

class _ShoppingVoiceConfirmDialogState
    extends State<ShoppingVoiceConfirmDialog> {
  late final List<TextEditingController> _rows = [
    for (final item in widget.items) TextEditingController(text: item),
  ];
  final List<FocusNode> _focus = [];

  @override
  void initState() {
    super.initState();
    _focus.addAll([for (var i = 0; i < _rows.length; i++) FocusNode()]);
    if (_rows.isEmpty) _addRow(focus: false);
  }

  @override
  void dispose() {
    for (final c in _rows) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _addRow({bool focus = true}) {
    final controller = TextEditingController();
    final node = FocusNode();
    setState(() {
      _rows.add(controller);
      _focus.add(node);
    });
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
  }

  void _removeRow(int i) {
    final controller = _rows.removeAt(i);
    final node = _focus.removeAt(i);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
      node.dispose();
    });
  }

  List<String> get _finalItems {
    final seen = <String>{};
    final out = <String>[];
    for (final c in _rows) {
      final item = tidyShoppingItem(c.text);
      if (item.isEmpty) continue;
      if (seen.add(shoppingItemKey(item))) out.add(item);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final count = _finalItems.length;
    final heard = widget.heard.trim();
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < DashboardTheme.compactBreakpoint;
    final fontSize = compact ? 20.0 : 24.0;

    return Dialog(
      key: ShoppingVoiceConfirmDialog.cardKey,
      backgroundColor: DashboardTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
        side: BorderSide(
          color: DashboardTheme.shopping.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shopping_basket_rounded,
                    color: DashboardTheme.shopping,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add to shopping list?',
                      style: TextStyle(
                        color: DashboardTheme.ink,
                        fontSize: fontSize + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (heard.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '“$heard”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: DashboardTheme.inkMuted,
                    fontSize: fontSize - 6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _rows.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: ShoppingVoiceConfirmDialog.fieldKey(i),
                                  controller: _rows[i],
                                  focusNode: _focus[i],
                                  onChanged: (_) => setState(() {}),
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: TextStyle(
                                    color: DashboardTheme.ink,
                                    fontSize: fontSize,
                                  ),
                                  cursorColor: DashboardTheme.shopping,
                                  decoration: InputDecoration(
                                    hintText: 'Item',
                                    hintStyle: const TextStyle(
                                      color: DashboardTheme.inkFaint,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.06,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        DashboardTheme.radiusSm,
                                      ),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                key: ShoppingVoiceConfirmDialog.removeKey(i),
                                tooltip: 'Remove',
                                iconSize: 32,
                                constraints: const BoxConstraints(
                                  minWidth: 56,
                                  minHeight: 56,
                                ),
                                color: DashboardTheme.inkMuted,
                                onPressed: () => _removeRow(i),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ShoppingVoiceConfirmDialog.addRowKey,
                  onPressed: _addRow,
                  style: TextButton.styleFrom(
                    foregroundColor: DashboardTheme.shopping,
                    minimumSize: const Size(0, 52),
                    textStyle: TextStyle(fontSize: fontSize - 4),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 28),
                  label: const Text('Add another'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ShoppingVoiceConfirmDialog.cancelKey,
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DashboardTheme.ink,
                        side: const BorderSide(color: DashboardTheme.inkFaint),
                        minimumSize: const Size.fromHeight(64),
                        textStyle: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DashboardTheme.radiusMd,
                          ),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      key: ShoppingVoiceConfirmDialog.addKey,
                      onPressed: count == 0
                          ? null
                          : () => Navigator.of(context).pop(_finalItems),
                      style: FilledButton.styleFrom(
                        backgroundColor: DashboardTheme.shopping,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(64),
                        textStyle: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DashboardTheme.radiusMd,
                          ),
                        ),
                      ),
                      child: Text(
                        count == 1 ? 'Add 1 item' : 'Add $count items',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
