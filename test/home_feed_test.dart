import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/home_feed_logic.dart';
import 'package:lovehub/services/home_feed_weather.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/home_feed/home_feed_view.dart';

const tom = 'tom-uid';
const maria = 'maria-uid';

Map<String, dynamic> ev(
  String title,
  DateTime start,
  DateTime end, {
  String who = tom,
  String category = 'general',
  bool allDay = false,
  String? status,
}) => {
  'summary': title,
  'start': start,
  'end': end,
  'assignedTo': who,
  'category': category,
  'allDay': allDay,
  'status': ?status,
};

HomeFeedData data(
  DateTime now, {
  List<Map<String, dynamic>> events = const [],
  List<FeedChore> chores = const [],
  List<FeedTask> tasks = const [],
  FeedWeather? weather,
  String? quote,
}) => HomeFeedData(
  now: now,
  myUid: tom,
  names: const {tom: 'Tom', maria: 'Maria'},
  events: events,
  chores: chores,
  tasks: tasks,
  weather: weather,
  quote: quote,
);

void main() {
  group('icons', () {
    test('chores map from title keywords', () {
      expect(
        choreIconFor('Dusting (Window sills, appliances)'),
        Icons.auto_awesome_rounded,
      );
      expect(choreIconFor('Clean Bathroom'), Icons.bathtub_rounded);
      expect(choreIconFor('Hoovering'), Icons.cleaning_services_rounded);
      expect(
        choreIconFor('Check fridge for expired food'),
        Icons.kitchen_rounded,
      );
      expect(choreIconFor('Change Bedding'), Icons.bed_rounded);
      expect(choreIconFor('Change Litter'), Icons.pets_rounded);
      expect(choreIconFor('Water plants'), Icons.local_florist_rounded);
      expect(choreIconFor('Put the bins out'), Icons.delete_rounded);
      expect(choreIconFor('Laundry'), Icons.local_laundry_service_rounded);
      expect(choreIconFor('Dishes'), Icons.wash_rounded);
      expect(choreIconFor('Something odd'), Icons.auto_awesome_outlined);
    });

    test('tasks map from text keywords', () {
      expect(taskIconFor('Book Enzo vet'), Icons.pets_rounded);
      expect(taskIconFor('Pay council tax'), Icons.currency_pound_rounded);
      expect(taskIconFor('Call mum'), Icons.phone_rounded);
      expect(taskIconFor('Book table for Friday'), Icons.event_rounded);
      expect(taskIconFor('Buy new kettle'), Icons.shopping_bag_rounded);
      expect(taskIconFor('Fix the shelf'), Icons.build_rounded);
      expect(taskIconFor('Car MOT'), Icons.directions_car_rounded);
      expect(taskIconFor('Gift for Bella'), Icons.card_giftcard_rounded);
      expect(taskIconFor('Ponder life'), Icons.task_alt_rounded);
    });
  });

  test('responsive columns', () {
    expect(homeFeedColumns(390), 2);
    expect(homeFeedColumns(599), 2);
    expect(homeFeedColumns(844), 3);
    expect(homeFeedColumns(1280), 4);
  });

  test('masonry distribute balances by weight', () {
    final b = FeedMasonryGrid.distribute([3, 1, 1, 1], 2);
    expect(b[0], [0]);
    expect(b[1], [1, 2, 3]);
  });

  test('pack order fills gaps before a full-width card', () {
    // h = half, F = full
    final o = FeedMasonryGrid.packOrder(
      ['h1', 'F1', 'h2', 'h3'],
      (x) => x.startsWith('F'),
      2,
    );
    expect(o, ['h1', 'h2', 'F1', 'h3']);
    expect(
      FeedMasonryGrid.packOrder(['h1', 'F1'], (x) => x.startsWith('F'), 2),
      ['h1', 'F1'],
    );
  });

  group('overnight rule', () {
    final fri = DateTime(2026, 10, 23);
    final bou = ev(
      'C2 — Bou',
      DateTime(2026, 10, 23, 22),
      DateTime(2026, 10, 24, 4, 30),
      category: 'work',
    );
    final late = ev(
      'All-nighter',
      DateTime(2026, 10, 23, 22),
      DateTime(2026, 10, 24, 7),
    );
    test('club night ending before 06:00 stays on the start day', () {
      expect(feedEventsOnDay([bou], fri), [bou]);
      expect(feedEventsOnDay([bou], fri.add(const Duration(days: 1))), isEmpty);
    });
    test('still on next day when it runs past 06:00', () {
      expect(feedEventsOnDay([late], fri.add(const Duration(days: 1))), [late]);
    });
    test('upcoming 48h lists the club night once', () {
      final d = data(DateTime(2026, 10, 23, 12), events: [bou]);
      expect(feedUpcoming48h(d).length, 1);
    });
  });

  group('hero', () {
    test('morning: today agenda + chores left', () {
      final now = DateTime(2026, 10, 19, 8);
      final d = data(
        now,
        events: [
          ev(
            'Janis',
            DateTime(2026, 10, 19, 15),
            DateTime(2026, 10, 19, 16),
            who: 'shared',
          ),
        ],
        chores: const [FeedChore(id: 'a', title: 'Hoovering', assignedTo: tom)],
      );
      final h = buildHeroNow(d);
      expect(h.moment, FeedMoment.morning);
      expect(h.headline, '1 thing on today');
      expect(h.lines.any((l) => l.contains('Janis')), isTrue);
      expect(h.lines.any((l) => l.contains('1 chore left')), isTrue);
    });

    test('up next with countdown within 3 hours', () {
      final now = DateTime(2026, 10, 19, 13);
      final d = data(
        now,
        events: [
          ev('Janis', DateTime(2026, 10, 19, 15), DateTime(2026, 10, 19, 16)),
        ],
      );
      final h = buildHeroNow(d);
      expect(h.eyebrow, 'UP NEXT');
      expect(h.countdown, 'in 2h');
    });

    test('happening now shows time left', () {
      final now = DateTime(2026, 10, 19, 15, 30);
      final d = data(
        now,
        events: [
          ev('Janis', DateTime(2026, 10, 19, 15), DateTime(2026, 10, 19, 16)),
        ],
      );
      final h = buildHeroNow(d);
      expect(h.eyebrow, 'HAPPENING NOW');
      expect(h.countdown, 'ends in 30m');
    });

    test('evening: tonight shift, partner status, tomorrow preview', () {
      final now = DateTime(2026, 10, 23, 18);
      final d = data(
        now,
        events: [
          ev(
            'C2 — Bou',
            DateTime(2026, 10, 23, 22),
            DateTime(2026, 10, 24, 4, 30),
            category: 'work',
            status: 'tentative',
          ),
          ev(
            'Brunch',
            DateTime(2026, 10, 24, 11),
            DateTime(2026, 10, 24, 12),
            who: 'shared',
          ),
        ],
      );
      final h = buildHeroNow(d);
      expect(h.moment, FeedMoment.evening);
      expect(h.lines.first, 'You work tonight 22:00–04:30 · C2 — Bou (?)');
      expect(h.lines, contains('Maria is free tonight'));
      expect(
        h.lines.any((l) => l.startsWith('Tomorrow: 11:00–12:00  Brunch')),
        isTrue,
      );
    });

    test('during one shift, the later shift tonight still shows; meals '
        'do not make anyone busy', () {
      final now = DateTime(2026, 10, 23, 18);
      final d = data(
        now,
        events: [
          ev(
            'C2 — R&B',
            DateTime(2026, 10, 23, 15),
            DateTime(2026, 10, 23, 23, 30),
            category: 'work',
          ),
          ev(
            'C2 — Bou',
            DateTime(2026, 10, 23, 22),
            DateTime(2026, 10, 24, 4, 30),
            category: 'work',
          ),
          ev(
            'Fajitas',
            DateTime(2026, 10, 23, 19),
            DateTime(2026, 10, 23, 20),
            who: 'shared',
            category: 'meal',
          ),
        ],
      );
      final h = buildHeroNow(d);
      expect(h.headline, 'C2 — R&B');
      expect(h.lines, contains('You work tonight 22:00–04:30 · C2 — Bou'));
      expect(h.lines, contains('Maria is free tonight'));
    });

    test('overnight shift carried past midnight is "happening now"', () {
      final now = DateTime(2026, 10, 24, 1);
      final d = data(
        now,
        events: [
          ev(
            'C2 — Bou',
            DateTime(2026, 10, 23, 22),
            DateTime(2026, 10, 24, 4, 30),
            category: 'work',
          ),
        ],
      );
      final h = buildHeroNow(d);
      expect(h.eyebrow, 'HAPPENING NOW');
      expect(h.headline, 'C2 — Bou');
    });
  });

  group('ranking', () {
    final now = DateTime(2026, 10, 19, 9);
    test('empty data shows no cards', () {
      expect(rankFeedCards(data(now)), isEmpty);
    });

    test('overdue tasks and soon birthdays beat filler', () {
      final d = data(
        now,
        tasks: [
          FeedTask(id: '1', text: 'Pay bill', due: DateTime(2026, 10, 17)),
          const FeedTask(id: '2', text: 'Milk', listName: 'Shopping'),
        ],
        events: [
          ev(
            'Bella',
            DateTime(2026, 10, 20),
            DateTime(2026, 10, 20),
            category: 'birthday',
            who: 'shared',
            allDay: true,
          ),
        ],
        quote: 'Tea first',
        weather: const FeedWeather(city: 'Brighton', rainChance: 10),
      );
      final kinds = rankFeedCards(d).map((c) => c.kind).toList();
      expect(kinds.first, FeedCardKind.tasks);
      expect(kinds[1], FeedCardKind.birthdays);
      expect(kinds.last, FeedCardKind.quote);
      expect(kinds, contains(FeedCardKind.shopping));
      expect(kinds, isNot(contains(FeedCardKind.weather)));
    });

    test('rain makes the weather card show up high', () {
      final d = data(
        now,
        weather: const FeedWeather(city: 'Brighton', rainChance: 80),
        quote: 'x',
      );
      expect(rankFeedCards(d).first.kind, FeedCardKind.weather);
    });

    test('tasks order: overdue, today, urgent, later', () {
      final d = data(
        now,
        tasks: [
          const FeedTask(id: 'later', text: 'a'),
          const FeedTask(id: 'urgent', text: 'b', urgent: true),
          FeedTask(id: 'today', text: 'c', due: DateTime(2026, 10, 19)),
          FeedTask(id: 'over', text: 'd', due: DateTime(2026, 10, 10)),
          const FeedTask(id: 'maria', text: 'e', assignedTo: maria),
        ],
      );
      expect(feedRankedTasks(d).map((t) => t.id), [
        'over',
        'today',
        'urgent',
        'later',
      ]);
    });

    test('due labels', () {
      expect(feedDueLabel(DateTime(2026, 10, 17), now), 'Overdue 2d');
      expect(feedDueLabel(DateTime(2026, 10, 19), now), 'Today');
      expect(feedDueLabel(DateTime(2026, 10, 20), now), 'Tomorrow');
    });
  });

  test('weather parse finds rain in the next 12h', () {
    final now = DateTime(2026, 10, 19, 9);
    final w = parseHomeFeedWeather('Brighton', {
      'current': {'temperature_2m': 11.4},
      'hourly': {
        'time': [
          for (var h = 0; h < 24; h++)
            '2026-10-19T${h.toString().padLeft(2, '0')}:00',
        ],
        'precipitation_probability': [
          for (var h = 0; h < 24; h++) h == 15 ? 70 : 10,
        ],
      },
      'daily': {
        'temperature_2m_max': [14],
        'temperature_2m_min': [8],
      },
    }, now)!;
    expect(w.rainChance, 70);
    expect(w.rainFrom, DateTime(2026, 10, 19, 15));
    expect(w.isNotable, isTrue);
  });

  group('widgets', () {
    Future<void> pump(
      WidgetTester t,
      Size size,
      HomeFeedData d, {
      ChoreToggle? onToggle,
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeFeedView(
                data: d,
                palette: HubMemberPalette.fromMembers(const [
                  {'uid': tom, 'name': 'Tom'},
                  {'uid': maria, 'name': 'Maria'},
                ]),
                onToggleChore: onToggle,
              ),
            ),
          ),
        ),
      );
    }

    final now = DateTime(2026, 10, 19, 8);
    final d = data(
      now,
      chores: const [
        FeedChore(
          id: 'c1',
          title: 'Clean Bathroom',
          assignedTo: tom,
          minutes: 25,
        ),
        FeedChore(id: 'c2', title: 'Change Litter', assignedTo: maria),
      ],
      tasks: [
        FeedTask(id: 't1', text: 'Pay bill', due: DateTime(2026, 10, 17)),
      ],
      quote: 'Tea first',
    );

    testWidgets('phone: hero + cards, overdue highlight, no overflow', (
      t,
    ) async {
      await pump(t, const Size(390, 2400), d);
      expect(find.byKey(HomeFeedView.heroKey), findsOneWidget);
      expect(
        find.byKey(HomeFeedView.cardKey(FeedCardKind.chores)),
        findsOneWidget,
      );
      expect(
        find.byKey(HomeFeedView.cardKey(FeedCardKind.tasks)),
        findsOneWidget,
      );
      expect(find.byKey(TaskTile.overdueKey), findsOneWidget);
      expect(
        find.byKey(HomeFeedView.cardKey(FeedCardKind.shopping)),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('tablet landscape renders without overflow', (t) async {
      await pump(t, const Size(1280, 1600), d);
      expect(find.byKey(HomeFeedView.heroKey), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('tap a chore: burst plays and callback fires', (t) async {
      final calls = <(String, bool)>[];
      await pump(
        t,
        const Size(390, 2400),
        d,
        onToggle: (c, v) => calls.add((c.id, v)),
      );
      await t.tap(find.byKey(ChoresCard.tileKey('c1')));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(ChoreTile.burstKey), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byKey(ChoreTile.burstKey), findsNothing);
      expect(calls, [('c1', true)]);
    });

    test('chore order: mine, shared, partner, done last', () {
      final o = ChoresCard.order(const [
        FeedChore(id: 'p', title: 'x', assignedTo: maria),
        FeedChore(id: 'd', title: 'x', assignedTo: tom, done: true),
        FeedChore(id: 's', title: 'x', assignedTo: 'shared'),
        FeedChore(id: 'm', title: 'x', assignedTo: tom),
      ], tom);
      expect(o.map((c) => c.id), ['m', 's', 'p', 'd']);
    });
  });
}
