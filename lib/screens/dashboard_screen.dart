import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../widgets/dashboard/dashboard_calendar_overview.dart';
import '../theme/calendar_colors.dart';
import '../widgets/calendar_split_pill.dart';
import '../widgets/dashboard/dashboard_chrome.dart';
import '../widgets/dashboard/dashboard_theme.dart';
import '../services/member_profile.dart';
import 'dashboard/city_weather_card.dart';
import 'dashboard/dashboard_options_screen.dart';
import 'dashboard/dashboard_quotes.dart';
import 'dashboard/dashboard_weather_icons.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.visibleHubs});

  final List<MapEntry<String, dynamic>> visibleHubs;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _DashboardBoot { loading, ready, empty, error }

class _DashboardScreenState extends State<DashboardScreen> {
  final PageController _pageController = PageController();
  final List<StreamSubscription<dynamic>> _subs = [];

  late ConfettiController _confettiController;
  int _birthdaySlideIndex = -1;
  bool _hasBirthdayToday = false;

  List<Map<String, dynamic>> _hubMembers = [];
  HubMemberDirectory? _memberDirectory;
  List<Map<String, dynamic>> _rawEvents = [];
  List<Map<String, dynamic>> _eventsAll = [];
  List<Map<String, dynamic>> _birthdays = [];
  List<QueryDocumentSnapshot> _allTasks = [];
  Map<String, dynamic>? _rotaConfig;

  List<String> _photoUrls = [];
  String? _currentPhotoUrl;

  String _primaryCityName = 'Brighton';
  List<Map<String, dynamic>> _savedCities = [];
  final Map<String, dynamic> _weatherCache = {};
  bool _isLoadingWeather = false;
  String? _weatherError;
  Timer? _weatherUpdateTimer;

  String _quoteText = 'Fetching inspiration...';
  String _quoteAuthor = '';
  Timer? _quoteTimer;
  List<Map<String, String>> _customQuotes = [];

  Timer? _midnightTimer;
  DateTime _currentDay = DateUtils.dateOnly(DateTime.now());

  List<Widget> _slides = [];
  int _weatherSlideIndex = 0;
  Timer? _slideTimer;
  Timer? _controlsHideTimer;
  int _currentPageIndex = 0;
  bool _isPlaying = true;
  bool _showControls = false;
  double _slideDuration = 15.0;
  int _secondsSinceLastSlide = 0;
  DateTime? _resumeAutoPlayAt;
  bool _isAutoAnimating = false;
  int _pausedSeconds = 0;
  double _cachedScreenWidth = 0;

  _DashboardBoot _boot = _DashboardBoot.loading;
  String _bootError = '';

  IconData _birthdayIcon(String seed) {
    const icons = [
      Icons.cake_rounded,
      Icons.celebration_rounded,
      Icons.card_giftcard_rounded,
      Icons.stars_rounded,
      Icons.local_play_rounded,
    ];
    return icons[seed.hashCode.abs() % icons.length];
  }

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 4),
    );
    _memberDirectory = HubMemberDirectory(
      currentUser: FirebaseAuth.instance.currentUser,
      onChanged: (members) {
        if (!mounted) return;
        _hubMembers = members;
        if (_boot == _DashboardBoot.ready) {
          _rebuildSlides(_widthOrDefault);
        }
      },
    );

    if (widget.visibleHubs.isEmpty) {
      _boot = _DashboardBoot.empty;
    } else {
      _initData();
    }

    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateUtils.dateOnly(DateTime.now());
      if (now.isAfter(_currentDay)) {
        _currentDay = now;
        _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
      }
    });
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _slideTimer?.cancel();
    _controlsHideTimer?.cancel();
    _quoteTimer?.cancel();
    _midnightTimer?.cancel();
    _weatherUpdateTimer?.cancel();
    _pageController.dispose();
    _confettiController.dispose();
    _memberDirectory?.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _projectedBirthdays() {
    final virtualEvents = <Map<String, dynamic>>[];
    final currentYear = DateTime.now().year;
    for (final b in _birthdays) {
      final month = b['month'];
      final day = b['day'];
      if (month is! int || day is! int) continue;
      final year = b['year'] as int?;

      for (int y = currentYear - 1; y <= currentYear + 2; y++) {
        final title = year != null ? "${b['name']} (${y - year})" : "${b['name']}";
        final date = DateTime(y, month, day);
        virtualEvents.add({
          'id': 'bday_${b['id']}_$y',
          'summary': title,
          'start': Timestamp.fromDate(date),
          'end': Timestamp.fromDate(date),
          'allDay': true,
          'category': 'birthday',
          'assignedTo': 'shared',
        });
      }
    }
    return virtualEvents;
  }

  bool _eventOverlapsDay(Map<String, dynamic> data, DateTime day) {
    if (data['start'] == null) return false;
    final checkDay = DateUtils.dateOnly(day);
    final DateTime start = (data['start'] as Timestamp).toDate();
    final DateTime end = data['end'] != null
        ? (data['end'] as Timestamp).toDate()
        : start;
    final dayStart = DateUtils.dateOnly(start);
    final dayEnd = DateUtils.dateOnly(end);
    return (checkDay.isAtSameMomentAs(dayStart) || checkDay.isAfter(dayStart)) &&
        (checkDay.isAtSameMomentAs(dayEnd) || checkDay.isBefore(dayEnd));
  }

  Future<void> _initData() async {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _quoteTimer?.cancel();
    _weatherUpdateTimer?.cancel();
    _slideTimer?.cancel();

    final hubId = widget.visibleHubs.first.key;

    try {
      final hubDoc = await FirebaseFirestore.instance.collection('hubs').doc(hubId).get();
      if (!hubDoc.exists) {
        if (!mounted) return;
        setState(() {
          _boot = _DashboardBoot.error;
          _bootError = 'This hub could not be found.';
        });
        return;
      }

      _memberDirectory?.watch(hubId);

      if (!mounted) return;
      _boot = _DashboardBoot.ready;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _boot = _DashboardBoot.error;
        _bootError = 'Could not load your home dashboard.';
      });
      return;
    }

    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('birthdays')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _birthdays = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _eventsAll = [..._rawEvents, ..._projectedBirthdays()];
        _rebuildSlides(_widthOrDefault);
      }, onError: (_) {}),
    );

    final lookBack = DateTime.now().subtract(const Duration(days: 60));
    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('events')
          .where('start', isGreaterThan: Timestamp.fromDate(lookBack))
          .orderBy('start')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _rawEvents = snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _eventsAll = [..._rawEvents, ..._projectedBirthdays()];
        _rebuildSlides(_widthOrDefault);
      }, onError: (_) {}),
    );

    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('items')
          .where('isDone', isEqualTo: false)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _allTasks = snap.docs;
        _rebuildSlides(_widthOrDefault);
      }, onError: (_) {}),
    );

    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('rota_settings')
          .doc('config')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _rotaConfig = snap.data();
        _rebuildSlides(_widthOrDefault);
      }, onError: (_) {}),
    );

    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('quotes')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _customQuotes = snap.docs.map((d) {
          return {
            'text': d['text'] as String? ?? '',
            'author': d['author'] as String? ?? 'Us',
          };
        }).toList();
        _pickRandomQuote();
      }, onError: (_) {}),
    );

    _subs.add(
      FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('photos')
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        _photoUrls = snap.docs
            .map((d) => d.data()['url'] as String?)
            .whereType<String>()
            .where((url) => url.isNotEmpty)
            .toList();
        if (_photoUrls.isEmpty) {
          _currentPhotoUrl = null;
        } else if (_currentPhotoUrl == null ||
            !_photoUrls.contains(_currentPhotoUrl)) {
          _pickRandomPhoto();
        }
        _rebuildSlides(_widthOrDefault);
      }, onError: (_) {}),
    );

    _initWeatherSystem();
    _startTimer();
    _quoteTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _pickRandomQuote();
      _pickRandomPhoto();
    });
    _weatherUpdateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _fetchAllWeather(),
    );
    _rebuildSlides(_widthOrDefault);
  }

  double get _widthOrDefault =>
      _cachedScreenWidth > 0 ? _cachedScreenWidth : 800;

  void _pickRandomQuote() {
    final allQuotes = [...kRelationshipQuotes, ..._customQuotes];
    if (allQuotes.isEmpty) return;
    final random = List.of(allQuotes)..shuffle();
    if (!mounted) return;
    _quoteText = random.first['text']!;
    _quoteAuthor = random.first['author']!;
    _rebuildSlides(_widthOrDefault);
  }

  void _pickRandomPhoto() {
    if (_photoUrls.isEmpty) return;
    final random = List.of(_photoUrls)..shuffle();
    if (!mounted) return;
    _currentPhotoUrl = random.first;
  }

  HubMemberPalette get _memberPalette =>
      HubMemberPalette.fromMembers(_hubMembers);

  Widget _memberAvatar(String uid, {double radius = 14}) {
    final who = _memberPalette.whoColor(uid);
    if (uid == 'shared') {
      return CircleAvatar(
        radius: radius,
        backgroundColor: DashboardTheme.fade(who, 0.28),
        child: Icon(
          Icons.favorite_rounded,
          color: who,
          size: radius * 1.2,
        ),
      );
    }

    final member = _hubMembers.firstWhere(
      (m) => m['uid'] == uid,
      orElse: () => {'name': '?', 'photoURL': ''},
    );
    final photoURL = member['photoURL'] ?? '';
    final name = (member['name'] ?? '?').toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: who,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.85,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (photoURL.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        photoURL,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  Future<void> _initWeatherSystem() async {
    var uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null && _hubMembers.isNotEmpty) uid = _hubMembers.first['uid'];
    if (uid == null) return;

    _subs.add(
      FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((
        snapshot,
      ) {
        if (!mounted) return;
        final data = snapshot.data();
        final rawCities = data?['weatherCities'] ?? [];
        _savedCities = (rawCities as List).isEmpty
            ? [
                {'name': 'Brighton', 'lat': 50.82, 'lng': -0.13},
              ]
            : List<Map<String, dynamic>>.from(rawCities);
        _primaryCityName = data?['primaryCity'] ?? _savedCities.first['name'];
        if (data != null && data.containsKey('dashboardSlideDuration')) {
          _slideDuration = (data['dashboardSlideDuration'] as num).toDouble();
        }
        _fetchAllWeather();
      }, onError: (_) {}),
    );
  }

  Future<void> _fetchAllWeather() async {
    if (_savedCities.isEmpty) return;
    if (mounted) {
      setState(() {
        _isLoadingWeather = true;
        _weatherError = null;
      });
    }
    try {
      for (final city in _savedCities) {
        final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${city['lat']}&longitude=${city['lng']}&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation_probability,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7',
        );
        final response = await http.get(url);
        if (response.statusCode == 200 && mounted) {
          _weatherCache[city['name']] = json.decode(response.body);
        }
      }
    } catch (e) {
      _weatherError = 'Forecast is taking a pause.';
      debugPrint('Weather fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingWeather = false);
        _rebuildSlides(_widthOrDefault);
      }
    }
  }

  Future<void> _setPrimaryCity(String cityName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'primaryCity': cityName,
    }, SetOptions(merge: true));
    if (!mounted) return;
    _primaryCityName = cityName;
    _rebuildSlides(_widthOrDefault);
  }

  Future<void> _deleteCity(String cityName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newCities = List<Map<String, dynamic>>.from(_savedCities)
      ..removeWhere((c) => c['name'] == cityName);
    if (_primaryCityName == cityName && newCities.isNotEmpty) {
      _setPrimaryCity(newCities.first['name']);
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'weatherCities': newCities,
    }, SetOptions(merge: true));
  }

  void _showCitySearchDialog() {
    final searchCtrl = TextEditingController();
    var searchResults = <dynamic>[];
    var isSearching = false;
    String? searchError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: DashboardTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
          ),
          title: const Text('Add city', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _runCitySearch(
                    searchCtrl.text,
                    (fn) => setDialogState(() {
                      fn();
                    }),
                    (results, error, loading) {
                      searchResults = results;
                      searchError = error;
                      isSearching = loading;
                    },
                    () => isSearching,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search (e.g. Manchester)',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: () => _runCitySearch(
                        searchCtrl.text,
                        (fn) => setDialogState(() {
                          fn();
                        }),
                        (results, error, loading) {
                          searchResults = results;
                          searchError = error;
                          isSearching = loading;
                        },
                        () => isSearching,
                      ),
                    ),
                  ),
                ),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(color: DashboardTheme.weather),
                  ),
                if (searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      searchError!,
                      style: const TextStyle(color: DashboardTheme.inkMuted),
                    ),
                  ),
                if (searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      itemBuilder: (context, index) {
                        final city = searchResults[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.place,
                            color: DashboardTheme.weather,
                          ),
                          title: Text(
                            '${city['name']}, ${city['country'] ?? ''}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () async {
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid != null) {
                              final newCities =
                                  List<Map<String, dynamic>>.from(_savedCities);
                              if (!newCities.any((c) => c['name'] == city['name'])) {
                                newCities.add({
                                  'name': city['name'],
                                  'lat': city['latitude'],
                                  'lng': city['longitude'],
                                });
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .set({
                                      'weatherCities': newCities,
                                    }, SetOptions(merge: true));
                              }
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runCitySearch(
    String query,
    void Function(VoidCallback fn) setDialogState,
    void Function(List<dynamic> results, String? error, bool loading) apply,
    bool Function() isSearching,
  ) async {
    if (query.trim().isEmpty || isSearching()) return;
    setDialogState(() => apply(const [], null, true));
    try {
      final res = await http.get(
        Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeQueryComponent(query.trim())}&count=5&language=en&format=json',
        ),
      );
      final results = (json.decode(res.body)['results'] as List<dynamic>?) ?? [];
      setDialogState(
        () => apply(
          results,
          results.isEmpty ? 'No matching cities. Try a different spelling.' : null,
          false,
        ),
      );
    } catch (_) {
      setDialogState(
        () => apply(const [], 'Could not search right now. Try again.', false),
      );
    }
  }

  int? _primaryWeatherCode() {
    final data = _weatherCache[_primaryCityName];
    if (data == null) return null;
    return (data['current']?['weather_code'] as num?)?.toInt();
  }

  String _formatMultiDayTitle(Map<String, dynamic> data, DateTime currentDate) {
    final title = data['summary'] ?? 'Event';
    final start = (data['start'] as Timestamp).toDate();
    final end = data['end'] != null ? (data['end'] as Timestamp).toDate() : start;
    if (!DateUtils.isSameDay(start, end)) {
      final totalDays =
          DateUtils.dateOnly(end).difference(DateUtils.dateOnly(start)).inDays + 1;
      final currentDayNum =
          (DateUtils.dateOnly(currentDate).difference(DateUtils.dateOnly(start)).inDays +
                  1)
              .clamp(1, totalDays);
      return '$title (Day $currentDayNum/$totalDays)';
    }
    return title;
  }

  DashboardMetrics _metricsFor(double width) =>
      DashboardMetrics(Size(width, 800));

  List<Widget> _generateSlides(double screenWidth) {
    final slides = <Widget>[];
    final metrics = _metricsFor(screenWidth);

    slides.add(_buildScheduleSlide(metrics));
    slides.add(
      DashboardCalendarOverviewSlide(
        metrics: metrics,
        events: _eventsAll,
        now: DateTime.now(),
        members: _hubMembers,
      ),
    );

    final nonShopTasks = _allTasks.where((t) {
      final d = t.data() as Map<String, dynamic>;
      return d['listName'] != 'Shopping' && d['status'] != 'pending_acceptance';
    }).toList();
    if (nonShopTasks.isNotEmpty) {
      slides.add(_buildTasksSlide(nonShopTasks, metrics));
    }

    if (_rotaConfig != null && !_rotaConfig!.containsKey('cycleLength')) {
      slides.add(_buildWeeklyChoresSlide(metrics));
    }

    final shopItems = _allTasks
        .where((t) => (t.data() as Map)['listName'] == 'Shopping')
        .toList();
    final urgentShop =
        shopItems.where((t) => (t.data() as Map)['isUrgent'] == true).toList();
    final regularShop =
        shopItems.where((t) => (t.data() as Map)['isUrgent'] != true).toList();

    if (metrics.isCompact) {
      if (urgentShop.isNotEmpty) {
        slides.add(_buildShoppingSlide(urgentShop, regular: const [], metrics: metrics, mobileUrgent: true));
      }
      if (regularShop.isNotEmpty) {
        slides.add(_buildShoppingSlide(const [], regular: regularShop, metrics: metrics, mobileUrgent: false));
      }
    } else if (shopItems.isNotEmpty) {
      slides.add(
        _buildShoppingSlide(urgentShop, regular: regularShop, metrics: metrics),
      );
    }

    final today = DateUtils.dateOnly(DateTime.now());
    final birthdays = _eventsAll.where((d) {
      if ((d['category'] ?? '') != 'birthday') return false;
      final start = (d['start'] as Timestamp).toDate();
      return start.isAfter(DateTime.now().subtract(const Duration(days: 1))) &&
          start.isBefore(DateTime.now().add(const Duration(days: 365)));
    }).toList()
      ..sort(
        (a, b) => (a['start'] as Timestamp).compareTo(b['start'] as Timestamp),
      );
    final topBirthdays = birthdays.take(10).toList();
    _hasBirthdayToday = topBirthdays.any((d) {
      final start = (d['start'] as Timestamp).toDate();
      return DateUtils.dateOnly(start).difference(today).inDays == 0;
    });

    var showBirthdays = false;
    if (topBirthdays.isNotEmpty) {
      final next = (topBirthdays.first['start'] as Timestamp).toDate();
      if (DateUtils.dateOnly(next).difference(today).inDays <= 21) {
        showBirthdays = true;
      }
    }
    if (showBirthdays) {
      _birthdaySlideIndex = slides.length;
      slides.add(_buildBirthdaysSlide(topBirthdays, metrics));
    } else {
      _birthdaySlideIndex = -1;
    }

    slides.add(_buildAffirmationsSlide(metrics));
    _weatherSlideIndex = slides.length;
    slides.add(_buildWeatherSlide(metrics));

    if (_photoUrls.isNotEmpty) {
      slides.add(_buildPhotosSlide(metrics));
    }

    return slides;
  }

  Widget _buildScheduleSlide(DashboardMetrics metrics) {
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.schedule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.calendar_month_rounded,
            tint: DashboardTheme.schedule,
            title: 'SCHEDULE',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: metrics.isCompact
                ? _buildScheduleBox(metrics, startDayOffset: 0, dayCount: 7, large: false)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 60,
                        child: _buildScheduleBox(
                          metrics,
                          startDayOffset: 0,
                          dayCount: 2,
                          large: true,
                        ),
                      ),
                      SizedBox(width: metrics.isWide ? 32 : 24),
                      Expanded(
                        flex: 40,
                        child: _buildScheduleBox(
                          metrics,
                          startDayOffset: 2,
                          dayCount: 5,
                          large: false,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleBox(
    DashboardMetrics metrics, {
    required int startDayOffset,
    required int dayCount,
    required bool large,
  }) {
    final todayStart = DateUtils.dateOnly(DateTime.now());
    return DashboardGlassCard(
      tint: DashboardTheme.schedule,
      padding: EdgeInsets.all(large ? 28 : 20),
      child: ListView(
        children: List.generate(dayCount, (index) {
          final i = startDayOffset + index;
          final checkDate = todayStart.add(Duration(days: i));
          final events = _eventsAll.where((d) {
            if (!_eventOverlapsDay(d, checkDate)) return false;
            if (i == 0 && d['allDay'] != true) {
              final start = (d['start'] as Timestamp).toDate();
              final end = d['end'] != null
                  ? (d['end'] as Timestamp).toDate()
                  : start;
              if (end.isBefore(DateTime.now())) return false;
            }
            return true;
          }).toList()
            ..sort(
              (a, b) =>
                  (a['start'] as Timestamp).compareTo(b['start'] as Timestamp),
            );

          var emptyText = 'Nothing planned';
          if (events.isEmpty && i == 0) {
            final hadAny = _eventsAll.any((d) => _eventOverlapsDay(d, checkDate));
            if (hadAny) emptyText = 'All done for today';
          }

          final label = i == 0
              ? 'TODAY'
              : i == 1
              ? 'TOMORROW'
              : DateFormat('EEE d MMM').format(checkDate).toUpperCase();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: index == 0 ? 0 : (large ? 24 : 18),
                  bottom: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: i == 0
                            ? Colors.greenAccent
                            : const Color(0xFF8FB0C8),
                        fontSize: large ? 22 : 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Divider(
                        color: DashboardTheme.fade(
                          i == 0 ? Colors.greenAccent : Colors.white,
                          0.2,
                        ),
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (events.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    emptyText,
                    style: TextStyle(
                      color: DashboardTheme.inkFaint,
                      fontSize: large ? 20 : 17,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                ...events.map((d) => _eventRow(d, checkDate, large)),
            ],
          );
        }),
      ),
    );
  }

  Widget _eventRow(
    Map<String, dynamic> data,
    DateTime checkDate,
    bool large,
  ) {
    final isMeal = data['category'] == 'meal';
    final category = data['category'] ?? 'general';
    final ownerId = data['assignedTo'] ?? 'shared';
    final isAllDay = data['allDay'] ?? false;
    final start = (data['start'] as Timestamp).toDate();
    final timeStr = isAllDay ? 'All day' : DateFormat('HH:mm').format(start);

    final style = CalendarColors.resolve(
      assignedTo: ownerId.toString(),
      category: category.toString(),
      palette: _memberPalette,
    );

    return CalendarSplitPill(
      style: style,
      title: _formatMultiDayTitle(data, checkDate),
      subtitle: timeStr,
      density: large
          ? CalendarSplitPillDensity.comfortable
          : CalendarSplitPillDensity.regular,
      margin: const EdgeInsets.only(bottom: 12),
      leading: _memberAvatar(ownerId, radius: large ? 16 : 13),
      trailing: category == 'birthday'
          ? Icon(
              _birthdayIcon(data['id'] ?? data['summary']),
              size: large ? 20 : 16,
            )
          : isMeal
          ? Icon(Icons.restaurant, size: large ? 20 : 16)
          : null,
    );
  }

  Widget _buildSmartMasonry({
    required DashboardMetrics metrics,
    required List<Map<String, dynamic>> groups,
  }) {
    if (groups.isEmpty) return const SizedBox.shrink();

    if (metrics.isCompact) {
      return ListView(
        children: groups
            .map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: g['widget'] as Widget,
              ),
            )
            .toList(),
      );
    }

    groups.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    final columnCount = metrics.isWide && groups.length >= 3 ? 3 : 2;
    final columns = List.generate(columnCount, (_) => <Widget>[]);
    for (var i = 0; i < groups.length; i++) {
      columns[i % columnCount].add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: groups[i]['widget'] as Widget,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) const SizedBox(width: 20),
          Expanded(child: ListView(children: columns[i])),
        ],
      ],
    );
  }

  Widget _buildUserGroupBox({
    required String ownerId,
    required List<dynamic> items,
    required Color themeColor,
    required bool isTasks,
    required DashboardMetrics metrics,
    List<String>? completedChores,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    var title = 'SHARED';
    if (ownerId != 'shared') {
      final member = _hubMembers.firstWhere(
        (m) => m['uid'] == ownerId,
        orElse: () => {'name': 'Partner'},
      );
      title = member['name'].toString().toUpperCase();
    }

    return DashboardGlassCard(
      tint: themeColor,
      padding: EdgeInsets.all(metrics.isCompact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _memberAvatar(ownerId, radius: metrics.isCompact ? 18 : 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: themeColor,
                    fontSize: metrics.isCompact ? 18 : 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...items.map((item) {
            if (isTasks) {
              final d = (item as QueryDocumentSnapshot).data()
                  as Map<String, dynamic>;
              final isUrgent = d['isUrgent'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isUrgent ? Icons.error_rounded : Icons.circle_outlined,
                      color: isUrgent ? Colors.redAccent : Colors.white38,
                      size: metrics.isCompact ? 22 : 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        d['text'] ?? '',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.bodySize,
                          fontWeight: isUrgent ? FontWeight.w700 : FontWeight.w400,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final chore = item as Map<String, dynamic>;
            final isDone = completedChores?.contains(chore['id']) ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: isDone ? Colors.green : Colors.white38,
                    size: metrics.isCompact ? 22 : 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chore['title'] ?? '',
                      style: TextStyle(
                        color: isDone ? Colors.white38 : Colors.white,
                        fontSize: metrics.bodySize,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${chore['effortMinutes']}m',
                    style: TextStyle(
                      color: isDone ? Colors.white24 : themeColor,
                      fontSize: metrics.isCompact ? 16 : 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTasksSlide(
    List<QueryDocumentSnapshot> tasks,
    DashboardMetrics metrics,
  ) {
    final grouped = <String, List<QueryDocumentSnapshot>>{'shared': []};
    for (final member in _hubMembers) {
      grouped[member['uid']] = [];
    }
    for (final task in tasks) {
      final owner =
          (task.data() as Map<String, dynamic>)['assignedTo'] ?? 'shared';
      grouped.putIfAbsent(owner, () => []).add(task);
    }

    final layoutGroups = <Map<String, dynamic>>[];
    grouped.forEach((ownerId, items) {
      if (items.isEmpty) return;
      items.sort((a, b) {
        final aUrgent = (a.data() as Map)['isUrgent'] == true;
        final bUrgent = (b.data() as Map)['isUrgent'] == true;
        if (aUrgent && !bUrgent) return -1;
        if (!aUrgent && bUrgent) return 1;
        return 0;
      });
      layoutGroups.add({
        'id': ownerId,
        'count': items.length,
        'widget': _buildUserGroupBox(
          ownerId: ownerId,
          items: items,
          themeColor: DashboardTheme.tasks,
          isTasks: true,
          metrics: metrics,
        ),
      });
    });

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.tasks,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.task_alt_rounded,
            tint: DashboardTheme.tasks,
            title: 'TASKS',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _buildSmartMasonry(metrics: metrics, groups: layoutGroups),
          ),
        ],
      ),
    );
  }

  Widget _rotaEmptySlide(DashboardMetrics metrics, String message) {
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.rota,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.cleaning_services_rounded,
            tint: DashboardTheme.rota,
            title: 'HOUSE ROTA',
          ),
          Expanded(
            child: DashboardEmptyState(
              icon: Icons.cleaning_services_outlined,
              tint: DashboardTheme.rota,
              title: 'A quiet week',
              message: message,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChoresSlide(DashboardMetrics metrics) {
    if (_rotaConfig == null || _rotaConfig!['anchorDate'] == null) {
      return _rotaEmptySlide(
        metrics,
        'The rota is not set up yet. Add chores from the Rota tab.',
      );
    }

    final anchorDate = (_rotaConfig!['anchorDate'] as Timestamp).toDate();
    final daysSince = DateUtils.dateOnly(DateTime.now())
        .difference(DateUtils.dateOnly(anchorDate))
        .inDays;
    if (daysSince < 0) {
      return _rotaEmptySlide(
        metrics,
        'This week’s rota has not started yet.',
      );
    }

    final absoluteWeekNum = (daysSince ~/ 7) + 1;
    final currentCycleWeek = ((daysSince ~/ 7) % 8) + 1;
    final startOfWeek = DateUtils.dateOnly(
      anchorDate,
    ).add(Duration(days: (absoluteWeekNum - 1) * 7));
    final weekId = DateFormat('yyyy-MM-dd').format(startOfWeek);
    final blueprint = _rotaConfig!['blueprint'] as Map<String, dynamic>? ?? {};
    final weekChores = List<Map<String, dynamic>>.from(
      blueprint[currentCycleWeek.toString()] ?? [],
    );
    if (weekChores.isEmpty) {
      return _rotaEmptySlide(
        metrics,
        'No chores on the rota this week. Enjoy the calm.',
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hubs')
          .doc(widget.visibleHubs.first.key)
          .collection('rota_logs')
          .doc('week_$weekId')
          .snapshots(),
      builder: (context, snapshot) {
        var completed = <String>[];
        if (snapshot.hasData && snapshot.data!.exists) {
          completed = List<String>.from(
            (snapshot.data!.data() as Map<String, dynamic>)['completed'] ?? [],
          );
        }
        final progress = completed.length / weekChores.length;

        final grouped = <String, List<Map<String, dynamic>>>{'shared': []};
        for (final member in _hubMembers) {
          grouped[member['uid']] = [];
        }
        for (final chore in weekChores) {
          final owner = chore['assignedTo'] ?? 'shared';
          grouped.putIfAbsent(owner, () => []).add(chore);
        }

        final layoutGroups = <Map<String, dynamic>>[];
        grouped.forEach((ownerId, items) {
          if (items.isEmpty) return;
          items.sort((a, b) {
            final aDone = completed.contains(a['id']);
            final bDone = completed.contains(b['id']);
            if (aDone && !bDone) return 1;
            if (!aDone && bDone) return -1;
            return 0;
          });
          layoutGroups.add({
            'id': ownerId,
            'count': items.length,
            'widget': _buildUserGroupBox(
              ownerId: ownerId,
              items: items,
              themeColor: DashboardTheme.rota,
              isTasks: false,
              completedChores: completed,
              metrics: metrics,
            ),
          });
        });

        return DashboardSlide(
          metrics: metrics,
          tint: DashboardTheme.rota,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(
                metrics: metrics,
                icon: Icons.cleaning_services_rounded,
                tint: DashboardTheme.rota,
                title: 'HOUSE ROTA',
                trailing: SizedBox(
                  width: metrics.isCompact ? 48 : 56,
                  height: metrics.isCompact ? 48 : 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        color: DashboardTheme.rota,
                        backgroundColor: Colors.white10,
                        strokeWidth: 7,
                      ),
                      Center(
                        child: Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: metrics.isCompact ? 11 : 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _buildSmartMasonry(
                  metrics: metrics,
                  groups: layoutGroups,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShoppingSlide(
    List<QueryDocumentSnapshot> urgent, {
    required List<QueryDocumentSnapshot> regular,
    required DashboardMetrics metrics,
    bool? mobileUrgent,
  }) {
    final isMobileUrgent = mobileUrgent == true;
    final isMobileRegular = mobileUrgent == false;
    final title = isMobileUrgent
        ? 'PRIORITY SHOPPING'
        : (isMobileRegular ? 'SHOPPING' : 'SHOPPING');

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.shopping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.shopping_cart_rounded,
            tint: DashboardTheme.shopping,
            title: title,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: metrics.isCompact
                ? DashboardGlassCard(
                    tint: isMobileUrgent
                        ? DashboardTheme.shoppingUrgent
                        : DashboardTheme.shopping,
                    child: _shopList(
                      isMobileUrgent ? urgent : regular,
                      isUrgent: isMobileUrgent,
                      metrics: metrics,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (urgent.isNotEmpty)
                        Expanded(
                          child: _shopColumn(
                            'PRIORITY',
                            urgent,
                            urgent: true,
                            metrics: metrics,
                          ),
                        ),
                      if (urgent.isNotEmpty && regular.isNotEmpty)
                        const SizedBox(width: 20),
                      if (regular.isNotEmpty)
                        Expanded(
                          child: _shopColumn(
                            'REGULAR',
                            regular,
                            urgent: false,
                            metrics: metrics,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _shopColumn(
    String title,
    List<QueryDocumentSnapshot> items, {
    required bool urgent,
    required DashboardMetrics metrics,
  }) {
    return DashboardGlassCard(
      tint: urgent ? DashboardTheme.shoppingUrgent : DashboardTheme.shopping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: urgent ? DashboardTheme.shoppingUrgent : Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _shopList(items, isUrgent: urgent, metrics: metrics),
          ),
        ],
      ),
    );
  }

  Widget _shopList(
    List<QueryDocumentSnapshot> items, {
    required bool isUrgent,
    required DashboardMetrics metrics,
  }) {
    if (items.isEmpty) {
      return const DashboardEmptyState(
        icon: Icons.shopping_basket_outlined,
        tint: DashboardTheme.shopping,
        title: 'List is clear',
        message: 'Nothing waiting on this shopping list.',
      );
    }
    return ListView(
      children: items.map((t) {
        final data = t.data() as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                isUrgent ? Icons.error_rounded : Icons.circle_outlined,
                color: isUrgent ? Colors.redAccent : Colors.white38,
                size: metrics.isCompact ? 22 : 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  data['text'] ?? '',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.isCompact ? 20 : 26,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBirthdaysSlide(
    List<Map<String, dynamic>> birthdays,
    DashboardMetrics metrics,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.accent,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2D0A18), Color(0xFF0A0A2E)],
      ),
      child: Column(
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.cake_rounded,
            tint: DashboardTheme.accent,
            title: 'BIRTHDAYS',
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: SizedBox(
                width: metrics.isCompact ? double.infinity : 720,
                child: ListView.builder(
                  itemCount: birthdays.length,
                  itemBuilder: (context, i) {
                    final data = birthdays[i];
                    final start = (data['start'] as Timestamp).toDate();
                    final daysUntil =
                        DateUtils.dateOnly(start).difference(today).inDays;
                    final isToday = daysUntil == 0;
                    final isImminent = daysUntil > 0 && daysUntil <= 3;
                    final isSoon = daysUntil > 0 && daysUntil <= 14;
                    final fade = (isToday || isSoon)
                        ? 0.0
                        : (birthdays.length > 1
                              ? (i / (birthdays.length - 1))
                              : 0.0);
                    final scale = isToday
                        ? 1.12
                        : (isImminent ? 1.06 : (1.0 - (fade * 0.22)));

                    return Container(
                      margin: EdgeInsets.only(bottom: 12 * scale),
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.isCompact ? 16 : 22,
                        vertical: (metrics.isCompact ? 12 : 14) * scale,
                      ),
                      decoration: BoxDecoration(
                        color: isToday
                            ? DashboardTheme.fade(DashboardTheme.accent, 0.18)
                            : DashboardTheme.fade(Colors.white, 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isToday
                              ? DashboardTheme.accent
                              : DashboardTheme.fade(
                                  DashboardTheme.accent,
                                  isImminent ? 0.7 : (isSoon ? 0.4 : 0.16),
                                ),
                          width: isToday ? 2 : 1,
                        ),
                        boxShadow: isToday
                            ? [
                                BoxShadow(
                                  color: DashboardTheme.fade(
                                    DashboardTheme.accent,
                                    0.22,
                                  ),
                                  blurRadius: 16,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _birthdayIcon(data['id'] ?? data['summary']),
                            color: isToday
                                ? Colors.white
                                : DashboardTheme.accent,
                            size: 20 * scale,
                          ),
                          SizedBox(width: 12 * scale),
                          Expanded(
                            child: Text(
                              '${data['summary']}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: (metrics.isCompact ? 18 : 22) * scale,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: DashboardTheme.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'TODAY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                            )
                          else if (isSoon)
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isImminent
                                    ? DashboardTheme.accent
                                    : DashboardTheme.fade(
                                        DashboardTheme.accent,
                                        0.16,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                daysUntil == 1
                                    ? 'Tomorrow'
                                    : 'In $daysUntil days',
                                style: TextStyle(
                                  color: isImminent
                                      ? Colors.white
                                      : DashboardTheme.accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (!isToday)
                            Text(
                              DateFormat('d MMM').format(start),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: (metrics.isCompact ? 15 : 17) * scale,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddQuoteDialog() {
    final textCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: DashboardTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
          ),
          title: const Text(
            'Add a quote',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'A quote, inside joke, or affirmation…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Author (leave blank for 'Us')",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: DashboardTheme.accent),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (textCtrl.text.trim().isEmpty) return;
                      setDialogState(() => isSaving = true);
                      final hubId = widget.visibleHubs.first.key;
                      await FirebaseFirestore.instance
                          .collection('hubs')
                          .doc(hubId)
                          .collection('quotes')
                          .add({
                            'text': textCtrl.text.trim(),
                            'author': authorCtrl.text.trim().isEmpty
                                ? 'Us'
                                : authorCtrl.text.trim(),
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _pickRandomQuote();
                      _showControlsOverlay();
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save quote',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAffirmationsSlide(DashboardMetrics metrics) {
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.accent,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.isCompact ? 28 : 72,
        vertical: metrics.slidePadTop,
      ),
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    color: DashboardTheme.accent,
                    size: metrics.isCompact ? 40 : 56,
                  ),
                  const SizedBox(height: 24),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: metrics.size.width,
                      ),
                      child: Text(
                        '"$_quoteText"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.quoteSize,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.4,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  if (_quoteAuthor.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text(
                      '— $_quoteAuthor',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DashboardTheme.fade(DashboardTheme.accent, 0.85),
                        fontSize: metrics.isCompact ? 16 : 20,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(
                Icons.add_comment_rounded,
                color: Colors.white24,
                size: 32,
              ),
              onPressed: _showAddQuoteDialog,
              tooltip: 'Add a quote',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherSlide(DashboardMetrics metrics) {
    final cards = _savedCities
        .map((city) {
          final name = city['name'] as String? ?? '';
          final data = _weatherCache[name];
          if (data == null) return null;
          return CityWeatherCard(
            name: name,
            isPrimary: name == _primaryCityName,
            data: data,
            onSetPrimary: () => _setPrimaryCity(name),
            onDelete: () => _deleteCity(name),
          );
        })
        .whereType<Widget>()
        .toList();

    Widget body;
    if (_isLoadingWeather && cards.isEmpty) {
      body = const DashboardLoadingView(label: 'Fetching the forecast…');
    } else if (cards.isEmpty) {
      body = DashboardEmptyState(
        icon: Icons.wb_cloudy_outlined,
        tint: DashboardTheme.weather,
        title: _weatherError ?? 'Forecast unavailable',
        message: 'Add a city, or try again in a moment.',
        action: TextButton.icon(
          onPressed: _showCitySearchDialog,
          icon: const Icon(Icons.add_rounded, color: DashboardTheme.weather),
          label: const Text(
            'Add a city',
            style: TextStyle(color: DashboardTheme.weather),
          ),
        ),
      );
    } else {
      body = ListView(children: cards);
    }

    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.weather,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.wb_cloudy_rounded,
            tint: DashboardTheme.weather,
            title: 'FORECAST',
            trailing: TextButton.icon(
              onPressed: _showCitySearchDialog,
              icon: const Icon(Icons.add_rounded, color: Colors.white38, size: 18),
              label: const Text(
                'Add city',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildPhotosSlide(DashboardMetrics metrics) {
    return DashboardSlide(
      metrics: metrics,
      tint: DashboardTheme.photos,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionHeader(
            metrics: metrics,
            icon: Icons.photo_library_rounded,
            tint: DashboardTheme.photos,
            title: 'MEMORIES',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DashboardTheme.radiusLg),
                child: _currentPhotoUrl == null
                    ? const DashboardEmptyState(
                        icon: Icons.photo_outlined,
                        tint: DashboardTheme.photos,
                        title: 'No photo yet',
                        message: 'Add a picture in Gallery to fill this slide.',
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            _currentPhotoUrl!,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const DashboardLoadingView(
                                label: 'Loading a memory…',
                              );
                            },
                            errorBuilder: (context, error, stack) {
                              return const DashboardEmptyState(
                                icon: Icons.broken_image_outlined,
                                tint: DashboardTheme.photos,
                                title: 'Photo could not load',
                                message:
                                    'The next memory will appear on the next refresh.',
                              );
                            },
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(metrics.isCompact ? 16 : 24),
                              child: Icon(
                                Icons.photo_camera_back,
                                color: Colors.white54,
                                size: metrics.isCompact ? 22 : 28,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DashboardMetrics metrics) {
    final currentCode = _primaryWeatherCode();
    final weather = _weatherCache[_primaryCityName];
    final temp = (weather?['current']?['temperature_2m'] as num?)?.toDouble();
    final isDay = (weather?['current']?['is_day'] as num?)?.toInt() ?? 1;

    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = DateTime.now();
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.headerPadH,
              metrics.headerPadTop,
              metrics.headerPadH,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(now),
                            style: TextStyle(
                              fontSize: metrics.clockSize,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.0,
                              letterSpacing: -1,
                            ),
                          ),
                          if (!metrics.isCompact) ...[
                            const SizedBox(width: 2),
                            Text(
                              DateFormat(':ss').format(now),
                              style: TextStyle(
                                fontSize: metrics.secondsSize,
                                fontWeight: FontWeight.w300,
                                color: DashboardTheme.fade(Colors.white, 0.35),
                                height: 1.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
                        style: TextStyle(
                          color: DashboardTheme.accent,
                          fontSize: metrics.dateSize,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    if (_slides.isEmpty || !_pageController.hasClients) return;
                    final currentRaw = _pageController.page?.round() ?? 0;
                    final currentMod = currentRaw % _slides.length;
                    final distance = _weatherSlideIndex - currentMod;
                    _pageController.animateToPage(
                      currentRaw + distance,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.isCompact ? 10 : 14,
                      vertical: metrics.isCompact ? 8 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: DashboardTheme.fade(Colors.white, 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        currentCode != null
                            ? DashboardWeatherIcon(
                                code: currentCode,
                                isDay: isDay,
                                size: metrics.isCompact ? 22 : 26,
                              )
                            : Icon(
                                Icons.cloud_rounded,
                                color: Colors.white38,
                                size: metrics.isCompact ? 22 : 26,
                              ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              temp != null ? '${temp.round()}°' : '--°',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: metrics.isCompact ? 20 : 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _primaryCityName,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showControlsOverlay() {
    setState(() => _showControls = true);
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 280),
      opacity: _showControls ? 1.0 : 0.0,
      child: !_showControls
          ? const SizedBox.shrink()
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: DashboardTheme.fade(Colors.black, 0.82),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Exit dashboard',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                          size: 26,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      IconButton(
                        tooltip: _isPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPlaying = !_isPlaying;
                            if (_isPlaying) _resumeAutoPlayAt = null;
                          });
                          _showControlsOverlay();
                        },
                      ),
                      IconButton(
                        tooltip: 'Options',
                        icon: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white54,
                          size: 26,
                        ),
                        onPressed: () {
                          setState(() {
                            _showControls = false;
                            _isPlaying = false;
                          });
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DashboardOptionsScreen(
                                slideDuration: _slideDuration,
                                onDurationChanged: (v) {
                                  setState(() => _slideDuration = v);
                                  final uid =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (uid != null) {
                                    FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .set({
                                          'dashboardSlideDuration': v,
                                        }, SetOptions(merge: true));
                                  }
                                },
                                savedCities: _savedCities,
                                primaryCity: _primaryCityName,
                                onSetPrimary: _setPrimaryCity,
                                onDeleteCity: _deleteCity,
                                onAddCityTap: _showCitySearchDialog,
                              ),
                            ),
                          ).then((_) {
                            if (!mounted) return;
                            setState(() {
                              _isPlaying = true;
                              _secondsSinceLastSlide = 0;
                              _resumeAutoPlayAt = null;
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _startTimer() {
    _slideTimer?.cancel();
    _slideTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_slides.isEmpty) return;

      if (!_isPlaying || _showControls) {
        _pausedSeconds++;
        if (_pausedSeconds >= 300 && mounted) {
          setState(() {
            _isPlaying = true;
            _showControls = false;
            _pausedSeconds = 0;
            _resumeAutoPlayAt = null;
          });
        }
        return;
      }
      _pausedSeconds = 0;

      if (_resumeAutoPlayAt != null) {
        if (DateTime.now().isAfter(_resumeAutoPlayAt!)) {
          _resumeAutoPlayAt = null;
          _secondsSinceLastSlide = 0;
        } else {
          return;
        }
      }

      _secondsSinceLastSlide++;
      if (_secondsSinceLastSlide >= _slideDuration) {
        _secondsSinceLastSlide = 0;
        _isAutoAnimating = true;
        final next = (_pageController.page?.round() ?? 0) + 1;
        if (_pageController.hasClients) {
          _pageController
              .animateToPage(
                next,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
              )
              .then((_) => _isAutoAnimating = false);
        }
      }
    });
  }

  void _rebuildSlides(double screenWidth) {
    if (!mounted) return;
    setState(() {
      _slides = _generateSlides(screenWidth);
      _cachedScreenWidth = screenWidth;
    });
  }

  Future<void> _retryBoot() async {
    setState(() {
      _boot = _DashboardBoot.loading;
      _bootError = '';
    });
    await _initData();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final metrics = DashboardMetrics(size);

    if (_boot == _DashboardBoot.ready &&
        ( _slides.isEmpty || (size.width - _cachedScreenWidth).abs() > 1)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildSlides(size.width);
      });
    }

    late final Widget body;
    if (_boot == _DashboardBoot.loading) {
      body = const DashboardLoadingView();
    } else if (_boot == _DashboardBoot.empty) {
      body = ColoredBox(
        color: DashboardTheme.canvas,
        child: DashboardEmptyState(
          icon: Icons.favorite_outline_rounded,
          title: 'No hub selected',
          message:
              'Open a shared hub from settings, then come back to this wall view.',
          action: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DashboardTheme.accent),
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to LoveHub'),
          ),
        ),
      );
    } else if (_boot == _DashboardBoot.error) {
      body = ColoredBox(
        color: DashboardTheme.canvas,
        child: DashboardEmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Dashboard needs a moment',
          message: _bootError,
          action: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DashboardTheme.accent),
            onPressed: _retryBoot,
            child: const Text('Try again'),
          ),
        ),
      );
    } else {
      final displaySlides = _slides.isNotEmpty
          ? _slides
          : [const DashboardLoadingView(label: 'Arranging your slides…')];

      body = Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => _currentPageIndex = i % displaySlides.length);
              if (_currentPageIndex == _birthdaySlideIndex && _hasBirthdayToday) {
                _confettiController.play();
              }
              if (!_isAutoAnimating) {
                _secondsSinceLastSlide = 0;
                _resumeAutoPlayAt = DateTime.now().add(
                  const Duration(seconds: 30),
                );
              }
            },
            itemBuilder: (context, index) {
              return displaySlides[index % displaySlides.length];
            },
          ),
          _buildHeader(metrics),
          _buildControlsOverlay(),
          if (_slides.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: IgnorePointer(
                child: Center(
                  child: DashboardPageDots(
                    count: _slides.length,
                    index: _currentPageIndex % _slides.length,
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              colors: const [
                Colors.pinkAccent,
                Colors.purpleAccent,
                Colors.white,
                Colors.amber,
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: DashboardTheme.canvas,
      body: GestureDetector(
        onTap: _boot == _DashboardBoot.ready ? _showControlsOverlay : null,
        child: body,
      ),
    );
  }
}
