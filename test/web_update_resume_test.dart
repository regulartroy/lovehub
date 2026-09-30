import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/web_resume.dart';
import 'package:lovehub/services/web_update_policy.dart';
import 'package:lovehub/widgets/build_version_footer.dart';
import 'package:lovehub/widgets/web_update_host.dart';

final _now = DateTime.utc(2026, 10, 1, 12);
String _flag([Duration ago = Duration.zero]) =>
    '${_now.subtract(ago).millisecondsSinceEpoch}';

void main() {
  group('WebResumeSnapshot', () {
    test('round-trips tab, dashboard, and slide', () {
      final snap = WebResumeSnapshot(
        tabIndex: 1,
        dashboardOpen: true,
        dashboardSlide: 3,
        savedAtMs: _now.millisecondsSinceEpoch,
      );
      expect(WebResumeSnapshot.decode(snap.encode(), now: _now), snap);
    });

    test('stale, malformed, or empty values are ignored', () {
      final old = WebResumeSnapshot(
        tabIndex: 2,
        savedAtMs: _now
            .subtract(const Duration(minutes: 6))
            .millisecondsSinceEpoch,
      );
      expect(WebResumeSnapshot.decode(old.encode(), now: _now), isNull);
      for (final raw in [null, '', '{', '[]', '{"tab":1}', '"x"']) {
        expect(WebResumeSnapshot.decode(raw, now: _now), isNull, reason: raw);
      }
    });

    test('out-of-range tab and slide are clamped', () {
      final raw = jsonEncode({
        'tab': 42,
        'dashboard': 'yes',
        'slide': -3,
        'savedAt': _now.millisecondsSinceEpoch,
      });
      final snap = WebResumeSnapshot.decode(raw, now: _now)!;
      expect(snap.tabIndex, kMainTabCount - 1);
      expect(snap.dashboardOpen, isFalse);
      expect(snap.dashboardSlide, 0);
    });

    test('installing flag must be fresh', () {
      expect(isFreshInstallingFlag(_flag(), now: _now), isTrue);
      expect(
        isFreshInstallingFlag(_flag(const Duration(minutes: 4)), now: _now),
        isTrue,
      );
      expect(
        isFreshInstallingFlag(_flag(const Duration(minutes: 6)), now: _now),
        isFalse,
      );
      expect(isFreshInstallingFlag(null, now: _now), isFalse);
      expect(isFreshInstallingFlag('1', now: _now), isFalse);
      expect(isFreshInstallingFlag('soon', now: _now), isFalse);
    });
  });

  group('WebResumeController', () {
    test('cold start: no flag means no splash and nothing to restore', () {
      final c = WebResumeController()
        ..boot(installingFlag: null, resumeJson: null, now: _now);
      expect(c.resumingFromUpdate, isFalse);
      expect(c.ready, isTrue);
      expect(c.pending, isNull);
    });

    test('a resume without the installing flag is not restored', () {
      final json = WebResumeSnapshot(
        tabIndex: 3,
        savedAtMs: _now.millisecondsSinceEpoch,
      ).encode();
      final c = WebResumeController()
        ..boot(installingFlag: null, resumeJson: json, now: _now);
      expect(c.pending, isNull);
    });

    test('stale flag from an old tab does not show the splash', () {
      final c = WebResumeController()
        ..boot(
          installingFlag: _flag(const Duration(hours: 1)),
          resumeJson: null,
          now: _now,
        );
      expect(c.resumingFromUpdate, isFalse);
      expect(c.ready, isTrue);
    });

    test('update boot restores once and waits for ready', () {
      final json = WebResumeSnapshot(
        tabIndex: 1,
        dashboardOpen: true,
        dashboardSlide: 4,
        savedAtMs: _now.millisecondsSinceEpoch,
      ).encode();
      final c = WebResumeController()
        ..boot(installingFlag: _flag(), resumeJson: json, now: _now);
      expect(c.resumingFromUpdate, isTrue);
      expect(c.ready, isFalse);
      final first = c.takePending();
      expect(first?.tabIndex, 1);
      expect(first?.dashboardSlide, 4);
      expect(c.takePending(), isNull);

      var notified = 0;
      c.addListener(() => notified += 1);
      c.markReady();
      c.markReady();
      expect(c.ready, isTrue);
      expect(notified, 1);
    });

    test('snapshot follows tab and dashboard slide', () {
      final c = WebResumeController()..setTab(2);
      expect(c.snapshot(now: _now).dashboardOpen, isFalse);
      c.dashboardOpened(0);
      c.dashboardSlideChanged(5);
      final snap = c.snapshot(now: _now);
      expect(snap.tabIndex, 2);
      expect(snap.dashboardOpen, isTrue);
      expect(snap.dashboardSlide, 5);
      c.dashboardClosed();
      expect(c.snapshot(now: _now).dashboardOpen, isFalse);
      expect(c.snapshot(now: _now).dashboardSlide, 0);
    });
  });

  group('update splash', () {
    testWidgets('tablet shows the splash, saves the location, then reloads', (
      tester,
    ) async {
      final resume = WebResumeController()
        ..setTab(0)
        ..dashboardOpened(0)
        ..dashboardSlideChanged(3);
      final h = await _pump(
        tester,
        size: const Size(1024, 768),
        resume: resume,
        splashDelay: const Duration(milliseconds: 900),
      );
      h.remote.add('new');
      await tester.pump();
      await tester.pump();

      expect(find.byType(WebUpdateSplash), findsOneWidget);
      expect(find.text(WebUpdateSplash.text), findsOneWidget);
      expect(h.reloads, isEmpty, reason: 'splash first');
      expect(h.attempts.read(), {'new'}, reason: 'guard saved before reload');
      expect(
        isFreshInstallingFlag(h.handoff.installingFlag, now: DateTime.now()),
        isTrue,
      );
      final saved = WebResumeSnapshot.decode(
        h.handoff.resumeJson,
        now: DateTime.now(),
      )!;
      expect(saved.dashboardOpen, isTrue);
      expect(saved.dashboardSlide, 3);

      await tester.pump(const Duration(milliseconds: 900));
      expect(h.reloads, ['reload']);

      // Another snapshot of the same id must not reload again.
      h.remote.add('new');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(h.reloads, ['reload']);
    });

    testWidgets('phone chip tap uses the same splash and handoff', (
      tester,
    ) async {
      final resume = WebResumeController()..setTab(1);
      final h = await _pump(
        tester,
        size: const Size(390, 844),
        resume: resume,
        splashDelay: const Duration(milliseconds: 900),
      );
      h.remote.add('new');
      await tester.pump();
      await tester.pump();
      expect(find.text('Update ready'), findsOneWidget);
      expect(find.byType(WebUpdateSplash), findsNothing);
      expect(h.handoff.installingFlag, isNull);

      await tester.tap(find.byKey(const ValueKey('web-update-ready')));
      await tester.pump();
      expect(find.byType(WebUpdateSplash), findsOneWidget);
      expect(find.text('Update ready'), findsNothing);
      expect(
        WebResumeSnapshot.decode(
          h.handoff.resumeJson,
          now: DateTime.now(),
        )?.tabIndex,
        1,
      );
      expect(h.reloads, isEmpty);

      await tester.pump(const Duration(milliseconds: 900));
      expect(h.reloads, ['reload']);
    });

    testWidgets('if the browser never reloads, the app and chip come back', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        size: const Size(1024, 768),
        splashDelay: const Duration(milliseconds: 900),
      );
      h.remote.add('new');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(h.reloads, ['reload']);
      expect(find.byType(WebUpdateSplash), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(find.byType(WebUpdateSplash), findsNothing);
      expect(h.handoff.installingFlag, isNull);
      expect(find.text('Update ready'), findsOneWidget);
      expect(h.reloads, ['reload'], reason: 'loop guard still holds');
    });

    testWidgets('after an update reload the splash is up on the first frame '
        'and fades once the screen is ready', (tester) async {
      final resume = WebResumeController()
        ..boot(installingFlag: _flag(), resumeJson: null, now: _now);
      final h = await _pump(
        tester,
        size: const Size(1024, 768),
        resume: resume,
        localBuildId: 'new',
      );
      expect(find.byType(WebUpdateSplash), findsOneWidget);
      h.remote.add('new');
      await tester.pump();
      expect(find.byType(WebUpdateSplash), findsOneWidget);

      resume.markReady();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WebUpdateSplash), findsNothing);
      expect(h.reloads, isEmpty);
    });

    testWidgets('resume splash gives up after the timeout', (tester) async {
      final resume = WebResumeController()
        ..boot(installingFlag: _flag(), resumeJson: null, now: _now);
      await _pump(tester, size: const Size(390, 844), resume: resume);
      expect(find.byType(WebUpdateSplash), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(WebUpdateSplash), findsNothing);
    });

    testWidgets('normal cold start never shows the splash', (tester) async {
      final resume = WebResumeController()
        ..boot(installingFlag: null, resumeJson: null, now: DateTime.now());
      await _pump(tester, size: const Size(1024, 768), resume: resume);
      expect(find.byType(WebUpdateSplash), findsNothing);
    });
  });

  group('version footer', () {
    test('deploy time comes from the build id', () {
      final at = buildIdDeployedAt('01844e0-20260925T231509Z')!;
      expect(at.toUtc(), DateTime.utc(2026, 9, 25, 23, 15, 9));
      expect(buildIdDeployedAt('dev'), isNull);
    });

    testWidgets('matching ids read as up to date', (tester) async {
      final h = await _pump(
        tester,
        size: const Size(390, 844),
        localBuildId: 'abc-20261001T000000Z',
        child: const BuildVersionFooter(),
      );
      expect(find.text('Latest: checking…'), findsOneWidget);
      h.remote.add('abc-20261001T000000Z');
      await tester.pump();
      expect(find.text('Build: abc-20261001T000000Z'), findsOneWidget);
      expect(find.text('Up to date with the latest release'), findsOneWidget);
      expect(find.byKey(const ValueKey('build-version-install')), findsNothing);
    });

    testWidgets('newer stamp offers Install update with the splash', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        size: const Size(390, 844),
        localBuildId: 'old',
        child: const BuildVersionFooter(),
      );
      h.remote.add('new');
      await tester.pump();
      expect(find.text('Build: old'), findsOneWidget);
      expect(find.text('Latest: new'), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('build-version-install')));
      await tester.pump();
      expect(find.byType(WebUpdateSplash), findsOneWidget);
      expect(h.reloads, ['reload']);
    });

    testWidgets('without the host it still shows the compiled id', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BuildVersionFooter(localBuildId: '')),
        ),
      );
      expect(find.text('Build: dev (no BUILD_ID)'), findsOneWidget);
      expect(find.textContaining('Latest'), findsNothing);
    });
  });
}

class _Harness {
  _Harness(this.remote, this.attempts, this.handoff, this.reloads);

  final StreamController<String?> remote;
  final MemoryWebUpdateAttemptStore attempts;
  final MemoryWebUpdateHandoff handoff;
  final List<String> reloads;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required Size size,
  String localBuildId = 'old',
  WebResumeController? resume,
  Duration splashDelay = Duration.zero,
  Widget child = const Center(child: Text('home')),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final remote = StreamController<String?>.broadcast();
  addTearDown(remote.close);
  final attempts = MemoryWebUpdateAttemptStore();
  final handoff = MemoryWebUpdateHandoff();
  final reloads = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      home: WebUpdateHost(
        enabled: true,
        localBuildId: localBuildId,
        remoteUpdates: remote.stream,
        focusEvents: const Stream<void>.empty(),
        reload: () => reloads.add('reload'),
        attempts: attempts,
        handoff: handoff,
        resume: resume ?? WebResumeController(),
        checkInterval: null,
        splashDelay: splashDelay,
        child: Scaffold(body: child),
      ),
    ),
  );
  return _Harness(remote, attempts, handoff, reloads);
}
