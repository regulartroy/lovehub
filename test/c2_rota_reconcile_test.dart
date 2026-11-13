import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/event_import/c2_rota_reconcile.dart';
import 'package:lovehub/event_import/imported_event.dart';
import 'package:lovehub/event_import/london_date.dart';
import 'package:lovehub/services/hub_collection.dart';

void main() {
  final reviewedAt = DateTime.utc(2026, 11, 8, 12);
  const secret = 'feed-token-should-not-leak';

  group('Europe/London', () {
    test('BST starts and ends at 01:00 UTC on the last Sunday', () {
      expect(londonIsBst(DateTime.utc(2026, 3, 29, 0, 30)), isFalse);
      expect(londonIsBst(DateTime.utc(2026, 3, 29, 1)), isTrue);
      expect(londonIsBst(DateTime.utc(2026, 10, 25, 0, 30)), isTrue);
      expect(londonIsBst(DateTime.utc(2026, 10, 25, 1)), isFalse);
      expect(
        londonCivilDate(DateTime.utc(2026, 1, 15, 23, 30)).ymd,
        '2026-01-15',
      );
      expect(
        londonCivilDate(DateTime.utc(2026, 7, 15, 23, 30)).ymd,
        '2026-07-16',
      );
      expect(londonCivilDate(DateTime.utc(2026, 11, 9)).ymd, '2026-11-09');
    });

    test('the reconcile window is prior 14 days through next 90', () {
      final window = londonReconcileWindow(reviewedAt);
      expect(window.start.ymd, '2026-10-25');
      expect(window.end.ymd, '2027-02-06');
      expect(window.contains(LondonDate(2026, 10, 25)), isTrue);
      expect(window.contains(LondonDate(2026, 10, 24)), isFalse);
      expect(window.contains(LondonDate(2027, 2, 6)), isTrue);
      expect(window.contains(LondonDate(2027, 2, 7)), isFalse);
    });
  });

  group('feed parsing', () {
    test('accepts the live row shape', () {
      final parsed = parseC2RotaFeed({
        'generatedAt': '2026-11-08T09:39:00Z',
        'days': [
          {
            'date': '2026-11-15',
            'show': 'MNEK',
            'status': 'cancelled',
            'tom': 'not_working',
            'role': null,
            'loadIn': null,
            'finish': null,
          },
        ],
      });
      final day = parsed.days.single;
      expect(day.date.ymd, '2026-11-15');
      expect(day.show, 'MNEK');
      expect(day.showStatus, C2ShowStatus.cancelled);
      expect(day.tom, C2TomState.notWorking);
      expect(day.role, isNull);
    });

    test(
      'rejects an empty, stale-shaped, or invalid feed before any match',
      () {
        expect(
          () => parseC2RotaFeed({
            'generatedAt': '2026-11-08T09:39:00Z',
            'days': [],
          }),
          throwsA(
            isA<C2RotaFeedException>().having(
              (error) => error.message,
              'message',
              contains('empty'),
            ),
          ),
        );
        expect(
          () => parseC2RotaFeed({
            'days': [_row('2026-11-09', 'Cardinals')],
          }),
          throwsA(isA<C2RotaFeedException>()),
        );
        expect(
          () => parseC2RotaFeed({
            'generatedAt': '2026-11-08T09:39:00Z',
            'days': [
              _row('2026-11-09', 'Cardinals'),
              {
                'date': '2026-11-10',
                'show': 'Mykki Blanco',
                'status': 'on',
                'tom': 'maybe',
                'leak': secret,
              },
            ],
          }),
          throwsA(
            isA<C2RotaFeedException>().having(
              (error) => error.message,
              'message',
              isNot(contains(secret)),
            ),
          ),
        );
        expect(
          () => parseC2RotaFeed({
            'generatedAt': '2026-11-08T09:39:00Z',
            'days': [
              _row('2026-11-12', 'The Allergies', 'undecided'),
              _row('2026-11-12', 'Allergies', 'working'),
            ],
          }),
          throwsA(isA<C2RotaFeedException>()),
        );
        expect(
          () => decodeC2FeedHttpBody(statusCode: 401, body: secret),
          throwsA(
            isA<C2RotaFeedException>().having(
              (error) => error.message,
              'message',
              isNot(contains(secret)),
            ),
          ),
        );
        expect(
          () => decodeC2FeedHttpBody(statusCode: 302, body: ''),
          throwsA(
            isA<C2RotaFeedException>().having(
              (error) => error.message,
              'message',
              contains('redirected'),
            ),
          ),
        );
        expect(
          () => decodeC2FeedHttpBody(
            statusCode: 200,
            body: '<html>$secret</html>',
          ),
          throwsA(
            isA<C2RotaFeedException>().having(
              (error) => error.message,
              'message',
              isNot(contains(secret)),
            ),
          ),
        );
      },
    );

    test('the feed URL cannot carry the bearer token anywhere else', () {
      expect(
        requireC2RotaFeedUri(c2RotaFeedUrl).host,
        contains('cloudfunctions.net'),
      );
      expect(
        () => requireC2RotaFeedUri(
          'http://us-central1-concorde2-e8b96.cloudfunctions.net/tomRotaFeed',
        ),
        throwsA(isA<C2RotaFeedException>()),
      );
      expect(
        () => requireC2RotaFeedUri('https://example.com/tomRotaFeed'),
        throwsA(isA<C2RotaFeedException>()),
      );
      expect(
        () => requireC2RotaFeedUri('$c2RotaFeedUrl?x=1'),
        throwsA(isA<C2RotaFeedException>()),
      );
    });

    test('a token file is parsed without echoing it', () {
      expect(
        parseFeedToken('  Bearer super-secret-token-value  '),
        'super-secret-token-value',
      );
      const pem =
          '-----BEGIN PRIVATE KEY-----\nMIIEsecretvalue\n-----END PRIVATE KEY-----';
      expect(
        () => parseFeedToken(pem),
        throwsA(
          isA<C2RotaFeedException>().having(
            (error) => error.message,
            'message',
            isNot(contains('MIIE')),
          ),
        ),
      );
      expect(
        () => parseFeedToken('{"token":"super-secret-token-value"}'),
        throwsA(isA<C2RotaFeedException>()),
      );
      expect(
        () => parseFeedToken('short'),
        throwsA(isA<C2RotaFeedException>()),
      );
      expect(
        redactSecret(
          'failed super-secret-token-value',
          'super-secret-token-value',
        ),
        'failed [redacted]',
      );
    });

    test('skips empty show off-days and keeps valid rows', () {
      final parsed = parseC2RotaFeed({
        'generatedAt': '2026-11-08T09:39:00Z',
        'days': [
          {
            'date': '2026-11-02',
            'show': '',
            'status': 'on',
            'tom': 'undecided',
          },
          _row('2026-11-09', 'Cardinals', 'working'),
          {
            'date': '2026-11-11',
            'show': '   ',
            'status': 'on',
            'tom': 'undecided',
          },
        ],
      });
      expect(parsed.days.map((day) => day.show), ['Cardinals']);
      expect(parsed.warnings, hasLength(2));
      expect(parsed.warnings.first, contains('empty show'));
      expect(parsed.warnings.first, contains('2026-11-02'));
    });

    test('treats postponed like cancelled and skips unknown status', () {
      final parsed = parseC2RotaFeed({
        'generatedAt': '2026-11-08T09:39:00Z',
        'days': [
          {
            'date': '2026-11-07',
            'show': 'DAY RAVE',
            'status': 'postponed',
            'tom': 'not_working',
          },
          {
            'date': '2026-11-09',
            'show': 'Mystery',
            'status': 'tbc',
            'tom': 'undecided',
          },
          _row('2026-11-15', 'MNEK', 'not_working', 'cancelled'),
        ],
      });
      expect(parsed.days, hasLength(2));
      expect(parsed.days.first.show, 'DAY RAVE');
      expect(parsed.days.first.showStatus, C2ShowStatus.cancelled);
      expect(parsed.days.last.show, 'MNEK');
      expect(parsed.warnings, hasLength(1));
      expect(parsed.warnings.single, contains('unknown status'));
      expect(parsed.warnings.single, contains('tbc'));
    });
  });

  group('8 Nov review', () {
    test(
      'confirms Cardinals, keeps undecided, deletes not-working and cancelled',
      () {
        final plan = _examplePlan(reviewedAt);
        expect(plan.blockReason, isNull);
        expect(plan.outOfScope, 2);
        expect(plan.confirms.map((action) => action.docId), [
          'c2-rota:2026-11-09',
        ]);
        expect(plan.deletes.map((action) => action.docId), [
          'c2-rota:2026-11-13',
          'c2-rota:2026-11-13-junebabies-bar',
          'c2-rota:2026-11-15',
        ]);
        expect(
          plan.actions
              .where((action) => action.kind == C2RotaActionKind.keepTentative)
              .map((action) => action.docId),
          ['c2-rota:2026-11-10', 'c2-rota:2026-11-12'],
        );
        expect(
          plan.actions.map((action) => action.docId),
          isNot(contains('dinner-2026-11-09')),
        );
        expect(
          plan.actions.map((action) => action.docId),
          isNot(contains('seb:2026-11-09-london')),
        );

        final text = renderC2RotaPlan(
          plan,
          hubId: 'pobIb3qupVJudoQGMJjl',
          applying: false,
        );
        expect(text, contains('CONFIRM'));
        expect(text, contains('c2-rota:2026-11-09'));
        expect(text, contains('KEEP'));
        expect(text, contains('c2-rota:2026-11-10'));
        expect(text, contains('nothing written'));
        expect(text, isNot(contains(secret)));
        expect(
          text
              .split('\n')
              .where((line) => line.contains('c2-rota:2026-11-10'))
              .single,
          startsWith('KEEP'),
        );
        expect(
          text
              .split('\n')
              .where((line) => line.contains('c2-rota:2026-11-09'))
              .single,
          contains('tentative -> confirmed'),
        );
        expect(
          text
              .split('\n')
              .where((line) => line.contains('c2-rota:2026-11-15'))
              .single,
          contains('show cancelled'),
        );
      },
    );

    test('the same feed is idempotent after the plan is applied', () {
      final events = _exampleEvents();
      final first = _examplePlan(reviewedAt);
      final removed = first.deletes.map((action) => action.docId).toSet();
      final confirmed = first.confirms.map((action) => action.docId).toSet();
      final second = planC2RotaReconcile(
        feed: _exampleFeed(),
        events: [
          for (final event in events)
            if (!removed.contains(event.docId))
              confirmed.contains(event.docId)
                  ? event.withStatus('confirmed')
                  : event,
        ],
        now: reviewedAt,
      );
      expect(second.confirms, isEmpty);
      expect(second.deletes, isEmpty);
      expect(
        second.actions
            .where((action) => action.docId == 'c2-rota:2026-11-09')
            .single
            .kind,
        C2RotaActionKind.keepConfirmed,
      );
      expect(
        second.actions
            .where((action) => action.docId == 'c2-rota:2026-11-10')
            .single
            .kind,
        C2RotaActionKind.keepTentative,
      );
    });

    test('a missing show is not treated as cancelled', () {
      final plan = planC2RotaReconcile(
        feed: parseC2RotaFeed({
          'generatedAt': '2026-11-08T09:39:00Z',
          'days': [_row('2026-11-09', 'Cardinals', 'working')],
        }),
        events: _exampleEvents(),
        now: reviewedAt,
      );
      expect(plan.confirms.map((action) => action.docId), [
        'c2-rota:2026-11-09',
      ]);
      expect(plan.deletes, isEmpty);
      expect(
        plan.actions
            .where((action) => action.docId == 'c2-rota:2026-11-15')
            .single
            .kind,
        C2RotaActionKind.skip,
      );
    });
  });

  group('matching and protection', () {
    test('date alone does not confirm or delete', () {
      final plan = _plan(
        days: [_row('2026-11-09', 'Cardinals', 'not_working')],
        events: [_show('2026-11-09', 'C2 — Someone Else')],
      );
      expect(plan.deletes, isEmpty);
      expect(plan.confirms, isEmpty);
      expect(
        plan.actions
            .where((action) => action.docId == 'c2-rota:2026-11-09')
            .single
            .kind,
        C2RotaActionKind.skip,
      );
    });

    test('a suffixed id whose title disagrees is left alone', () {
      final plan = _plan(
        days: [_row('2026-11-13', 'Junebabies (Bar)', 'not_working')],
        events: [
          _show(
            '2026-11-13-junebabies-bar',
            'C2 — John Digweed',
            start: '2026-11-13T20:00:00Z',
          ),
        ],
      );
      expect(plan.deletes, isEmpty);
      expect(
        plan.actions.where((action) => action.docId != null).single.kind,
        C2RotaActionKind.skip,
      );
    });

    test('two events for one show are ambiguous and neither is written', () {
      final plan = _plan(
        days: [_row('2026-11-09', 'Cardinals', 'working')],
        events: [
          _show('2026-11-09', 'C2 — Cardinals'),
          _show('2026-11-09-cardinals', 'C2 — Cardinals'),
        ],
      );
      expect(plan.confirms, isEmpty);
      expect(plan.deletes, isEmpty);
      expect(
        plan.actions
            .where((action) => action.docId != null)
            .map((action) => action.kind),
        everyElement(C2RotaActionKind.skip),
      );
    });

    test('one day can confirm one show and delete another', () {
      final plan = _plan(
        days: [
          _row('2026-11-20', 'Alpha', 'working'),
          _row('2026-11-20', 'Beta', 'not_working'),
        ],
        events: [
          _show('2026-11-20', 'C2 — Alpha'),
          _show('2026-11-20-beta', 'C2 — Beta'),
          C2StoredEvent(
            docId: 'manual-alpha',
            summary: 'C2 — Alpha',
            startUtc: DateTime.utc(2026, 11, 20, 19),
            status: 'tentative',
          ),
        ],
      );
      expect(plan.confirms.map((action) => action.docId), [
        'c2-rota:2026-11-20',
      ]);
      expect(plan.deletes.map((action) => action.docId), [
        'c2-rota:2026-11-20-beta',
      ]);
      expect(plan.outOfScope, 1);
      expect(
        plan.actions.map((action) => action.docId),
        isNot(contains('manual-alpha')),
      );
    });

    test('The Allergies matches Allergies on a date-only id', () {
      final plan = _plan(
        days: [_row('2026-11-12', 'Allergies', 'undecided')],
        events: [_show('2026-11-12', 'C2 — The Allergies')],
      );
      expect(plan.actions.single.kind, C2RotaActionKind.keepTentative);
    });

    test('confirmed and legacy events are never deleted or downgraded', () {
      final cancelled = _plan(
        days: [_row('2026-11-15', 'MNEK', 'not_working', 'cancelled')],
        events: [_show('2026-11-15', 'C2 — MNEK', status: 'confirmed')],
      );
      expect(cancelled.deletes, isEmpty);
      expect(cancelled.actions.single.kind, C2RotaActionKind.keepConfirmed);
      expect(cancelled.actions.single.reason, contains('left confirmed'));

      final missing = _plan(
        days: [_row('2026-11-13', 'John Digweed', 'not_working')],
        events: [_show('2026-11-13', 'C2 — John Digweed', status: null)],
      );
      expect(missing.deletes, isEmpty);
      expect(missing.actions.single.kind, C2RotaActionKind.keepConfirmed);

      final undecided = _plan(
        days: [_row('2026-11-10', 'Mykki Blanco', 'undecided')],
        events: [_show('2026-11-10', 'C2 — Mykki Blanco', status: 'CONFIRMED')],
      );
      expect(undecided.actions.single.kind, C2RotaActionKind.keepConfirmed);
      expect(undecided.actions.single.reason, contains('undecided'));
    });

    test(
      'cancelled wins over working, and undecided plus cancelled still deletes',
      () {
        final cancelled = _plan(
          days: [_row('2026-11-15', 'MNEK', 'working', 'cancelled')],
          events: [_show('2026-11-15', 'C2 — MNEK')],
        );
        expect(cancelled.deletes.map((action) => action.docId), [
          'c2-rota:2026-11-15',
        ]);
        expect(cancelled.confirms, isEmpty);

        final undecided = _plan(
          days: [_row('2026-11-15', 'MNEK', 'undecided', 'cancelled')],
          events: [_show('2026-11-15', 'C2 — MNEK')],
        );
        expect(undecided.deletes, hasLength(1));
      },
    );

    test('a London start that disagrees with the id is not deleted', () {
      final plan = _plan(
        days: [_row('2026-11-09', 'Cardinals', 'not_working')],
        events: [
          _show('2026-11-09', 'C2 — Cardinals', start: '2026-11-10T12:00:00Z'),
        ],
      );
      expect(plan.deletes, isEmpty);
      expect(
        plan.actions.where((action) => action.docId != null).single.reason,
        contains('does not match'),
      );
    });

    test('shows outside the window are ignored', () {
      final plan = _plan(
        days: [_row('2026-10-01', 'Old Show', 'not_working')],
        events: [_show('2026-10-01', 'C2 — Old Show')],
      );
      expect(plan.deletes, isEmpty);
      expect(plan.canCommit, isFalse);
      expect(plan.blockReason, contains('no shows inside'));
    });

    test('a hand-made id is out of scope even with source c2-rota', () {
      final plan = _plan(
        days: [_row('2026-11-09', 'Cardinals', 'not_working')],
        events: [
          C2StoredEvent(
            docId: 'abc123',
            source: 'c2-rota',
            externalId: '2026-11-09',
            summary: 'C2 — Cardinals',
            startUtc: DateTime.utc(2026, 11, 9, 19),
            status: 'tentative',
          ),
        ],
      );
      expect(plan.outOfScope, 1);
      expect(plan.deletes, isEmpty);
    });

    test('postponed deletes a tentative show like cancelled', () {
      final plan = _plan(
        days: [
          {
            'date': '2026-11-15',
            'show': 'DAY RAVE',
            'status': 'postponed',
            'tom': 'working',
          },
        ],
        events: [_show('2026-11-15', 'C2 — DAY RAVE')],
      );
      expect(plan.deletes.map((action) => action.docId), [
        'c2-rota:2026-11-15',
      ]);
      expect(plan.deletes.single.reason, 'show cancelled');
    });

    test('does not delete before today but may confirm a past worked show', () {
      final now = DateTime.utc(2026, 11, 10, 12);
      final plan = planC2RotaReconcile(
        feed: parseC2RotaFeed({
          'generatedAt': '2026-11-10T00:00:00Z',
          'days': [
            _row('2026-11-08', 'Holy Fawn', 'not_working'),
            _row('2026-11-09', 'Cardinals', 'working'),
            _row('2026-11-10', 'Mykki Blanco', 'not_working'),
            _row('2026-11-13', 'John Digweed', 'not_working'),
          ],
        }),
        events: [
          _show('2026-11-08', 'C2 — Holy Fawn'),
          _show('2026-11-09', 'C2 — Cardinals'),
          _show('2026-11-10', 'C2 — Mykki Blanco'),
          _show('2026-11-13', 'C2 — John Digweed'),
        ],
        now: now,
      );
      expect(plan.confirms.map((action) => action.docId), [
        'c2-rota:2026-11-09',
      ]);
      expect(plan.deletes.map((action) => action.docId), [
        'c2-rota:2026-11-10',
        'c2-rota:2026-11-13',
      ]);
      final pastKeep = plan.actions.singleWhere(
        (action) => action.docId == 'c2-rota:2026-11-08',
      );
      expect(pastKeep.kind, C2RotaActionKind.keepTentative);
      expect(pastKeep.reason, 'before today; not deleted');
    });

    test('skipped feed rows appear as warnings without blocking the plan', () {
      final plan = _plan(
        days: [
          {
            'date': '2026-11-02',
            'show': '',
            'status': 'on',
            'tom': 'undecided',
          },
          {
            'date': '2026-11-09',
            'show': 'Cardinals',
            'status': 'tbc',
            'tom': 'working',
          },
          _row('2026-11-12', 'The Allergies', 'undecided'),
        ],
        events: [_show('2026-11-12', 'C2 — The Allergies')],
      );
      expect(plan.blockReason, isNull);
      expect(plan.deletes, isEmpty);
      expect(plan.confirms, isEmpty);
      expect(
        plan.actions.where((action) => action.kind == C2RotaActionKind.skip),
        hasLength(2),
      );
      expect(
        plan.actions
            .singleWhere(
              (action) => action.kind == C2RotaActionKind.keepTentative,
            )
            .docId,
        'c2-rota:2026-11-12',
      );
    });

    test('slug helpers', () {
      expect(
        c2CanonicalShowSlug(c2ShowSlug('Junebabies (Bar)')),
        'junebabies-bar',
      );
      expect(c2SummaryShowSlug('C2 — Cardinals'), 'cardinals');
      expect(c2SummaryShowSlug('C2 - Cardinals'), 'cardinals');
      expect(c2IsTentativeStatus(' Tentative '), isTrue);
      expect(c2IsTentativeStatus(null), isFalse);
      expect(c2IsTentativeStatus('confirmed'), isFalse);
    });
  });

  group('bounds, stale feeds, commits, rollback', () {
    test('a stale feed still explains the plan and refuses the batch', () {
      final plan = planC2RotaReconcile(
        feed: parseC2RotaFeed({
          'generatedAt': '2026-11-07T00:00:00Z',
          'days': [_row('2026-11-09', 'Cardinals', 'working')],
        }),
        events: [_show('2026-11-09', 'C2 — Cardinals', snapshot: true)],
        now: reviewedAt,
      );
      expect(plan.confirms, hasLength(1));
      expect(plan.blockReason, contains('stale'));
      expect(plan.canCommit, isFalse);
      expect(
        () => c2RotaCommitWrites(
          projectId: lovehubFirebaseProjectId,
          hubId: 'hub',
          plan: plan,
          auditId: c2RotaAuditId(reviewedAt, plan.planKey),
          appliedAt: reviewedAt,
        ),
        throwsStateError,
      );
    });

    test(
      'more deletes than the cap writes nothing, including the ones inside the cap',
      () {
        final days = [
          for (var i = 0; i < 9; i++)
            _row('2026-11-${16 + i}', 'Show $i', 'not_working'),
        ];
        final events = [
          for (var i = 0; i < 9; i++)
            _show('2026-11-${16 + i}', 'C2 — Show $i', snapshot: true),
        ];
        final plan = planC2RotaReconcile(
          feed: parseC2RotaFeed({
            'generatedAt': '2026-11-08T09:39:00Z',
            'days': days,
          }),
          events: events,
          now: reviewedAt,
          maxDeletes: 8,
        );
        expect(plan.deletes, hasLength(9));
        expect(plan.canCommit, isFalse);
        expect(plan.blockReason, contains('nothing written'));
        expect(
          () => c2RotaCommitWrites(
            projectId: lovehubFirebaseProjectId,
            hubId: 'hub',
            plan: plan,
            auditId: c2RotaAuditId(reviewedAt, plan.planKey),
            appliedAt: reviewedAt,
          ),
          throwsStateError,
        );
      },
    );

    test('too many imported events aborts with no deletes', () {
      final events = [
        for (var i = 0; i < 501; i++)
          _show('2026-11-09-show-$i', 'C2 — Cardinals'),
      ];
      final plan = _plan(
        days: [_row('2026-11-09', 'Cardinals', 'not_working')],
        events: events,
      );
      expect(plan.importedCount, 501);
      expect(plan.deletes, isEmpty);
      expect(plan.blockReason, contains('exceed'));
    });

    test(
      'the 8 Nov batch confirms one field and deletes only the three tentative shows',
      () {
        final events = [
          for (final event in _exampleEvents())
            if (event.source == c2RotaSource)
              C2StoredEvent(
                docId: event.docId,
                source: event.source,
                externalId: event.externalId,
                summary: event.summary,
                startUtc: event.startUtc,
                status: event.status,
                updateTime: '2026-11-08T10:00:00.000000Z',
                restFields: {
                  'summary': {'stringValue': event.summary},
                  'source': {'stringValue': 'c2-rota'},
                  'externalId': {'stringValue': event.externalId},
                  'status': {'stringValue': event.status},
                  'start': {
                    'timestampValue': event.startUtc!.toUtc().toIso8601String(),
                  },
                },
              )
            else
              event,
        ];
        final plan = planC2RotaReconcile(
          feed: _exampleFeed(),
          events: events,
          now: reviewedAt,
        );
        expect(plan.canCommit, isTrue);
        final auditId = c2RotaAuditId(reviewedAt, plan.planKey);
        final writes = c2RotaCommitWrites(
          projectId: lovehubFirebaseProjectId,
          hubId: 'pobIb3qupVJudoQGMJjl',
          plan: plan,
          auditId: auditId,
          appliedAt: reviewedAt,
        );
        expect(writes, hasLength(5));
        final encoded = jsonEncode(writes);
        expect(encoded, isNot(contains(secret)));
        expect(encoded, isNot(contains('dinner-2026-11-09')));
        expect(encoded, isNot(contains('seb:2026-11-09-london')));
        expect(encoded, isNot(contains('c2-rota:2026-11-10')));
        expect(encoded, isNot(contains('c2-rota:2026-11-12')));

        final confirm = writes.singleWhere(
          (write) =>
              '${write['update']?['name']}'.endsWith('c2-rota:2026-11-09'),
        );
        expect(confirm['updateMask'], {
          'fieldPaths': ['status'],
        });
        expect(confirm['update']['fields'], {
          'status': {'stringValue': 'confirmed'},
        });
        expect(confirm['currentDocument'], {
          'updateTime': '2026-11-08T10:00:00.000000Z',
        });
        expect(
          writes
              .where((write) => write.containsKey('delete'))
              .map((write) => '${write['delete']}'.split('/').last),
          [
            'c2-rota:2026-11-13',
            'c2-rota:2026-11-13-junebabies-bar',
            'c2-rota:2026-11-15',
          ],
        );

        final auditFields = writes.last['update']['fields'] as Map;
        final audit = parseC2RotaAuditDocument(
          runId: auditId,
          document: {'fields': auditFields},
        );
        final current = [
          events
              .singleWhere((event) => event.docId == 'c2-rota:2026-11-09')
              .withStatus('confirmed'),
          events.singleWhere((event) => event.docId == 'c2-rota:2026-11-10'),
          events.singleWhere((event) => event.docId == 'c2-rota:2026-11-12'),
        ];
        final rollback = planC2RotaRollback(
          audit: audit,
          currentEvents: current,
        );
        expect(
          rollback.writes.map((action) => '${action.op} ${action.docId}'),
          containsAll([
            'restoreStatus c2-rota:2026-11-09',
            'recreate c2-rota:2026-11-13',
            'recreate c2-rota:2026-11-13-junebabies-bar',
            'recreate c2-rota:2026-11-15',
          ]),
        );
        final rollbackId = c2RotaAuditId(reviewedAt, 'rollback:$auditId');
        final rollbackWrites = c2RollbackCommitWrites(
          projectId: lovehubFirebaseProjectId,
          hubId: 'pobIb3qupVJudoQGMJjl',
          plan: rollback,
          sourceAuditId: auditId,
          rollbackAuditId: rollbackId,
          appliedAt: reviewedAt,
        );
        expect(
          rollbackWrites.every((write) => !write.containsKey('delete')),
          isTrue,
        );
        final restore = rollbackWrites.singleWhere(
          (write) =>
              '${write['update']?['name']}'.endsWith('c2-rota:2026-11-09'),
        );
        expect(restore['update']['fields'], {
          'status': {'stringValue': 'tentative'},
        });
        expect(
          restore['currentDocument']['updateTime'],
          '2026-11-08T10:00:00.000000Z',
        );
        final recreate = rollbackWrites.singleWhere(
          (write) =>
              '${write['update']?['name']}'.endsWith('c2-rota:2026-11-15'),
        );
        expect(recreate['currentDocument'], {'exists': false});
        expect(recreate['update']['fields']['summary'], {
          'stringValue': 'C2 — MNEK',
        });
      },
    );

    test(
      'rollback does not recreate an event that returned or unconfirm one that changed',
      () {
        final audit = C2RotaAudit(
          runId: c2RotaAuditId(reviewedAt, 'confirm:c2-rota:2026-11-09'),
          hubId: 'hub',
          kind: 'c2-rota-reconcile',
          changes: [
            C2AuditChange(
              op: 'confirm',
              docId: 'c2-rota:2026-11-09',
              beforeStatus: 'tentative',
              beforeFields: {
                'source': {'stringValue': 'c2-rota'},
                'externalId': {'stringValue': '2026-11-09'},
              },
            ),
            C2AuditChange(
              op: 'delete',
              docId: 'c2-rota:2026-11-15',
              beforeStatus: 'tentative',
              beforeFields: {
                'source': {'stringValue': 'c2-rota'},
                'externalId': {'stringValue': '2026-11-15'},
                'summary': {'stringValue': 'C2 — MNEK'},
                'status': {'stringValue': 'tentative'},
              },
            ),
          ],
        );
        final plan = planC2RotaRollback(
          audit: audit,
          currentEvents: [
            _show(
              '2026-11-09',
              'C2 — Cardinals',
              status: 'tentative',
              snapshot: true,
            ),
            _show('2026-11-15', 'C2 — MNEK', snapshot: true),
          ],
        );
        expect(plan.writes, isEmpty);
      },
    );

    test('Firestore query rows keep the stable id and updateTime', () {
      final events = c2EventsFromRunQuery([
        {
          'document': {
            'name':
                'projects/lovehub-26107/databases/(default)/documents/$kHubsCollection/pobIb3qupVJudoQGMJjl/events/c2-rota:2026-11-13-junebabies-bar',
            'updateTime': '2026-11-08T10:00:00.123456Z',
            'fields': {
              'source': {'stringValue': 'c2-rota'},
              'externalId': {'stringValue': '2026-11-13-junebabies-bar'},
              'summary': {'stringValue': 'C2 — Junebabies (Bar)'},
              'status': {'stringValue': 'tentative'},
              'start': {'timestampValue': '2026-11-13T20:00:00Z'},
            },
          },
        },
        {'readTime': '2026-11-08T10:00:01Z'},
      ]);
      expect(events.single.docId, 'c2-rota:2026-11-13-junebabies-bar');
      expect(events.single.updateTime, '2026-11-08T10:00:00.123456Z');
      expect(isImportedC2RotaDoc(events.single), isTrue);
    });

    test('retry only transient commit failures', () {
      expect(c2CommitShouldRetry(503, 0), isTrue);
      expect(c2CommitShouldRetry(503, 2), isFalse);
      expect(c2CommitShouldRetry(200, 0), isFalse);
      expect(c2CommitShouldRetry(400, 0), isFalse);
      expect(c2CommitConflict(409, ''), isTrue);
      expect(c2CommitConflict(400, 'FAILED_PRECONDITION'), isTrue);
      expect(c2CommitConflict(400, 'INVALID'), isFalse);
    });
  });

  group('cli args and Application Default Credentials', () {
    test(
      'dry-run is the default and apply cannot use a fixture clock or file',
      () {
        final command = parseC2ReconcileArgs(['--hub', 'pobIb3qupVJudoQGMJjl']);
        expect(command.apply, isFalse);
        expect(command.tokenFile, defaultTomRotaTokenFile);
        expect(command.maxConfirms, c2RotaDefaultMaxConfirms);
        expect(command.maxDeletes, c2RotaDefaultMaxDeletes);

        final fromEnv = parseC2ReconcileArgs(
          const [],
          environment: {'HUB_ID': 'hub-1'},
        );
        expect(fromEnv.hubId, 'hub-1');

        expect(parseC2ReconcileArgs(const ['--help']).help, isTrue);
        expect(
          () => parseC2ReconcileArgs([
            '--hub',
            'hub',
            '--apply',
            '--now',
            '2026-11-08T12:00:00Z',
          ]),
          throwsA(isA<C2RotaArgsException>()),
        );
        expect(
          () => parseC2ReconcileArgs([
            '--hub',
            'hub',
            '--apply',
            '--events-file',
            'events.json',
          ]),
          throwsA(isA<C2RotaArgsException>()),
        );
        expect(
          () => parseC2ReconcileArgs(['--hub', 'hub', '--max-deletes', '41']),
          throwsA(isA<C2RotaArgsException>()),
        );
        expect(
          () => parseC2ReconcileArgs(['--hub', 'a/b']),
          throwsA(isA<C2RotaArgsException>()),
        );
        expect(
          () => parseC2ReconcileArgs([
            '--hub',
            'hub',
            '--rollback',
            'not-an-audit',
          ]),
          throwsA(isA<C2RotaArgsException>()),
        );
      },
    );

    test('missing ADC explains setup and withholds a token', () {
      final message = c2RotaAdcUnavailableMessage(
        'token ya29.secret refresh_token=abc private_key client_secret',
      );
      expect(message, contains('gcloud auth application-default login'));
      expect(message, contains('set-quota-project lovehub-26107'));
      expect(message, isNot(contains('ya29')));
      expect(message, isNot(contains('refresh_token')));
      expect(message, isNot(contains('private_key')));
      expect(message, isNot(contains('client_secret')));
      expect(
        c2RotaAdcUnavailableMessage(
          'Cloud Firestore refused the Application Default Credential (401).',
        ),
        contains('(401)'),
      );
    });

    test('the sync path does not scrape the Firebase CLI credential cache', () {
      expect(
        File('lib/event_import/firebase_cli_auth.dart').existsSync(),
        isFalse,
      );
      final tool = File('tool/reconcile_c2_rota.dart').readAsStringSync();
      for (final forbidden in [
        'firebase-tools.json',
        'configstore',
        'print-access-token',
        'FIREBASE_TOKEN',
        'GOOGLE_ACCESS_TOKEN',
        'firebaseToolsOauth',
        'refresh_token',
        'client_secret',
        '_readCliConfig',
        '_exchangeRefreshToken',
      ]) {
        expect(tool, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(tool, contains('clientViaApplicationDefaultCredentials'));
      expect(
        c2RotaFirestoreScope,
        'https://www.googleapis.com/auth/cloud-platform',
      );
    });
  });
}

Map<String, Object?> _row(
  String date,
  String show, [
  String tom = 'working',
  String status = 'on',
]) {
  return {
    'date': date,
    'show': show,
    'status': status,
    'tom': tom,
    'role': null,
    'loadIn': null,
    'finish': null,
  };
}

C2StoredEvent _show(
  String externalId,
  String summary, {
  String? status = 'tentative',
  String? start,
  bool snapshot = false,
}) {
  final date = externalId.substring(0, 10);
  final startUtc = DateTime.parse(start ?? '${date}T19:00:00Z').toUtc();
  return C2StoredEvent(
    docId: 'c2-rota:$externalId',
    source: 'c2-rota',
    externalId: externalId,
    summary: summary,
    startUtc: startUtc,
    status: status,
    updateTime: snapshot ? '2026-11-08T10:00:00.000000Z' : null,
    restFields: snapshot
        ? {
            'summary': {'stringValue': summary},
            'source': {'stringValue': 'c2-rota'},
            'externalId': {'stringValue': externalId},
            'status': {'stringValue': status},
            'start': {'timestampValue': startUtc.toIso8601String()},
          }
        : null,
  );
}

C2RotaFeed _exampleFeed() {
  return parseC2RotaFeed(
    jsonDecode(File('tool/c2_rota_feed_example.json').readAsStringSync()),
  );
}

List<C2StoredEvent> _exampleEvents() {
  return parseC2EventFixture(
    jsonDecode(File('tool/c2_rota_events_example.json').readAsStringSync()),
  );
}

C2RotaPlan _examplePlan(DateTime now) {
  return planC2RotaReconcile(
    feed: _exampleFeed(),
    events: _exampleEvents(),
    now: now,
  );
}

C2RotaPlan _plan({
  required List<Map<String, Object?>> days,
  required List<C2StoredEvent> events,
}) {
  return planC2RotaReconcile(
    feed: parseC2RotaFeed({
      'generatedAt': '2026-11-08T09:39:00Z',
      'days': days,
    }),
    events: events,
    now: DateTime.utc(2026, 11, 8, 12),
  );
}
