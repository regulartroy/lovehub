import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/quote_model.dart';
import 'package:lovehub/repositories/quote_repository.dart';
import 'package:lovehub/screens/dashboard/quotes_screen.dart';
import 'package:lovehub/services/dashboard_voice.dart';
import 'package:lovehub/services/quote_voice.dart';
import 'package:lovehub/widgets/quote_composer.dart';

/// Recognizer the test drives by hand.
class FakeRecognizer implements DashboardSpeechRecognizer {
  FakeRecognizer({this.supported = true});

  final bool supported;
  final List<Duration> windows = [];
  int cancels = 0;
  Completer<DashboardSpeechCapture>? _pending;

  @override
  bool get isSupported => supported;

  bool get isListening => _pending != null && !_pending!.isCompleted;

  @override
  Future<DashboardSpeechCapture> listen({
    Duration maxDuration = kDashboardListenLimit,
  }) {
    windows.add(maxDuration);
    _pending = Completer<DashboardSpeechCapture>();
    return _pending!.future;
  }

  void hear(String text) => _pending?.complete(
    DashboardSpeechCapture(
      outcome: DashboardSpeechOutcome.transcript,
      transcript: text,
    ),
  );

  void fail(DashboardSpeechOutcome outcome) =>
      _pending?.complete(DashboardSpeechCapture(outcome: outcome));

  @override
  void cancel() {
    cancels++;
    if (isListening) {
      _pending!.complete(
        const DashboardSpeechCapture(
          outcome: DashboardSpeechOutcome.empty,
          message: 'cancelled',
        ),
      );
    }
  }
}

class FakeQuotes implements QuoteRepository {
  FakeQuotes([List<QuoteModel> initial = const []]) {
    _quotes = [...initial];
  }

  late List<QuoteModel> _quotes;
  final _changes = StreamController<void>.broadcast();
  final List<(String, String)> saved = [];
  bool failNext = false;

  @override
  Stream<List<QuoteModel>> watch(String hubId) async* {
    yield _quotes;
    await for (final _ in _changes.stream) {
      yield _quotes;
    }
  }

  @override
  Future<void> add(
    String hubId, {
    required String text,
    String author = '',
  }) async {
    if (failNext) {
      failNext = false;
      throw Exception('offline');
    }
    final name = author.trim().isEmpty ? kDefaultQuoteAuthor : author.trim();
    saved.add((text, name));
    _quotes = [
      QuoteModel(id: '${saved.length}', text: text, author: name),
      ..._quotes,
    ];
    _changes.add(null);
  }
}

Future<void> pumpComposer(
  WidgetTester tester, {
  required FakeRecognizer recognizer,
  required Future<void> Function(String, String) onSave,
  List<bool>? closed,
  bool startListening = false,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 560,
            child: QuoteComposer(
              recognizer: recognizer,
              onSave: onSave,
              onClose: (v) => closed?.add(v),
              startListening: startListening,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('speak the quote, edit it, speak the name, save', (tester) async {
    final rec = FakeRecognizer();
    final saved = <(String, String)>[];
    final closed = <bool>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      closed: closed,
      onSave: (t, a) async => saved.add((t, a)),
    );

    expect(find.byKey(QuoteComposer.micKey), findsOneWidget);
    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    expect(find.byKey(QuoteComposer.listeningKey), findsOneWidget);
    expect(find.byKey(QuoteComposer.listeningTextKey), findsOneWidget);
    expect(rec.windows.single, kQuoteListenLimit);

    rec.hear('  home is wherever i am with you ');
    await tester.pump();
    expect(find.byKey(QuoteComposer.listeningKey), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(QuoteComposer.quoteFieldKey),
    );
    expect(field.controller!.text, 'Home is wherever i am with you');

    // Edit the transcription before moving on.
    await tester.enterText(
      find.byKey(QuoteComposer.quoteFieldKey),
      'Home is wherever I am with you',
    );
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    await tester.pump();

    // Dictated quote -> the name is asked out loud too.
    expect(find.byKey(QuoteComposer.whoTitleKey), findsOneWidget);
    expect(find.text('Who said this?'), findsOneWidget);
    expect(rec.isListening, isTrue);
    expect(rec.windows.last, kQuoteNameListenLimit);
    expect(find.byKey(QuoteComposer.listeningKey), findsOneWidget);

    rec.hear('it was Maria.');
    await tester.pump();
    final author = tester.widget<TextField>(
      find.byKey(QuoteComposer.authorFieldKey),
    );
    expect(author.controller!.text, 'Maria');

    await tester.tap(find.byKey(QuoteComposer.saveKey));
    await tester.pump();
    await tester.pump();
    expect(saved, [('Home is wherever I am with you', 'Maria')]);
    expect(closed, [true]);
  });

  testWidgets('typing works at both steps and a blank name is saved as Us', (
    tester,
  ) async {
    final rec = FakeRecognizer();
    final saved = <(String, String)>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      onSave: (t, a) async => saved.add((t, a)),
    );

    expect(
      tester.widget<FilledButton>(find.byKey(QuoteComposer.nextKey)).onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(QuoteComposer.quoteFieldKey),
      'You still do the washing up wrong',
    );
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();

    // Typed quote: the name step does not start listening by itself.
    expect(rec.windows, isEmpty);
    expect(find.byKey(QuoteComposer.whoTitleKey), findsOneWidget);

    await tester.tap(find.byKey(QuoteComposer.saveKey));
    await tester.pump();
    await tester.pump();
    expect(saved, [('You still do the washing up wrong', '')]);
  });

  testWidgets('typed name replaces nothing it should not, and is cleaned', (
    tester,
  ) async {
    final rec = FakeRecognizer();
    final saved = <(String, String)>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      onSave: (t, a) async => saved.add((t, a)),
    );
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'Hello');
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    await tester.enterText(find.byKey(QuoteComposer.authorFieldKey), 'mum');
    await tester.tap(find.byKey(QuoteComposer.saveKey));
    await tester.pump();
    await tester.pump();
    expect(saved, [('Hello', 'Mum')]);
  });

  testWidgets('retry after "didn\'t catch that"', (tester) async {
    final rec = FakeRecognizer();
    await pumpComposer(tester, recognizer: rec, onSave: (_, _) async {});

    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    rec.fail(DashboardSpeechOutcome.empty);
    await tester.pump();
    expect(find.text(quoteDidntCatchNote), findsOneWidget);
    expect(find.byKey(QuoteComposer.micKey), findsOneWidget);

    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    expect(find.text(quoteDidntCatchNote), findsNothing);
    rec.hear('second try');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(QuoteComposer.quoteFieldKey))
          .controller!
          .text,
      'Second try',
    );
  });

  testWidgets('mic blocked shows a note and typing still works', (
    tester,
  ) async {
    final rec = FakeRecognizer();
    await pumpComposer(tester, recognizer: rec, onSave: (_, _) async {});
    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    rec.fail(DashboardSpeechOutcome.denied);
    await tester.pump();
    expect(find.text(quoteMicBlockedNote), findsOneWidget);
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'Typed');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(QuoteComposer.nextKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('stop button ends listening and discards', (tester) async {
    final rec = FakeRecognizer();
    await pumpComposer(tester, recognizer: rec, onSave: (_, _) async {});
    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.listeningKey));
    await tester.pump();
    expect(find.byKey(QuoteComposer.listeningKey), findsNothing);
    expect(find.byKey(QuoteComposer.micKey), findsOneWidget);
    expect(rec.cancels, greaterThan(0));
    expect(
      tester
          .widget<TextField>(find.byKey(QuoteComposer.quoteFieldKey))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('cancel while listening closes without saving', (tester) async {
    final rec = FakeRecognizer();
    final closed = <bool>[];
    final saved = <String>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      closed: closed,
      onSave: (t, a) async => saved.add(t),
    );
    await tester.tap(find.byKey(QuoteComposer.micKey));
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.cancelKey));
    await tester.pump();
    expect(closed, [false]);
    expect(saved, isEmpty);
    expect(rec.isListening, isFalse);
  });

  testWidgets('edit quote goes back and keeps the name', (tester) async {
    final rec = FakeRecognizer();
    await pumpComposer(tester, recognizer: rec, onSave: (_, _) async {});
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'First');
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    await tester.enterText(find.byKey(QuoteComposer.authorFieldKey), 'Tom');
    await tester.tap(find.byKey(QuoteComposer.backKey));
    await tester.pump();
    expect(find.byKey(QuoteComposer.quoteFieldKey), findsOneWidget);
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'Second');
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(QuoteComposer.authorFieldKey))
          .controller!
          .text,
      'Tom',
    );
  });

  testWidgets('a failed save keeps the text and says so', (tester) async {
    final rec = FakeRecognizer();
    final closed = <bool>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      closed: closed,
      onSave: (_, _) async => throw Exception('offline'),
    );
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'Keep me');
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.saveKey));
    await tester.pump();
    await tester.pump();
    expect(closed, isEmpty);
    expect(find.byKey(QuoteComposer.noticeKey), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(QuoteComposer.saveKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('without speech support there is no mic, just a note', (
    tester,
  ) async {
    final rec = FakeRecognizer(supported: false);
    final saved = <(String, String)>[];
    await pumpComposer(
      tester,
      recognizer: rec,
      onSave: (t, a) async => saved.add((t, a)),
    );
    expect(find.byKey(QuoteComposer.micKey), findsNothing);
    expect(find.byKey(QuoteComposer.unsupportedKey), findsOneWidget);
    await tester.enterText(
      find.byKey(QuoteComposer.quoteFieldKey),
      'Typed only',
    );
    await tester.pump();
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    expect(find.byKey(QuoteComposer.micKey), findsNothing);
    expect(find.byKey(QuoteComposer.unsupportedKey), findsOneWidget);
    await tester.tap(find.byKey(QuoteComposer.saveKey));
    await tester.pump();
    await tester.pump();
    expect(saved, [('Typed only', '')]);
  });

  testWidgets('fits a small phone with the keyboard-sized viewport', (
    tester,
  ) async {
    final rec = FakeRecognizer();
    await pumpComposer(
      tester,
      recognizer: rec,
      size: const Size(360, 420),
      onSave: (_, _) async {},
    );
    await tester.enterText(find.byKey(QuoteComposer.quoteFieldKey), 'Short');
    await tester.pump();
    await tester.ensureVisible(find.byKey(QuoteComposer.nextKey));
    await tester.tap(find.byKey(QuoteComposer.nextKey));
    await tester.pump();
    await tester.ensureVisible(find.byKey(QuoteComposer.saveKey));
    expect(find.byKey(QuoteComposer.whoTitleKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('QuotesScreen', () {
    Future<void> pumpPage(
      WidgetTester tester,
      FakeQuotes repo,
      FakeRecognizer rec, {
      Size size = const Size(1280, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: QuotesScreen(
            hubId: 'hub',
            repository: repo,
            speechRecognizer: rec,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('empty hub gets an Add your first quote prompt', (
      tester,
    ) async {
      await pumpPage(tester, FakeQuotes(), FakeRecognizer());
      expect(find.byKey(QuotesScreen.emptyKey), findsOneWidget);
      expect(find.text('Add your first quote'), findsOneWidget);
      expect(find.byKey(QuotesScreen.micKey), findsOneWidget);
    });

    testWidgets('lists custom quotes with their author', (tester) async {
      final repo = FakeQuotes(const [
        QuoteModel(id: '1', text: 'Tea first', author: 'Maria'),
        QuoteModel(id: '2', text: 'Old one', author: 'Us'),
      ]);
      await pumpPage(tester, repo, FakeRecognizer());
      expect(find.byKey(QuotesScreen.emptyKey), findsNothing);
      expect(find.text('“Tea first”'), findsOneWidget);
      expect(find.text('— Maria'), findsOneWidget);
      expect(find.text('— Us'), findsOneWidget);
    });

    testWidgets('phone width lists in one column without overflow', (
      tester,
    ) async {
      final repo = FakeQuotes(const [
        QuoteModel(id: '1', text: 'Tea first', author: 'Maria'),
      ]);
      await pumpPage(
        tester,
        repo,
        FakeRecognizer(),
        size: const Size(390, 760),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(QuotesScreen.micKey), findsOneWidget);
    });

    testWidgets('mic starts listening, then asks who said it, then saves', (
      tester,
    ) async {
      final repo = FakeQuotes();
      final rec = FakeRecognizer();
      await pumpPage(tester, repo, rec);

      await tester.tap(find.byKey(QuotesScreen.micKey));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(rec.isListening, isTrue);
      expect(find.byKey(QuoteComposer.listeningKey), findsOneWidget);

      rec.hear('we should get a dog');
      await tester.pump();
      await tester.tap(find.byKey(QuoteComposer.nextKey));
      await tester.pump();
      await tester.pump();
      expect(find.text('Who said this?'), findsOneWidget);
      rec.hear('Tom');
      await tester.pump();
      await tester.tap(find.byKey(QuoteComposer.saveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.saved, [('We should get a dog', 'Tom')]);
      expect(find.text('“We should get a dog”'), findsOneWidget);
      expect(find.text('— Tom'), findsOneWidget);
      expect(find.byKey(QuotesScreen.emptyKey), findsNothing);
    });

    testWidgets('no speech support hides the mic and shows a note', (
      tester,
    ) async {
      await pumpPage(tester, FakeQuotes(), FakeRecognizer(supported: false));
      expect(find.byKey(QuotesScreen.micKey), findsNothing);
      expect(find.byKey(QuotesScreen.unsupportedKey), findsOneWidget);
      expect(find.byKey(QuotesScreen.addKey), findsOneWidget);
    });
  });
}
