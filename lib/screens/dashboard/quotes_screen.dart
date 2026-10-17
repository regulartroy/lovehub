import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/quote_model.dart';
import '../../repositories/quote_repository.dart';
import '../../services/dashboard_voice.dart';
import '../../services/quote_voice.dart';
import '../../widgets/dashboard/dashboard_theme.dart';
import '../../widgets/quote_composer.dart';

/// The hub's custom quotes: the only quotes the dashboard shows.
///
/// Add one by typing, or tap the mic, say the quote, then say (or type) who
/// said it.
class QuotesScreen extends StatelessWidget {
  const QuotesScreen({
    super.key,
    required this.hubId,
    required this.repository,
    required this.speechRecognizer,
  });

  final String hubId;
  final QuoteRepository repository;
  final DashboardSpeechRecognizer speechRecognizer;

  static const micKey = ValueKey('quotes-mic');
  static const addKey = ValueKey('quotes-add');
  static const emptyKey = ValueKey('quotes-empty');
  static const listKey = ValueKey('quotes-list');
  static const unsupportedKey = ValueKey('quotes-voice-unsupported');
  static const deleteConfirmKey = ValueKey('quotes-delete-confirm');
  static const deleteCancelKey = ValueKey('quotes-delete-cancel');
  static const undoDuration = Duration(seconds: 5);

  static ValueKey<String> menuKey(String id) => ValueKey('quote-menu-$id');
  static ValueKey<String> cardKey(String id) => ValueKey('quote-card-$id');
  static const editItemKey = ValueKey('quote-menu-edit');
  static const deleteItemKey = ValueKey('quote-menu-delete');

  Future<void> _compose(BuildContext context, {required bool voice}) async {
    final saved = await showQuoteComposer(
      context,
      recognizer: speechRecognizer,
      startListening: voice,
      onSave: (text, author) =>
          repository.add(hubId, text: text, author: author),
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quote saved')));
    }
  }

  Future<void> _edit(BuildContext context, QuoteModel quote) async {
    final saved = await showQuoteComposer(
      context,
      recognizer: speechRecognizer,
      editing: true,
      initialText: quote.text,
      initialAuthor: quote.author,
      onSave: (text, author) =>
          repository.update(hubId, quote.id, text: text, author: author),
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quote updated')));
    }
  }

  Future<void> _delete(BuildContext context, QuoteModel quote) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DashboardTheme.surface,
        title: const Text(
          'Delete this quote?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '“${quote.text}”\n— ${quote.author}',
          style: const TextStyle(color: DashboardTheme.inkMuted),
        ),
        actions: [
          TextButton(
            key: deleteCancelKey,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: deleteConfirmKey,
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repository.delete(hubId, quote.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t delete that. Try again.')),
      );
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Quote deleted'),
        duration: undoDuration,
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => unawaited(repository.restore(hubId, quote)),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, QuoteModel quote) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DashboardTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.white),
              title: const Text('Edit', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.shade300,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Colors.red.shade300),
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'edit') {
      await _edit(context, quote);
    } else if (choice == 'delete') {
      await _delete(context, quote);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = speechRecognizer.isSupported;
    return Scaffold(
      backgroundColor: DashboardTheme.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Quotes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<QuoteModel>>(
        stream: repository.watch(hubId),
        builder: (context, snapshot) {
          final quotes = snapshot.data;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: [
                      _header(context, supported),
                      const SizedBox(height: 20),
                      if (snapshot.hasError)
                        const _Message(
                          icon: Icons.wifi_off_rounded,
                          title: 'Couldn’t load quotes',
                          body: 'Try again in a moment.',
                        )
                      else if (quotes == null)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: DashboardTheme.accent,
                            ),
                          ),
                        )
                      else if (quotes.isEmpty)
                        _Message(
                          key: emptyKey,
                          icon: Icons.format_quote_rounded,
                          title: 'Add your first quote',
                          body:
                              'Quotes you add show up on the dashboard. Until '
                              'then, that slide stays hidden.',
                          action: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: DashboardTheme.accent,
                            ),
                            onPressed: () => _compose(context, voice: false),
                            icon: const Icon(
                              Icons.add_rounded,
                              color: Colors.black87,
                            ),
                            label: const Text(
                              'Add a quote',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                        )
                      else
                        _list(context, quotes, wide),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, bool supported) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (supported)
              FilledButton.icon(
                key: micKey,
                style: FilledButton.styleFrom(
                  backgroundColor: DashboardTheme.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
                onPressed: () => _compose(context, voice: true),
                icon: const Icon(Icons.mic_rounded, color: Colors.black87),
                label: const Text(
                  'Add by voice',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            OutlinedButton.icon(
              key: addKey,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
              onPressed: () => _compose(context, voice: false),
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              label: const Text(
                'Type a quote',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        if (!supported) ...[
          const SizedBox(height: 10),
          const Row(
            key: unsupportedKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mic_off_rounded, color: Colors.white38, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  quoteVoiceUnsupportedNote,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _list(BuildContext context, List<QuoteModel> quotes, bool wide) {
    final cards = [
      for (final q in quotes)
        _QuoteCard(
          key: cardKey(q.id),
          quote: q,
          menuKey: menuKey(q.id),
          onEdit: () => _edit(context, q),
          onDelete: () => _delete(context, q),
          onLongPress: () => _showActions(context, q),
        ),
    ];
    if (!wide) {
      return Column(
        key: listKey,
        children: [
          for (final c in cards)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ],
      );
    }
    return Row(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var col = 0; col < 2; col++) ...[
          if (col > 0) const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var i = col; i < cards.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: cards[i],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    super.key,
    required this.quote,
    required this.menuKey,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPress,
  });

  final QuoteModel quote;
  final Key menuKey;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 4, 20),
        decoration: DashboardTheme.glassCard(tint: DashboardTheme.accent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '“${quote.text}”',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w300,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '— ${quote.author}',
                    style: TextStyle(
                      color: DashboardTheme.fade(DashboardTheme.accent, 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: menuKey,
              tooltip: 'Quote options',
              color: DashboardTheme.surface,
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Colors.white38,
                size: 20,
              ),
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  key: QuotesScreen.editItemKey,
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Text('Edit', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  key: QuotesScreen.deleteItemKey,
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red.shade300,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Delete',
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: DashboardTheme.glassCard(tint: DashboardTheme.accent),
      child: Column(
        children: [
          Icon(icon, color: DashboardTheme.accent, size: 44),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DashboardTheme.inkMuted,
              fontSize: 15,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
