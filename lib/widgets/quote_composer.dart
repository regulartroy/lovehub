import 'dart:async';

import 'package:flutter/material.dart';

import '../models/quote_model.dart';
import '../services/dashboard_voice.dart';
import '../services/quote_voice.dart';
import 'dashboard/dashboard_theme.dart';

/// The two questions the composer asks, in order.
enum QuoteComposerStep { quote, author }

typedef QuoteSaveCallback = Future<void> Function(String text, String author);

/// Opens the add-a-quote composer in a dialog that suits phone and tablet.
///
/// [startListening] begins dictating the quote straight away (the page mic).
Future<bool> showQuoteComposer(
  BuildContext context, {
  required DashboardSpeechRecognizer recognizer,
  required QuoteSaveCallback onSave,
  bool startListening = false,
  String initialText = '',
  QuoteComposerStep initialStep = QuoteComposerStep.quote,
  bool dictatedInitialText = false,
  String initialAuthor = '',
  bool editing = false,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: DashboardTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: QuoteComposer(
          recognizer: recognizer,
          onSave: onSave,
          startListening: startListening,
          initialText: initialText,
          initialStep: initialStep,
          dictatedInitialText: dictatedInitialText,
          initialAuthor: initialAuthor,
          editing: editing,
          onClose: (didSave) => Navigator.of(ctx).pop(didSave),
        ),
      ),
    ),
  );
  return saved ?? false;
}

/// Add a quote by typing or speaking.
///
/// Step 1 collects the quote (speak, then edit). Step 2 asks "Who said
/// this?" (speak or type). Saving with no name stores [kDefaultQuoteAuthor].
class QuoteComposer extends StatefulWidget {
  const QuoteComposer({
    super.key,
    required this.recognizer,
    required this.onSave,
    required this.onClose,
    this.startListening = false,
    this.initialText = '',
    this.initialStep = QuoteComposerStep.quote,
    this.dictatedInitialText = false,
    this.initialAuthor = '',
    this.editing = false,
  });

  final DashboardSpeechRecognizer recognizer;
  final QuoteSaveCallback onSave;

  /// Called with true after a save, false on cancel.
  final ValueChanged<bool> onClose;
  final bool startListening;
  final String initialText;
  final QuoteComposerStep initialStep;

  /// Treat [initialText] as dictated, so the name step listens by itself.
  final bool dictatedInitialText;

  /// Prefills the "Who said this?" field (editing an existing quote).
  final String initialAuthor;

  /// Editing an existing quote: titles read "Edit quote".
  final bool editing;

  static const quoteFieldKey = ValueKey('quote-composer-text');
  static const authorFieldKey = ValueKey('quote-composer-author');
  static const micKey = ValueKey('quote-composer-mic');
  static const listeningKey = ValueKey('quote-composer-listening');
  static const listeningTextKey = ValueKey('quote-composer-listening-text');
  static const nextKey = ValueKey('quote-composer-next');
  static const backKey = ValueKey('quote-composer-back');
  static const saveKey = ValueKey('quote-composer-save');
  static const cancelKey = ValueKey('quote-composer-cancel');
  static const noticeKey = ValueKey('quote-composer-notice');
  static const unsupportedKey = ValueKey('quote-composer-unsupported');
  static const whoTitleKey = ValueKey('quote-composer-who-title');

  @override
  State<QuoteComposer> createState() => _QuoteComposerState();
}

class _QuoteComposerState extends State<QuoteComposer> {
  late final TextEditingController _text;
  late final TextEditingController _author;
  late QuoteComposerStep _step;
  bool _listening = false;
  bool _saving = false;
  bool _dictated = false;
  String? _notice;
  int _ticket = 0;

  bool get _supported => widget.recognizer.isSupported;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
    _author = TextEditingController(text: widget.initialAuthor);
    _step = widget.initialStep;
    _dictated = widget.dictatedInitialText;
    if (widget.startListening && _supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_listen());
      });
    }
  }

  @override
  void dispose() {
    _ticket++;
    widget.recognizer.cancel();
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_listening || _saving) return;
    if (!_supported) {
      setState(() => _notice = quoteVoiceUnsupportedNote);
      return;
    }
    final step = _step;
    final ticket = ++_ticket;
    setState(() {
      _listening = true;
      _notice = null;
    });
    DashboardSpeechCapture capture;
    try {
      capture = await widget.recognizer.listen(
        maxDuration: step == QuoteComposerStep.quote
            ? kQuoteListenLimit
            : kQuoteNameListenLimit,
      );
    } catch (_) {
      capture = const DashboardSpeechCapture(
        outcome: DashboardSpeechOutcome.error,
      );
    }
    if (!mounted || ticket != _ticket) return;
    if (capture.message == 'cancelled') {
      setState(() => _listening = false);
      return;
    }
    final problem = quoteVoiceNoticeFor(capture);
    if (problem != null) {
      setState(() {
        _listening = false;
        _notice = problem;
      });
      return;
    }
    final heard = step == QuoteComposerStep.quote
        ? cleanSpokenQuote(capture.transcript)
        : cleanSpokenAuthor(capture.transcript);
    if (heard.isEmpty) {
      setState(() {
        _listening = false;
        _notice = quoteDidntCatchNote;
      });
      return;
    }
    setState(() {
      _listening = false;
      _notice = null;
      if (step == QuoteComposerStep.quote) {
        _dictated = true;
        _text.text = heard;
        _text.selection = TextSelection.collapsed(offset: heard.length);
      } else {
        _author.text = heard;
        _author.selection = TextSelection.collapsed(offset: heard.length);
      }
    });
  }

  void _stopListening() {
    _ticket++;
    widget.recognizer.cancel();
    setState(() => _listening = false);
  }

  void _cancel() {
    _stopListening();
    widget.onClose(false);
  }

  void _goToAuthor() {
    if (_text.text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_listening) _stopListening();
    setState(() {
      _step = QuoteComposerStep.author;
      _notice = null;
    });
    // A dictated quote is a hands-free moment: ask for the name out loud too.
    if (_dictated && _supported && _author.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _step == QuoteComposerStep.author) {
          unawaited(_listen());
        }
      });
    }
  }

  void _backToQuote() {
    if (_listening) _stopListening();
    setState(() {
      _step = QuoteComposerStep.quote;
      _notice = null;
    });
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty || _saving) return;
    if (_listening) _stopListening();
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await widget.onSave(text, cleanSpokenAuthor(_author.text));
      if (!mounted) return;
      widget.onClose(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = 'Couldn’t save that. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onQuote = _step == QuoteComposerStep.quote;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onQuote) ..._quoteStep() else ..._authorStep(),
          const SizedBox(height: 18),
          _actions(onQuote),
        ],
      ),
    );
  }

  List<Widget> _quoteStep() {
    return [
      Text(
        widget.editing ? 'Edit quote' : 'Add a quote',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _supported
            ? 'Tap the mic and say it, or type it. You can edit before saving.'
            : 'Type a quote, inside joke, or affirmation.',
        style: const TextStyle(color: DashboardTheme.inkMuted, fontSize: 14),
      ),
      const SizedBox(height: 16),
      _inputRow(
        fieldKey: QuoteComposer.quoteFieldKey,
        controller: _text,
        hint: 'A quote, inside joke, or affirmation…',
        maxLines: 4,
        minLines: 3,
        capitalization: TextCapitalization.sentences,
      ),
      ..._voiceStatus(
        idleHint: _text.text.trim().isEmpty
            ? null
            : 'Tap the mic to say it again.',
        listeningText: 'Listening… say your quote',
      ),
    ];
  }

  List<Widget> _authorStep() {
    final preview = _text.text.trim();
    return [
      Text(
        'Who said this?',
        key: QuoteComposer.whoTitleKey,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(DashboardTheme.radiusSm),
        ),
        child: Text(
          '“$preview”',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DashboardTheme.inkMuted,
            fontStyle: FontStyle.italic,
            fontSize: 15,
          ),
        ),
      ),
      const SizedBox(height: 14),
      _inputRow(
        fieldKey: QuoteComposer.authorFieldKey,
        controller: _author,
        hint: 'Name',
        maxLines: 1,
        minLines: 1,
        capitalization: TextCapitalization.words,
        onSubmitted: (_) => unawaited(_save()),
      ),
      ..._voiceStatus(
        idleHint:
            'Tap the mic and say a name, or type it. Blank is saved as “$kDefaultQuoteAuthor”.',
        listeningText: 'Listening… say who said it',
      ),
    ];
  }

  Widget _inputRow({
    required Key fieldKey,
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required int minLines,
    required TextCapitalization capitalization,
    ValueChanged<String>? onSubmitted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            enabled: !_saving,
            style: const TextStyle(color: Colors.white, fontSize: 17),
            minLines: minLines,
            maxLines: maxLines,
            textCapitalization: capitalization,
            textInputAction: maxLines == 1
                ? TextInputAction.done
                : TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_supported) ...[const SizedBox(width: 12), _micButton()],
      ],
    );
  }

  Widget _micButton() {
    if (_listening) {
      return IconButton.filled(
        key: QuoteComposer.listeningKey,
        tooltip: 'Stop listening',
        style: IconButton.styleFrom(
          backgroundColor: Colors.redAccent,
          fixedSize: const Size(56, 56),
        ),
        icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 30),
        onPressed: _stopListening,
      );
    }
    return IconButton.filled(
      key: QuoteComposer.micKey,
      tooltip: _step == QuoteComposerStep.quote
          ? 'Say your quote'
          : 'Say a name',
      style: IconButton.styleFrom(
        backgroundColor: DashboardTheme.accent,
        fixedSize: const Size(56, 56),
      ),
      icon: const Icon(Icons.mic_rounded, color: Colors.black87, size: 30),
      onPressed: _saving ? null : () => unawaited(_listen()),
    );
  }

  List<Widget> _voiceStatus({
    required String? idleHint,
    required String listeningText,
  }) {
    final widgets = <Widget>[const SizedBox(height: 10)];
    if (!_supported) {
      widgets.add(
        const Row(
          key: QuoteComposer.unsupportedKey,
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
      );
    }
    if (_listening) {
      widgets.add(
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                listeningText,
                key: QuoteComposer.listeningTextKey,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (_notice != null) {
      if (_supported || _notice != quoteVoiceUnsupportedNote) {
        widgets.add(_noticeText(_notice!));
      }
    } else if (_supported && idleHint != null) {
      widgets.add(
        Text(
          idleHint,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
    }
    return widgets;
  }

  Widget _noticeText(String text) => Text(
    text,
    key: QuoteComposer.noticeKey,
    style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
  );

  Widget _actions(bool onQuote) {
    final cancel = TextButton(
      key: QuoteComposer.cancelKey,
      onPressed: _saving ? null : _cancel,
      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
    );
    final Widget primary;
    final Widget? secondary;
    if (onQuote) {
      secondary = null;
      primary = FilledButton(
        key: QuoteComposer.nextKey,
        style: FilledButton.styleFrom(backgroundColor: DashboardTheme.accent),
        onPressed: _text.text.trim().isEmpty ? null : _goToAuthor,
        child: const Text(
          'Next: who said this?',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      );
    } else {
      secondary = TextButton(
        key: QuoteComposer.backKey,
        onPressed: _saving ? null : _backToQuote,
        child: const Text('Edit quote'),
      );
      primary = FilledButton(
        key: QuoteComposer.saveKey,
        style: FilledButton.styleFrom(backgroundColor: DashboardTheme.accent),
        onPressed: _saving ? null : () => unawaited(_save()),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.black87,
                  strokeWidth: 2,
                ),
              )
            : Text(
                widget.editing ? 'Save changes' : 'Save quote',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [cancel, ?secondary, primary],
    );
  }
}
