import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/quote_model.dart';
import 'package:lovehub/services/dashboard_voice.dart';
import 'package:lovehub/services/quote_voice.dart';

void main() {
  group('cleanSpokenQuote', () {
    test('trims, collapses spaces and capitalises', () {
      expect(
        cleanSpokenQuote('  home is   wherever I am with you '),
        'Home is wherever I am with you',
      );
    });

    test('drops wrapping quote marks', () {
      expect(
        cleanSpokenQuote('“Two are better than one.”'),
        'Two are better than one.',
      );
      expect(cleanSpokenQuote('"hello"'), 'Hello');
    });

    test('empty stays empty', () {
      expect(cleanSpokenQuote('   '), '');
      expect(cleanSpokenQuote('""'), '');
    });
  });

  group('cleanSpokenAuthor', () {
    test('removes lead-ins and trailing punctuation', () {
      expect(cleanSpokenAuthor('it was Maria.'), 'Maria');
      expect(cleanSpokenAuthor("That's Tom"), 'Tom');
      expect(cleanSpokenAuthor('said by Oscar Wilde'), 'Oscar Wilde');
    });

    test('capitalises an all-lower-case name only', () {
      expect(cleanSpokenAuthor('mum'), 'Mum');
      expect(cleanSpokenAuthor('oscar wilde'), 'Oscar Wilde');
      expect(cleanSpokenAuthor('Ellie McGregor'), 'Ellie McGregor');
    });

    test('blank stays blank', () {
      expect(cleanSpokenAuthor('  '), '');
      expect(cleanSpokenAuthor('it was'), '');
    });
  });

  group('quoteVoiceNoticeFor', () {
    DashboardSpeechCapture cap(DashboardSpeechOutcome o, [String t = '']) =>
        DashboardSpeechCapture(outcome: o, transcript: t);

    test('a transcript has no notice, a blank one does', () {
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.transcript, 'hi')),
        isNull,
      );
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.transcript, ' ')),
        quoteDidntCatchNote,
      );
    });

    test('each failure has its own note', () {
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.unavailable)),
        quoteVoiceUnsupportedNote,
      );
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.denied)),
        quoteMicBlockedNote,
      );
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.empty)),
        quoteDidntCatchNote,
      );
      expect(
        quoteVoiceNoticeFor(cap(DashboardSpeechOutcome.error)),
        quoteVoiceErrorNote,
      );
    });
  });

  group('QuoteModel', () {
    test('missing or blank author reads as Us', () {
      expect(QuoteModel.fromMap({'text': 'a'}, id: '1').author, 'Us');
      expect(
        QuoteModel.fromMap({'text': 'a', 'author': '  '}, id: '1').author,
        'Us',
      );
      expect(
        QuoteModel.fromMap({'text': 'a', 'author': 'Tom'}, id: '1').author,
        'Tom',
      );
    });

    test('newest first, undated last', () {
      final a = QuoteModel(
        id: 'a',
        text: 'a',
        author: 'x',
        createdAt: DateTime(2026, 1, 1),
      );
      final b = QuoteModel(
        id: 'b',
        text: 'b',
        author: 'x',
        createdAt: DateTime(2026, 6, 1),
      );
      const c = QuoteModel(id: 'c', text: 'c', author: 'x');
      expect(sortQuotesNewestFirst([c, a, b]).map((q) => q.id), [
        'b',
        'a',
        'c',
      ]);
    });

    test('reads a Firestore timestamp', () {
      final q = QuoteModel.fromMap({
        'text': 'a',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
      }, id: '1');
      expect(q.createdAt!.toUtc(), DateTime.utc(2026, 3, 1));
    });
  });

  group('pickDashboardQuote', () {
    test('no custom quotes means no quote (no preset fallback)', () {
      expect(pickDashboardQuote(const [], Random(1)), isNull);
      expect(
        pickDashboardQuote(const [
          QuoteModel(id: 'x', text: '  ', author: 'Us'),
        ], Random(1)),
        isNull,
      );
    });

    test('only ever picks one of the custom quotes', () {
      const mine = [
        QuoteModel(id: '1', text: 'one', author: 'Tom'),
        QuoteModel(id: '2', text: 'two', author: 'Maria'),
      ];
      final random = Random(7);
      for (var i = 0; i < 30; i++) {
        expect(mine.contains(pickDashboardQuote(mine, random)), isTrue);
      }
    });
  });
}
