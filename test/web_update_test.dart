import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/web_build.dart';
import 'package:lovehub/services/web_build_stamp.dart';
import 'package:lovehub/services/web_update_policy.dart';
import 'package:lovehub/widgets/web_update_host.dart';

void main() {
  group('decideWebUpdate', () {
    const attempted = <String>{};

    test('same id does not prompt or reload', () {
      final decision = decideWebUpdate(
        localBuildId: 'abc1234-20260925T120000Z',
        remoteBuildId: 'abc1234-20260925T120000Z',
        isCompactLayout: false,
        sheetOrModalOpen: false,
        alreadyAttemptedIds: attempted,
      );
      expect(decision.action, WebUpdateAction.none);
    });

    test('missing, blank, or empty remote id never reloads', () {
      for (final remote in <String?>[null, '', '   ']) {
        final decision = decideWebUpdate(
          localBuildId: 'local',
          remoteBuildId: remote,
          isCompactLayout: false,
          sheetOrModalOpen: false,
          alreadyAttemptedIds: attempted,
        );
        expect(decision.action, WebUpdateAction.none, reason: '$remote');
      }
    });

    test('dev build without BUILD_ID stays quiet', () {
      final decision = decideWebUpdate(
        localBuildId: '',
        remoteBuildId: 'shipped',
        isCompactLayout: false,
        sheetOrModalOpen: false,
        alreadyAttemptedIds: attempted,
      );
      expect(decision.action, WebUpdateAction.none);
    });

    test('phone shows a prompt for a newer id', () {
      final decision = decideWebUpdate(
        localBuildId: 'old',
        remoteBuildId: ' new ',
        isCompactLayout: true,
        sheetOrModalOpen: false,
        alreadyAttemptedIds: attempted,
      );
      expect(decision.action, WebUpdateAction.prompt);
      expect(decision.remoteBuildId, 'new');
    });

    test('tablet schedules one quiet reload', () {
      final decision = decideWebUpdate(
        localBuildId: 'old',
        remoteBuildId: 'new',
        isCompactLayout: false,
        sheetOrModalOpen: false,
        alreadyAttemptedIds: attempted,
      );
      expect(decision.action, WebUpdateAction.reload);
      expect(decision.remoteBuildId, 'new');
    });

    test('open sheet soft-prompts even on a tablet', () {
      final decision = decideWebUpdate(
        localBuildId: 'old',
        remoteBuildId: 'new',
        isCompactLayout: false,
        sheetOrModalOpen: true,
        alreadyAttemptedIds: attempted,
      );
      expect(decision.action, WebUpdateAction.prompt);
    });

    test('an id already reloaded is not auto-reloaded again', () {
      final decision = decideWebUpdate(
        localBuildId: 'old',
        remoteBuildId: 'new',
        isCompactLayout: false,
        sheetOrModalOpen: false,
        alreadyAttemptedIds: const {'new'},
      );
      expect(decision.action, WebUpdateAction.prompt);
      expect(decision.remoteBuildId, 'new');
    });
  });

  group('attempt store', () {
    test('ignores blank ids and remembers the rest', () {
      final store = MemoryWebUpdateAttemptStore();
      store.remember('  ');
      store.remember('new');
      expect(store.read(), {'new'});
      store.remember('new');
      expect(store.read(), {'new'});
    });
  });

  group('stamp document', () {
    test('commit write targets appMeta/web', () {
      final write = webBuildStampCommitWrite(
        projectId: kLovehubFirebaseProjectId,
        buildId: 'abc1234-20260925T120000Z',
        updatedAt: DateTime.utc(2026, 9, 25, 12),
      );
      final update = write['update'] as Map<String, dynamic>;
      expect(
        update['name'],
        'projects/lovehub-26107/databases/(default)/documents/appMeta/web',
      );
      expect(update['fields'], {
        'buildId': {'stringValue': 'abc1234-20260925T120000Z'},
        'updatedAt': {'timestampValue': '2026-09-25T12:00:00.000Z'},
      });
      expect(write['updateMask'], {
        'fieldPaths': ['buildId', 'updatedAt'],
      });
    });

    test('rejects an empty build id', () {
      expect(
        () => webBuildStampCommitWrite(
          projectId: kLovehubFirebaseProjectId,
          buildId: '  ',
          updatedAt: DateTime.utc(2026, 9, 25),
        ),
        throwsArgumentError,
      );
    });

    test('args take --build-id over the environment', () {
      final command = parseWebBuildStampArgs([
        '--dry-run',
        '--build-id',
        'from-flag',
      ], buildIdFromEnvironment: 'from-env');
      expect(command.buildId, 'from-flag');
      expect(command.dryRun, isTrue);
      expect(command.help, isFalse);
    });

    test('args accept BUILD_ID from the environment', () {
      final command = parseWebBuildStampArgs(const ['--build-id=from-equals']);
      expect(command.buildId, 'from-equals');
    });

    test('args require a build id', () {
      expect(
        () => parseWebBuildStampArgs(const []),
        throwsA(isA<WebBuildStampArgsException>()),
      );
    });

    test('cached CLI access token is used until a minute before expiry', () {
      final expires = DateTime.utc(2026, 9, 25, 13).millisecondsSinceEpoch;
      final tokens = parseFirebaseCliConfig({
        'tokens': {
          'access_token': 'ya29.test',
          'refresh_token': 'refresh',
          'expires_at': expires,
        },
      });
      expect(tokens.refreshToken, 'refresh');
      expect(
        usableFirebaseCliAccessToken(
          tokens,
          now: DateTime.utc(2026, 9, 25, 12),
        ),
        'ya29.test',
      );
      expect(
        usableFirebaseCliAccessToken(
          tokens,
          now: DateTime.utc(2026, 9, 25, 12, 59, 30),
        ),
        isNull,
      );
    });

    test('CLI expiry in seconds is still accepted', () {
      final expiresSeconds =
          DateTime.utc(2026, 9, 25, 13).millisecondsSinceEpoch ~/ 1000;
      final tokens = parseFirebaseCliConfig({
        'tokens': {'access_token': 'ya29.test', 'expires_at': expiresSeconds},
      });
      expect(
        usableFirebaseCliAccessToken(
          tokens,
          now: DateTime.utc(2026, 9, 25, 12),
        ),
        'ya29.test',
      );
    });

    test('buildId field ignores blanks', () {
      expect(buildIdFromFields(null), isNull);
      expect(buildIdFromFields({'buildId': '  '}), isNull);
      expect(buildIdFromFields({'buildId': 'abc'}), 'abc');
    });
  });

  group('WebUpdateHost', () {
    testWidgets('same id shows nothing', (tester) async {
      final harness = await _pump(
        tester,
        size: const Size(390, 844),
        localBuildId: 'abc',
        initialRemote: 'abc',
      );
      expect(find.text('Update ready'), findsNothing);
      expect(harness.reloads, isEmpty);
    });

    testWidgets('phone shows Update ready and reloads only when tapped', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        size: const Size(390, 844),
        localBuildId: 'old',
        initialRemote: 'new',
      );
      expect(find.text('Update ready'), findsOneWidget);
      expect(harness.reloads, isEmpty);
      expect(find.text('home'), findsOneWidget);

      await tester.tap(find.text('home'));
      await tester.pump();
      expect(harness.homeTaps.single, 1);
      expect(harness.reloads, isEmpty);

      await tester.tap(find.byKey(const ValueKey('web-update-ready')));
      await tester.pump();
      expect(harness.reloads, ['reload']);
      expect(harness.attempts.read(), {'new'});
    });

    testWidgets('tablet reloads once for a newer id', (tester) async {
      final harness = await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: 'old',
        initialRemote: 'new',
      );
      expect(harness.reloads, ['reload']);
      expect(harness.attempts.read(), {'new'});

      harness.remote.add('new');
      await tester.pump();
      await tester.pump();
      expect(harness.reloads, ['reload']);
    });

    testWidgets(
      'width at the dashboard breakpoint reloads; just under prompts',
      (tester) async {
        final wide = await _pump(
          tester,
          size: const Size(700, 800),
          localBuildId: 'old',
          initialRemote: 'new',
        );
        expect(wide.reloads, ['reload']);

        final narrow = await _pump(
          tester,
          size: const Size(699, 800),
          localBuildId: 'old',
          initialRemote: 'new',
        );
        expect(find.text('Update ready'), findsOneWidget);
        expect(narrow.reloads, isEmpty);
      },
    );

    testWidgets('loop guard shows the chip instead of reloading again', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: 'old',
        initialRemote: 'new',
        alreadyAttempted: const {'new'},
      );
      expect(harness.reloads, isEmpty);
      expect(find.text('Update ready'), findsOneWidget);
    });

    testWidgets('blank remote id does not reload a tablet', (tester) async {
      final harness = await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: 'old',
        initialRemote: '   ',
      );
      expect(harness.reloads, isEmpty);
      expect(find.text('Update ready'), findsNothing);
    });

    testWidgets('empty local id does not prompt or reload', (tester) async {
      final harness = await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: '',
        initialRemote: 'new',
      );
      expect(harness.reloads, isEmpty);
      expect(find.text('Update ready'), findsNothing);
    });

    testWidgets(
      'open sheet soft-prompts a tablet, then reloads once it closes',
      (tester) async {
        final harness = await _pump(
          tester,
          size: const Size(1024, 768),
          localBuildId: 'old',
          sheetStartsOpen: true,
          initialRemote: 'new',
        );
        expect(find.text('Update ready'), findsOneWidget);
        expect(harness.reloads, isEmpty);

        harness.sheet.setOpen(false);
        await tester.pump();
        await tester.pump();
        expect(harness.reloads, ['reload']);
        expect(harness.attempts.read(), {'new'});
      },
    );

    testWidgets('window focus and resume refetch the stamp', (tester) async {
      final focus = StreamController<void>.broadcast();
      addTearDown(focus.close);
      var fetches = 0;
      final harness = await _pump(
        tester,
        size: const Size(390, 844),
        localBuildId: 'old',
        focusEvents: focus.stream,
        fetchRemote: () async {
          fetches += 1;
          return 'from-focus';
        },
      );
      expect(fetches, 0);

      focus.add(null);
      await tester.pump();
      await tester.pump();
      expect(fetches, 1);
      expect(find.text('Update ready'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(fetches, 2);
      expect(harness.reloads, isEmpty);
    });

    testWidgets('periodic timer refetches without a tap', (tester) async {
      var fetches = 0;
      await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: 'old',
        checkInterval: const Duration(minutes: 10),
        fetchRemote: () async {
          fetches += 1;
          return 'old';
        },
      );
      expect(fetches, 0);
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();
      expect(fetches, 1);
    });

    testWidgets('native host ignores a newer id', (tester) async {
      final harness = await _pump(
        tester,
        size: const Size(1024, 768),
        localBuildId: 'old',
        initialRemote: 'new',
        enabled: false,
      );
      expect(find.text('Update ready'), findsNothing);
      expect(harness.reloads, isEmpty);
    });
  });

  testWidgets('bottom sheet counts as open; a pushed page does not', (
    tester,
  ) async {
    final tracker = WebUpdateSheetTracker();
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(body: Text('page')),
                        ),
                      );
                    },
                    child: const Text('push'),
                  ),
                  TextButton(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => const SizedBox(
                          height: 120,
                          child: Text('Editing dinner'),
                        ),
                      );
                    },
                    child: const Text('edit'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(tracker.isOpen, isFalse);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(tracker.isOpen, isFalse);

    Navigator.of(tester.element(find.text('page'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    expect(tracker.isOpen, isTrue);

    Navigator.of(tester.element(find.text('Editing dinner'))).pop();
    await tester.pumpAndSettle();
    expect(tracker.isOpen, isFalse);
  });
}

class _Harness {
  _Harness({
    required this.remote,
    required this.attempts,
    required this.reloads,
    required this.sheet,
    required this.homeTaps,
  });

  final StreamController<String?> remote;
  final MemoryWebUpdateAttemptStore attempts;
  final List<String> reloads;
  final _FakeSheet sheet;

  /// Incremented when the screen under the chip is tapped.
  final List<int> homeTaps;
}

class _FakeSheet extends ChangeNotifier implements WebUpdateSheetSignal {
  _FakeSheet({bool open = false}) : _open = open;

  bool _open;

  @override
  bool get isOpen => _open;

  void setOpen(bool value) {
    if (_open == value) return;
    _open = value;
    notifyListeners();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required Size size,
  required String localBuildId,
  String? initialRemote,
  Set<String> alreadyAttempted = const {},
  bool sheetStartsOpen = false,
  bool enabled = true,
  Duration? checkInterval,
  Stream<void>? focusEvents,
  Future<String?> Function()? fetchRemote,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final remote = StreamController<String?>.broadcast();
  addTearDown(remote.close);
  final attempts = MemoryWebUpdateAttemptStore();
  for (final id in alreadyAttempted) {
    attempts.remember(id);
  }
  final reloads = <String>[];
  final sheet = _FakeSheet(open: sheetStartsOpen);
  final homeTaps = <int>[0];

  await tester.pumpWidget(
    MaterialApp(
      home: WebUpdateHost(
        enabled: enabled,
        localBuildId: localBuildId,
        sheetOpen: sheet,
        remoteUpdates: remote.stream,
        fetchRemote: fetchRemote,
        focusEvents: focusEvents ?? const Stream<void>.empty(),
        reload: () => reloads.add('reload'),
        attempts: attempts,
        checkInterval: checkInterval,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              onPressed: () => homeTaps[0] += 1,
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  );

  if (initialRemote != null) {
    remote.add(initialRemote);
    await tester.pump();
    await tester.pump();
  }

  return _Harness(
    remote: remote,
    attempts: attempts,
    reloads: reloads,
    sheet: sheet,
    homeTaps: homeTaps,
  );
}
