import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:confetti/confetti.dart';
import 'dart:math'; // For the confetti blast angle!

class DashboardScreen extends StatefulWidget {
  final List<MapEntry<String, dynamic>> visibleHubs;

  const DashboardScreen({super.key, required this.visibleHubs});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PageController _pageController = PageController();

  // --- NEW: Confetti State ---
  late ConfettiController _confettiController;
  int _birthdaySlideIndex = -1;
  bool _hasBirthdayToday = false;

  // Data State
  List<Map<String, dynamic>> _hubMembers = [];

  // --- NEW: Adjusted to handle pure Maps for virtual birthday projection ---
  List<Map<String, dynamic>> _rawEvents = [];
  List<Map<String, dynamic>> _eventsAll = [];
  List<Map<String, dynamic>> _birthdays = [];

  List<QueryDocumentSnapshot> _allTasks = [];
  Map<String, dynamic>? _rotaConfig;

  // --- NEW: Photo State ---
  List<String> _photoUrls = [];
  String? _currentPhotoUrl;

  // Weather
  String _primaryCityName = 'Brighton';
  List<Map<String, dynamic>> _savedCities = [];
  Map<String, dynamic> _weatherCache = {};
  bool _isLoadingWeather = false;
  Timer? _weatherUpdateTimer;

  // Curated Relationship Quotes
  String _quoteText = "Fetching inspiration...";
  String _quoteAuthor = "";
  Timer? _quoteTimer;

  // --- NEW: Custom Quotes from Firestore! ---
  List<Map<String, String>> _customQuotes = [];

  // Midnight rollover timer
  Timer? _midnightTimer;
  DateTime _currentDay = DateUtils.dateOnly(DateTime.now());

  // --- NEW: Dynamic Birthday Icons! ---
  IconData _getBdayIcon(String seed) {
    final icons = [
      Icons.cake_rounded,
      Icons.celebration_rounded,
      Icons.card_giftcard_rounded,
      Icons.stars_rounded,
      Icons.local_play_rounded, // Looks like a little party ticket!
    ];
    // Uses the unique ID to pick a "random" icon that stays consistent!
    return icons[seed.hashCode.abs() % icons.length];
  }

  final List<Map<String, String>> _relationshipQuotes = [
    {"text": "Home is wherever I'm with you.", "author": "Edward Sharpe"},
    {
      "text":
          "A successful marriage requires falling in love many times, always with the same person.",
      "author": "Mignon McLaughlin",
    },
    {
      "text": "The best thing to hold onto in life is each other.",
      "author": "Audrey Hepburn",
    },
    {
      "text": "Whatever our souls are made of, his and mine are the same.",
      "author": "Emily Brontë",
    },
    {
      "text":
          "Love is a partnership of two unique people who bring out the very best in each other.",
      "author": "Unknown",
    },
    {
      "text": "To love and be loved is to feel the sun from both sides.",
      "author": "David Viscott",
    },
    {
      "text": "Shared joy is a double joy; shared sorrow is half a sorrow.",
      "author": "Swedish Proverb",
    },
    {
      "text": "Grow old along with me; the best is yet to be.",
      "author": "Robert Browning",
    },
    {
      "text":
          "In all the world, there is no heart for me like yours. In all the world, there is no love for you like mine.",
      "author": "Maya Angelou",
    },
    {"text": "True love stories never have endings.", "author": "Richard Bach"},
    {
      "text":
          "I would rather share one lifetime with you than face all the ages of this world alone.",
      "author": "J.R.R. Tolkien",
    },
    {
      "text": "You are my today and all of my tomorrows.",
      "author": "Leo Christopher",
    },
    {
      "text": "There is no remedy for love but to love more.",
      "author": "Henry David Thoreau",
    },
    {
      "text":
          "To get the full value of joy you must have someone to divide it with.",
      "author": "Mark Twain",
    },
    {
      "text":
          "Love does not consist in gazing at each other, but in looking outward together in the same direction.",
      "author": "Antoine de Saint-Exupéry",
    },
    {"text": "Two are better than one.", "author": "Ecclesiastes 4:9"},
    {
      "text":
          "I swear I couldn’t love you more than I do right now, and yet I know I will tomorrow.",
      "author": "Leo Christopher",
    },
    {
      "text": "If I know what love is, it is because of you.",
      "author": "Hermann Hesse",
    },
    {
      "text":
          "You don't love someone for their looks, or their clothes, or for their fancy car, but because they sing a song only you can hear.",
      "author": "Oscar Wilde",
    },
    {
      "text":
          "The greatest happiness of life is the conviction that we are loved; loved for ourselves, or rather, loved in spite of ourselves.",
      "author": "Victor Hugo",
    },
    {"text": "We are most alive when we're in love.", "author": "John Updike"},
    {
      "text": "Love is composed of a single soul inhabiting two bodies.",
      "author": "Aristotle",
    },
    {
      "text":
          "Being deeply loved by someone gives you strength, while loving someone deeply gives you courage.",
      "author": "Lao Tzu",
    },
    {
      "text": "Every love story is beautiful, but ours is my favorite.",
      "author": "Unknown",
    },
    {
      "text":
          "I love you not only for what you are, but for what I am when I am with you.",
      "author": "Roy Croft",
    },
    {
      "text":
          "A great marriage is not when the 'perfect couple' comes together. It is when an imperfect couple learns to enjoy their differences.",
      "author": "Dave Meurer",
    },
    {
      "text": "I found the one my heart loves.",
      "author": "Song of Solomon 3:4",
    },
    {
      "text":
          "Let us be grateful to the people who make us happy; they are the charming gardeners who make our souls blossom.",
      "author": "Marcel Proust",
    },
    {"text": "You're nothing short of my everything.", "author": "Ralph Block"},
    {
      "text":
          "Love is when the other person's happiness is more important than your own.",
      "author": "H. Jackson Brown Jr.",
    },
  ];

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
  int _pausedSeconds = 0; // <-- NEW: Tracks how long it's been paused

  @override
  void initState() {
    super.initState();

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 4),
    );

    if (widget.visibleHubs.isNotEmpty) _initData();

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
    _slideTimer?.cancel();
    _controlsHideTimer?.cancel();
    _quoteTimer?.cancel();
    _midnightTimer?.cancel();
    _weatherUpdateTimer?.cancel();
    _pageController.dispose();
    _confettiController.dispose(); // <-- ADD THIS LINE
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CORE HELPERS
  // ---------------------------------------------------------------------------

  // --- NEW: Project Birthdays for the Dashboard! ---
  List<Map<String, dynamic>> _getProjectedBirthdays() {
    List<Map<String, dynamic>> virtualEvents = [];
    final int currentYear = DateTime.now().year;
    for (var b in _birthdays) {
      int month = b['month'];
      int day = b['day'];
      int? year = b['year'];

      for (int y = currentYear - 1; y <= currentYear + 2; y++) {
        // --- CLEAN UI: Just the name, and their age in brackets if known! ---
        String title = year != null
            ? "${b['name']} (${y - year})"
            : "${b['name']}";

        DateTime date = DateTime(y, month, day);
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
    final DateTime s = (data['start'] as Timestamp).toDate();
    final DateTime e = data['end'] != null
        ? (data['end'] as Timestamp).toDate()
        : s;
    final dayStart = DateUtils.dateOnly(s);
    final dayEnd = DateUtils.dateOnly(e);
    return (checkDay.isAtSameMomentAs(dayStart) ||
            checkDay.isAfter(dayStart)) &&
        (checkDay.isAtSameMomentAs(dayEnd) || checkDay.isBefore(dayEnd));
  }

  List<Map<String, dynamic>> _getChoresForDay(DateTime targetDate) {
    if (_rotaConfig == null) return [];
    if (_rotaConfig!['anchorDate'] == null ||
        _rotaConfig!['cycleLength'] == null ||
        _rotaConfig!['blueprint'] == null)
      return [];

    final anchorDate = (_rotaConfig!['anchorDate'] as Timestamp).toDate();
    final cycleLength = _rotaConfig!['cycleLength'] as int;
    final blueprint = _rotaConfig!['blueprint'] as Map<String, dynamic>;

    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final anchor = DateTime(anchorDate.year, anchorDate.month, anchorDate.day);

    final daysSince = target.difference(anchor).inDays;
    if (daysSince < 0) return [];

    int dayIndex = daysSince % cycleLength;
    List<dynamic> chores = blueprint[dayIndex.toString()] ?? [];
    return List<Map<String, dynamic>>.from(chores);
  }

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------
  void _initData() async {
    final hubId = widget.visibleHubs.first.key;
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUid != null) {
      final String? authPhoto = FirebaseAuth.instance.currentUser?.photoURL;
      if (authPhoto != null && authPhoto.isNotEmpty) {
        FirebaseFirestore.instance.collection('users').doc(currentUid).set({
          'photoURL': authPhoto,
        }, SetOptions(merge: true));
      }
    }

    final hubDoc = await FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .get();
    final List members = hubDoc.data()?['members'] ?? [];
    for (String uid in members) {
      final uDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      String photoURL = uDoc.data()?['photoURL'] ?? '';
      if (uid == currentUid) {
        photoURL = FirebaseAuth.instance.currentUser?.photoURL ?? photoURL;
      }
      if (mounted) {
        setState(() {
          // --- NEW: Grab the full name, then chop off the surname! ---
          String fullName = uDoc.data()?['displayName'] ?? 'Unknown';
          String firstName = fullName.split(' ').first;
          _hubMembers.add({
            'uid': uid,
            'name': firstName,
            'photoURL': photoURL,
          });
        });
      }
    }

    final lookBack = DateTime.now().subtract(const Duration(days: 60));

    // --- NEW: Watch Birthdays ---
    FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('birthdays')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _birthdays = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _eventsAll = [..._rawEvents, ..._getProjectedBirthdays()];
          _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
        });

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
              .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
              .toList();
          _eventsAll = [..._rawEvents, ..._getProjectedBirthdays()];
          _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
        });

    FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('items')
        .where('isDone', isEqualTo: false)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _allTasks = snap.docs;
          _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
        });

    FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('rota_settings')
        .doc('config')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _rotaConfig = snap.data();
          _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
        });

    // --- NEW: Watch Custom Quotes ---
    FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('quotes')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _customQuotes = snap.docs.map((d) {
            return {
              "text": d['text'] as String? ?? "",
              "author": d['author'] as String? ?? "Us",
            };
          }).toList();
          _pickRandomQuote();
        });

    // --- NEW: Listen to Photos ---
    FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('photos')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          _photoUrls = snap.docs
              .map((d) => (d.data() as Map<String, dynamic>)['url'] as String)
              .toList();

          // If this is the first load, pick a photo immediately!
          if (_currentPhotoUrl == null && _photoUrls.isNotEmpty) {
            _pickRandomPhoto();
            _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
          }
        });

    _initWeatherSystem();
    _startTimer();

    // Background timers
    _quoteTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _pickRandomQuote();
      _pickRandomPhoto(); // <-- Added this!
    });
    _weatherUpdateTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _fetchAllWeather(),
    );
  }

  void _pickRandomQuote() {
    // Merge the built-in quotes with your personal custom quotes!
    final allQuotes = [..._relationshipQuotes, ..._customQuotes];

    if (allQuotes.isEmpty) return;

    final random = List.of(allQuotes)..shuffle();
    if (mounted) {
      setState(() {
        _quoteText = random.first['text']!;
        _quoteAuthor = random.first['author']!;
      });
      _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
    }
  }

  void _pickRandomPhoto() {
    if (_photoUrls.isEmpty) return;
    final random = List.of(_photoUrls)..shuffle();
    if (mounted) {
      setState(() {
        _currentPhotoUrl = random.first;
      });
    }
  }

  Widget _memberAvatar(String uid, {double radius = 14}) {
    if (uid == 'shared') {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.pinkAccent.withOpacity(0.2),
        child: Icon(
          Icons.favorite_rounded,
          color: Colors.pinkAccent,
          size: radius * 1.2,
        ),
      );
    }

    final member = _hubMembers.firstWhere(
      (m) => m['uid'] == uid,
      orElse: () => {'name': '?', 'photoURL': ''},
    );
    final String photoURL = member['photoURL'] ?? '';
    final String name = member['name'] ?? '?';
    const Color bgColor = Colors.indigo;
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Widget fallback = CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
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

  // ---------------------------------------------------------------------------
  // WEATHER SYSTEM
  // ---------------------------------------------------------------------------
  Future<void> _initWeatherSystem() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null && _hubMembers.isNotEmpty) uid = _hubMembers.first['uid'];
    if (uid == null) return;

    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((
      snapshot,
    ) {
      if (!mounted) return;
      final data = snapshot.data();
      setState(() {
        final List<dynamic> rawCities = data?['weatherCities'] ?? [];
        _savedCities = rawCities.isEmpty
            ? [
                {'name': 'Brighton', 'lat': 50.82, 'lng': -0.13},
              ]
            : List<Map<String, dynamic>>.from(rawCities);
        _primaryCityName = data?['primaryCity'] ?? _savedCities.first['name'];

        // --- NEW: Load the saved slide duration! ---
        if (data != null && data.containsKey('dashboardSlideDuration')) {
          _slideDuration = (data['dashboardSlideDuration'] as num).toDouble();
        }
      });
      _fetchAllWeather();
    });
  }

  Future<void> _fetchAllWeather() async {
    if (_savedCities.isEmpty) return;
    if (mounted) setState(() => _isLoadingWeather = true);
    try {
      for (var city in _savedCities) {
        // --- UPGRADED: 7 Days of Hourly + Daily + is_day flags! ---
        final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${city['lat']}&longitude=${city['lng']}&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation_probability,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          if (mounted) {
            setState(
              () => _weatherCache[city['name']] = json.decode(response.body),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingWeather = false);
        _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
      }
    }
  }

  Future<void> _setPrimaryCity(String cityName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'primaryCity': cityName,
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _primaryCityName = cityName);
        _rebuildSlides(_cachedScreenWidth > 0 ? _cachedScreenWidth : 800);
      }
    }
  }

  Future<void> _deleteCity(String cityName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final newCities = List<Map<String, dynamic>>.from(_savedCities)
        ..removeWhere((c) => c['name'] == cityName);
      if (_primaryCityName == cityName && newCities.isNotEmpty)
        _setPrimaryCity(newCities.first['name']);
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'weatherCities': newCities,
      }, SetOptions(merge: true));
    }
  }

  void _showCitySearchDialog() {
    final searchCtrl = TextEditingController();
    List<dynamic> searchResults = [];
    bool isSearching = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add City', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  style: const TextStyle(color: Colors.white),
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
                      onPressed: () async {
                        if (searchCtrl.text.isEmpty) return;
                        setDialogState(() => isSearching = true);
                        try {
                          final res = await http.get(
                            Uri.parse(
                              'https://geocoding-api.open-meteo.com/v1/search?name=${searchCtrl.text}&count=5&language=en&format=json',
                            ),
                          );
                          setDialogState(() {
                            searchResults =
                                json.decode(res.body)['results'] ?? [];
                            isSearching = false;
                          });
                        } catch (_) {
                          setDialogState(() => isSearching = false);
                        }
                      },
                    ),
                  ),
                ),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(color: Colors.blueAccent),
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
                            color: Colors.blueAccent,
                          ),
                          title: Text(
                            '${city['name']}, ${city['country'] ?? ''}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          onTap: () async {
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid != null) {
                              final newCities = List<Map<String, dynamic>>.from(
                                _savedCities,
                              );
                              if (!newCities.any(
                                (c) => c['name'] == city['name'],
                              )) {
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
                            Navigator.pop(context);
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

  bool _isRainy(int code) =>
      (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;

  Widget _getWeatherIcon(int code, int isDay, {double size = 24}) {
    IconData icon;
    Color color;
    if (code == 0 || code == 1) {
      icon = isDay == 1 ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
      color = isDay == 1 ? Colors.orangeAccent : Colors.indigo.shade200;
    } else if (code == 2) {
      icon = Icons.cloud_queue_rounded;
      color = Colors.grey.shade400;
    } else if (code == 3) {
      icon = Icons.cloud_rounded;
      color = Colors.grey.shade500;
    } else if (code <= 48) {
      icon = Icons.foggy;
      color = Colors.blueGrey;
    } else if (code >= 95) {
      icon = Icons.flash_on_rounded;
      color = Colors.yellowAccent;
    } else if (_isRainy(code)) {
      icon = Icons.water_drop_rounded;
      color = Colors.lightBlueAccent;
    } else if (code >= 71 && code <= 77) {
      icon = Icons.ac_unit_rounded;
      color = Colors.cyanAccent;
    } else {
      icon = Icons.cloud_rounded;
      color = Colors.grey;
    }
    return Icon(icon, color: color, size: size);
  }

  int? _primaryWeatherCode() {
    final data = _weatherCache[_primaryCityName];
    if (data == null) return null;
    return (data['current']?['weather_code'] as num?)?.toInt();
  }

  String _formatMultiDayTitle(Map<String, dynamic> data, DateTime currentDate) {
    final String title = data['summary'] ?? 'Event';
    final DateTime start = (data['start'] as Timestamp).toDate();
    final DateTime end = data['end'] != null
        ? (data['end'] as Timestamp).toDate()
        : start;

    if (!DateUtils.isSameDay(start, end)) {
      final int totalDays =
          DateUtils.dateOnly(end).difference(DateUtils.dateOnly(start)).inDays +
          1;
      final int currentDayNum =
          (DateUtils.dateOnly(
                    currentDate,
                  ).difference(DateUtils.dateOnly(start)).inDays +
                  1)
              .clamp(1, totalDays);
      return '$title (Day $currentDayNum/$totalDays)';
    }
    return title;
  }

  // ---------------------------------------------------------------------------
  // SLIDE GENERATION
  // ---------------------------------------------------------------------------
  List<Widget> _generateSlides(double screenWidth) {
    final List<Widget> slides = [];
    final bool isMobile = screenWidth < 800;

    // --- 1. UNIFIED CALENDAR SLIDE ---
    slides.add(_buildSlide_UnifiedSchedule(isMobile));

    // --- 2. UNIFIED TASKS SLIDE ---
    final nonShopTasks = _allTasks.where((t) {
      final d = t.data() as Map<String, dynamic>;
      return d['listName'] != 'Shopping' && d['status'] != 'pending_acceptance';
    }).toList();

    if (nonShopTasks.isNotEmpty) {
      // We now pass all tasks together; the builder will group them by User!
      slides.add(_buildSlide_UnifiedTasks(nonShopTasks, isMobile));
    }

    // --- NEW: 2.5 WEEKLY CHORES SLIDE ---

    // --- NEW: 2.5 WEEKLY CHORES SLIDE ---
    if (_rotaConfig != null && !_rotaConfig!.containsKey('cycleLength')) {
      slides.add(_buildSlide_WeeklyChores(isMobile));
    }
    // --- 3. RESPONSIVE SHOPPING SLIDES ---
    final shopItems = _allTasks
        .where((t) => (t.data() as Map)['listName'] == 'Shopping')
        .toList();
    final urgentShop = shopItems
        .where((t) => (t.data() as Map)['isUrgent'] == true)
        .toList();
    final regularShop = shopItems
        .where((t) => (t.data() as Map)['isUrgent'] != true)
        .toList();

    if (isMobile) {
      if (urgentShop.isNotEmpty)
        slides.add(_buildSlide_Shopping_Mobile(urgentShop, true));
      if (regularShop.isNotEmpty)
        slides.add(_buildSlide_Shopping_Mobile(regularShop, false));
    } else {
      if (shopItems.isNotEmpty)
        slides.add(_buildSlide_Shopping(urgentShop, regularShop));
    }

    // --- 4. RESPONSIVE BIRTHDAY SLIDE ---
    final bdays =
        _eventsAll.where((d) {
          if ((d['category'] ?? '') != 'birthday') return false;
          final DateTime s = (d['start'] as Timestamp).toDate();
          return s.isAfter(DateTime.now().subtract(const Duration(days: 1))) &&
              s.isBefore(DateTime.now().add(const Duration(days: 365)));
        }).toList()..sort(
          (a, b) =>
              (a['start'] as Timestamp).compareTo(b['start'] as Timestamp),
        );

    final topBdays = bdays.take(10).toList();
    final today = DateUtils.dateOnly(DateTime.now());

    _hasBirthdayToday = topBdays.any((d) {
      final s = (d['start'] as Timestamp).toDate();
      return DateUtils.dateOnly(s).difference(today).inDays == 0;
    });

    // --- NEW: THE VISIBILITY GATEKEEPER ---
    bool shouldShowBirthdaySlide = false;

    if (topBdays.isNotEmpty) {
      // Look at the VERY NEXT birthday coming up
      final nextBday = (topBdays.first['start'] as Timestamp).toDate();
      final daysUntilNext = DateUtils.dateOnly(
        nextBday,
      ).difference(today).inDays;

      // Only show the slide if the next birthday is within 3 weeks (21 days)!
      if (daysUntilNext <= 21) {
        shouldShowBirthdaySlide = true;
      }
    }

    if (shouldShowBirthdaySlide) {
      _birthdaySlideIndex = slides.length;
      slides.add(_buildSlide_Birthdays(topBdays, isMobile));
    } else {
      _birthdaySlideIndex = -1; // Hide it completely from the loop
    }

    // --- 5. AFFIRMATIONS & WEATHER ---
    slides.add(_buildSlide_Affirmations());
    _weatherSlideIndex = slides.length;
    slides.add(_buildSlide_RichWeather());

    // --- NEW: PHOTOS SLIDE ---
    // --- 6. PHOTOS ---
    if (_photoUrls.isNotEmpty) {
      slides.add(_buildSlide_Photos(isMobile)); // <-- Pass isMobile here!
    }

    return slides;

    return slides;
  }

  // ---------------------------------------------------------------------------
  // SHARED SLIDES
  // ---------------------------------------------------------------------------
  // ===========================================================================
  // UNIFIED CALENDAR SLIDE
  // ===========================================================================
  Widget _buildSlide_UnifiedSchedule(bool isMobile) {
    return Container(
      // --- NEW: Full-screen ambient glass gradient! ---
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blueAccent.withOpacity(0.05), // Soft icy blue tint
            Colors.black,
          ],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 40,
        isMobile ? 140 : 160,
        isMobile ? 20 : 40,
        40,
      ),
      child: isMobile
          ? _buildUnifiedScheduleBox('UPCOMING SCHEDULE', 0, 7, false)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT BOX (Today & Tomorrow)
                Expanded(
                  flex: 60,
                  child: _buildUnifiedScheduleBox('', 0, 2, true),
                ),
                const SizedBox(width: 40),
                // RIGHT BOX (Next 5 Days)
                Expanded(
                  flex: 40,
                  child: _buildUnifiedScheduleBox('', 2, 5, false),
                ),
              ],
            ),
    );
  }

  Widget _buildUnifiedScheduleBox(
    String title,
    int startDayOffset,
    int dayCount,
    bool useLargeFont,
  ) {
    final todayStart = DateUtils.dateOnly(DateTime.now());

    return Container(
      // --- RESTORED: Deep, rich black gradient cards for the Calendar! ---
      padding: EdgeInsets.all(useLargeFont ? 32 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blueAccent.withOpacity(
              0.10,
            ), // A subtle splash of the icy blue
            Colors.black.withOpacity(0.85), // Fading into heavy black
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.blueAccent.withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              children: List.generate(dayCount, (index) {
                final int i = startDayOffset + index;
                final DateTime checkDate = todayStart.add(Duration(days: i));

                final events =
                    _eventsAll.where((d) {
                      if (!_eventOverlapsDay(d, checkDate)) return false;

                      if (i == 0) {
                        final bool isAllDay = d['allDay'] ?? false;
                        if (!isAllDay) {
                          final DateTime s = (d['start'] as Timestamp).toDate();
                          final DateTime e = d['end'] != null
                              ? (d['end'] as Timestamp).toDate()
                              : s;
                          if (e.isBefore(DateTime.now())) return false;
                        }
                      }
                      return true;
                    }).toList()..sort(
                      (a, b) => (a['start'] as Timestamp).compareTo(
                        b['start'] as Timestamp,
                      ),
                    );

                // --- NEW: Smart Empty State Logic ---
                String emptyText = 'No events scheduled';
                if (events.isEmpty && i == 0) {
                  // Check if there were any events today before the time-filter removed them!
                  bool hadAnyEventsToday = _eventsAll.any((d) {
                    return _eventOverlapsDay(d, checkDate);
                  });
                  if (hadAnyEventsToday) emptyText = 'All events finished';
                }

                final String label = i == 0
                    ? 'TODAY'
                    : i == 1
                    ? 'TOMORROW'
                    : DateFormat('EEE d MMM').format(checkDate).toUpperCase();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: index == 0 ? 0 : (useLargeFont ? 28 : 20),
                        bottom: 12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: i == 0
                                  ? Colors.greenAccent
                                  : const Color.fromARGB(255, 92, 128, 158),
                              // --- UPSCALED: Day Headers ---
                              fontSize: useLargeFont ? 28 : 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Divider(
                              color: i == 0
                                  ? Colors.greenAccent.withOpacity(0.3)
                                  : const Color.fromARGB(255, 119, 126, 131),
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (events.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Text(
                          emptyText, // <-- FIXED: Uses the smart text!
                          style: TextStyle(
                            color: Colors
                                .white38, // Brightened slightly so it's readable
                            fontSize: useLargeFont ? 24 : 20,
                            fontStyle:
                                FontStyle.italic, // Adds a nice subtle touch
                          ),
                        ),
                      )
                    else
                      ...events.map((d) {
                        final bool isMeal = d['category'] == 'meal';
                        final String category = d['category'] ?? 'general';
                        final String ownerId = d['assignedTo'] ?? 'shared';
                        final bool isAllDay = d['allDay'] ?? false;
                        final DateTime s = (d['start'] as Timestamp).toDate();
                        final String timeStr = isAllDay
                            ? 'All Day'
                            : DateFormat('HH:mm').format(s);

                        Color baseColor;
                        if (category == 'birthday') {
                          baseColor = Colors.purpleAccent;
                        } else if (isMeal) {
                          baseColor = Colors.greenAccent;
                        } else if (ownerId == 'shared') {
                          baseColor = Colors.pinkAccent;
                        } else {
                          int userIndex = _hubMembers.indexWhere(
                            (m) => m['uid'] == ownerId,
                          );

                          if (userIndex == 0) {
                            baseColor = Colors.blue.shade400;
                          } else if (userIndex == 1) {
                            baseColor = Colors.teal.shade400;
                          } else if (userIndex == 2) {
                            baseColor = Colors.teal.shade300;
                          } else {
                            baseColor = Colors.white70;
                          }
                        }

                        return Container(
                          // --- UPSCALED: Spacing between events ---
                          margin: const EdgeInsets.only(bottom: 16),
                          // --- UPSCALED: Padding inside the event bubble ---
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: useLargeFont ? 20 : 16,
                          ),
                          decoration: BoxDecoration(
                            color: baseColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: baseColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: useLargeFont
                                    ? 130
                                    : 110, // Widened to fit larger time text
                                child: Row(
                                  children: [
                                    _memberAvatar(
                                      ownerId,
                                      // --- UPSCALED: Avatar size ---
                                      radius: useLargeFont ? 20 : 16,
                                    ),
                                    const SizedBox(width: 12),
                                    if (category == 'birthday')
                                      Icon(
                                        _getBdayIcon(d['id'] ?? d['summary']),
                                        color: baseColor,
                                        size: useLargeFont ? 28 : 24,
                                      )
                                    else if (isMeal)
                                      Icon(
                                        Icons.restaurant,
                                        color: baseColor,
                                        // --- UPSCALED: Meal Icon ---
                                        size: useLargeFont ? 28 : 24,
                                      )
                                    else
                                      Expanded(
                                        child: Text(
                                          timeStr,
                                          style: TextStyle(
                                            color: baseColor,
                                            // --- UPSCALED: Time Text ---
                                            fontSize: useLargeFont ? 24 : 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _formatMultiDayTitle(d, checkDate),
                                  style: TextStyle(
                                    color: i == 0
                                        ? Colors.white
                                        : Colors.white70,
                                    // --- UPSCALED: Event Title ---
                                    fontSize: useLargeFont ? 28 : 22,
                                    fontWeight: i == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    height:
                                        1.3, // Added breathing room for multi-line event titles
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SMART MASONRY LAYOUT (For Tasks & Chores)
  // ===========================================================================
  Widget _buildSmartMasonry({
    required bool isMobile,
    required List<Map<String, dynamic>> groups,
  }) {
    if (groups.isEmpty) return const SizedBox();

    if (isMobile) {
      return ListView(
        children: groups.map((g) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: g['widget'] as Widget,
          );
        }).toList(),
      );
    }

    // --- DESKTOP: Smart 2-Column Layout ---
    // Sort groups by item count (Descending: largest list first)
    groups.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column 1: The single largest box gets its own column to avoid bottom overflow
        Expanded(child: ListView(children: [groups[0]['widget'] as Widget])),
        const SizedBox(width: 40),
        // Column 2: The remaining boxes stacked
        Expanded(
          child: ListView(
            children: groups.skip(1).map((g) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: g['widget'] as Widget,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildUserGroupBox({
    required String ownerId,
    required List<dynamic> items,
    required Color themeColor,
    required bool isTasks,
    List<String>? completedChores,
    required bool isMobile,
  }) {
    if (items.isEmpty) return const SizedBox();

    String title = "SHARED";
    if (ownerId != 'shared') {
      final member = _hubMembers.firstWhere(
        (m) => m['uid'] == ownerId,
        orElse: () => {'name': 'Partner'},
      );
      title = member['name'].toString().toUpperCase();
    }

    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _memberAvatar(ownerId, radius: isMobile ? 20 : 26),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  color: themeColor,
                  fontSize: isMobile ? 20 : 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          ...items.map((item) {
            if (isTasks) {
              // --- TASK ROW ---
              final d =
                  (item as QueryDocumentSnapshot).data()
                      as Map<String, dynamic>;
              final bool isUrgent = d['isUrgent'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- ALIGNMENT FIX: Nudge icon down slightly ---
                    Padding(
                      padding: EdgeInsets.only(top: isMobile ? 0 : 2.0),
                      child: Icon(
                        // --- STYLE FIX: Matches the Chores empty circle! ---
                        isUrgent ? Icons.error_rounded : Icons.circle_outlined,
                        color: isUrgent ? Colors.redAccent : Colors.white38,
                        size: isMobile ? 24 : 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        d['text'],
                        style: TextStyle(
                          color: isUrgent
                              ? Colors.white
                              : const Color.fromARGB(226, 255, 255, 255),
                          fontSize: isMobile ? 20 : 26,
                          fontWeight: isUrgent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          // --- ALIGNMENT FIX: Reduced from 1.5 to 1.2 ---
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            } else {
              // --- CHORE ROW ---
              final chore = item as Map<String, dynamic>;
              final bool isDone =
                  completedChores?.contains(chore['id']) ?? false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- ALIGNMENT FIX: Nudge icon down slightly ---
                    Padding(
                      padding: EdgeInsets.only(top: isMobile ? 0 : 2.0),
                      child: Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: isDone ? Colors.green : Colors.white38,
                        size: isMobile ? 24 : 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        chore['title'],
                        style: TextStyle(
                          color: isDone ? Colors.white38 : Colors.white,
                          fontSize: isMobile ? 20 : 26,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          // --- ALIGNMENT FIX: Reduced from 1.5 to 1.2 ---
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // --- ALIGNMENT FIX: Nudge minutes down slightly ---
                    Padding(
                      padding: EdgeInsets.only(top: isMobile ? 0 : 2.0),
                      child: Text(
                        "${chore['effortMinutes']}m",
                        style: TextStyle(
                          color: isDone ? Colors.white24 : themeColor,
                          fontSize: isMobile ? 18 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
          }).toList(),
        ],
      ),
    );
  }

  // ===========================================================================
  // UNIFIED TASKS SLIDE
  // ===========================================================================
  Widget _buildSlide_UnifiedTasks(
    List<QueryDocumentSnapshot> tasks,
    bool isMobile,
  ) {
    // 1. Group tasks by user
    final Map<String, List<QueryDocumentSnapshot>> groupedTasks = {
      'shared': [],
    };
    for (var m in _hubMembers) {
      groupedTasks[m['uid']] = [];
    }

    for (var t in tasks) {
      final owner =
          (t.data() as Map<String, dynamic>)['assignedTo'] ?? 'shared';
      groupedTasks.putIfAbsent(owner, () => []).add(t);
    }

    // 2. Build groups for masonry layout
    final List<Map<String, dynamic>> layoutGroups = [];
    groupedTasks.forEach((ownerId, items) {
      if (items.isNotEmpty) {
        // Sort urgent to the top of each individual box!
        items.sort((a, b) {
          bool aU = (a.data() as Map)['isUrgent'] == true;
          bool bU = (b.data() as Map)['isUrgent'] == true;
          if (aU && !bU) return -1;
          if (!aU && bU) return 1;
          return 0;
        });

        layoutGroups.add({
          'id': ownerId,
          'count': items.length,
          'widget': _buildUserGroupBox(
            ownerId: ownerId,
            items: items,
            themeColor: Colors.amberAccent,
            isTasks: true,
            isMobile: isMobile,
          ),
        });
      }
    });

    return Container(
      // --- RESTORED: Full-screen ambient glass gradient! ---
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.amberAccent.withOpacity(0.1), Colors.black],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 24 : 40,
        isMobile ? 120 : 160,
        isMobile ? 24 : 40,
        40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Colors.amberAccent,
                  size: 30,
                ),
              ),
              const SizedBox(width: 24),
              const Text(
                'TASKS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 24),
          Expanded(
            child: _buildSmartMasonry(isMobile: isMobile, groups: layoutGroups),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WEEKLY CHORES SLIDE
  // ===========================================================================
  Widget _buildSlide_WeeklyChores(bool isMobile) {
    if (_rotaConfig == null || _rotaConfig!['anchorDate'] == null)
      return const SizedBox();

    final anchorDate = (_rotaConfig!['anchorDate'] as Timestamp).toDate();
    final daysSince = DateUtils.dateOnly(
      DateTime.now(),
    ).difference(DateUtils.dateOnly(anchorDate)).inDays;

    if (daysSince < 0) return const SizedBox();

    int absoluteWeekNum = (daysSince ~/ 7) + 1;
    int currentCycleWeek = ((daysSince ~/ 7) % 8) + 1;
    final startOfWeek = DateUtils.dateOnly(
      anchorDate,
    ).add(Duration(days: (absoluteWeekNum - 1) * 7));
    final weekId = DateFormat('yyyy-MM-dd').format(startOfWeek);

    final blueprint = _rotaConfig!['blueprint'] as Map<String, dynamic>? ?? {};
    final weekChores = List<Map<String, dynamic>>.from(
      blueprint[currentCycleWeek.toString()] ?? [],
    );

    if (weekChores.isEmpty) return const SizedBox();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('hubs')
          .doc(widget.visibleHubs.first.key)
          .collection('rota_logs')
          .doc('week_$weekId')
          .snapshots(),
      builder: (context, snapshot) {
        List<String> completed = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          completed = List<String>.from(
            (snapshot.data!.data() as Map<String, dynamic>)['completed'] ?? [],
          );
        }

        double progress = completed.length / weekChores.length;

        // 1. Group chores by user
        final Map<String, List<Map<String, dynamic>>> groupedChores = {
          'shared': [],
        };
        for (var m in _hubMembers) {
          groupedChores[m['uid']] = [];
        }

        for (var c in weekChores) {
          final owner = c['assignedTo'] ?? 'shared';
          groupedChores.putIfAbsent(owner, () => []).add(c);
        }

        // 2. Build groups for masonry layout
        final List<Map<String, dynamic>> layoutGroups = [];
        groupedChores.forEach((ownerId, items) {
          if (items.isNotEmpty) {
            // Sort unfinished to the top of each individual box!
            items.sort((a, b) {
              bool aDone = completed.contains(a['id']);
              bool bDone = completed.contains(b['id']);
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
                themeColor: Colors.deepPurpleAccent,
                isTasks: false,
                completedChores: completed,
                isMobile: isMobile,
              ),
            });
          }
        });

        return Container(
          // --- RESTORED: Full-screen ambient glass gradient! ---
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurpleAccent.withOpacity(0.1), Colors.black],
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            isMobile ? 24 : 40,
            isMobile ? 120 : 160,
            isMobile ? 24 : 40,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurpleAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.cleaning_services_rounded,
                          color: Colors.deepPurpleAccent,
                          size: isMobile ? 26 : 30,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        'HOUSE ROTA', // <-- FIXED: Clean new title
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 26 : 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: isMobile ? 50 : 60,
                    height: isMobile ? 50 : 60,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          color: Colors.deepPurpleAccent,
                          backgroundColor: Colors.white10,
                          strokeWidth: 8,
                        ),
                        Center(
                          child: Text(
                            "${(progress * 100).toInt()}%",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 12 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: Colors.white.withOpacity(0.08)),
              const SizedBox(height: 24),
              Expanded(
                child: _buildSmartMasonry(
                  isMobile: isMobile,
                  groups: layoutGroups,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BIRTHDAY SLIDE
  // ---------------------------------------------------------------------------
  Widget _buildSlide_Birthdays(
    List<Map<String, dynamic>> bdays,
    bool isMobile,
  ) {
    final total = bdays.length;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D0A18), Color(0xFF0A0A2E)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        isMobile ? 24 : 40,
        isMobile ? 120 : 160,
        isMobile ? 24 : 40,
        40,
      ),
      child: Column(
        children: [
          Icon(
            Icons.cake_rounded,
            color: Colors.pinkAccent,
            size: isMobile ? 48 : 64,
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 40),
          Expanded(
            child: Center(
              // Constrain the width on TV so the single column looks elegant, not stretched!
              child: SizedBox(
                width: isMobile ? double.infinity : 700,
                child: _buildBirthdayColumn(bdays, isMobile, 0, total),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayColumn(
    List<Map<String, dynamic>> bdays,
    bool isMobile,
    int startIndex,
    int totalCount,
  ) {
    // We calculate "today" once up here to keep the list super fast
    final today = DateUtils.dateOnly(DateTime.now());

    return ListView.builder(
      itemCount: bdays.length,
      itemBuilder: (context, i) {
        final d = bdays[i];
        final DateTime s = (d['start'] as Timestamp).toDate();

        // --- NEW: THE URGENCY MATH ---
        final bdayDate = DateUtils.dateOnly(s);
        final int daysUntil = bdayDate.difference(today).inDays;

        bool isToday = daysUntil == 0;
        bool isImminent =
            daysUntil > 0 && daysUntil <= 3; // <-- NEW: Within 3 days!
        bool isSoon = daysUntil > 0 && daysUntil <= 14;

        int globalIndex = startIndex + i;

        double fade = (isToday || isSoon)
            ? 0.0
            : (totalCount > 1 ? (globalIndex / (totalCount - 1)) : 0.0);

        // --- NEW: Today gets a huge 15% bump, imminent gets a 10% bump!
        double scale = isToday
            ? 1.15
            : (isImminent ? 1.10 : (1.0 - (fade * 0.30)));

        // --- DYNAMIC COLORS ---
        Color boxColor = isToday
            ? Colors.pinkAccent.withOpacity(0.15)
            : (isImminent
                  ? Colors.pinkAccent.withOpacity(0.08)
                  : Color.lerp(
                      Colors.white.withOpacity(0.06),
                      Colors.white.withOpacity(0.01),
                      fade,
                    )!);

        Color borderColor = isToday
            ? Colors.pinkAccent
            : (isImminent
                  ? Colors.pinkAccent.withOpacity(
                      0.8,
                    ) // Brighter border for imminent
                  : (isSoon
                        ? Colors.pinkAccent.withOpacity(0.5)
                        : Color.lerp(
                            Colors.pinkAccent.withOpacity(0.3),
                            Colors.pinkAccent.withOpacity(0.05),
                            fade,
                          )!));

        Color iconColor = isToday
            ? Colors.white
            : Color.lerp(
                Colors.pinkAccent,
                Colors.pinkAccent.withOpacity(0.3),
                fade,
              )!;

        Color nameColor = isToday
            ? Colors.white
            : Color.lerp(Colors.white, Colors.white38, fade)!;

        Color dateColor = isToday
            ? Colors.white
            : Color.lerp(Colors.white70, Colors.white24, fade)!;

        return Container(
          margin: EdgeInsets.only(bottom: 12 * scale),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 24,
            vertical: (isMobile ? 12 : 16) * scale,
          ),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(20),
            // Thicker border and a soft glow if it's today!
            border: Border.all(color: borderColor, width: isToday ? 2 : 1),
            boxShadow: isToday
                ? [
                    BoxShadow(
                      color: Colors.pinkAccent.withOpacity(0.2),
                      blurRadius: 15,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                _getBdayIcon(d['id'] ?? d['summary']),
                color: iconColor,
                size: 20 * scale,
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Text(
                  '${d['summary']}',
                  style: TextStyle(
                    color: nameColor,
                    fontSize: (isMobile ? 18 : 22) * scale,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),

              // --- THE SMART BADGES ---
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "TODAY!",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                )
              else if (isSoon)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    // Solid pink if it's within 3 days to make it pop!
                    color: isImminent
                        ? Colors.pinkAccent
                        : Colors.pinkAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    daysUntil == 1 ? "Tomorrow" : "In $daysUntil days",
                    style: TextStyle(
                      color: isImminent ? Colors.white : Colors.pinkAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

              // Hide the standard date if it's today (the TODAY badge replaces it)
              if (!isToday)
                Text(
                  DateFormat('d MMM').format(s),
                  style: TextStyle(
                    color: dateColor,
                    fontSize: (isMobile ? 16 : 18) * scale,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // --- DESKTOP SHOPPING VIEW (Auto-hides empty columns) ---
  Widget _buildSlide_Shopping(
    List<QueryDocumentSnapshot> urgent,
    List<QueryDocumentSnapshot> regular,
  ) {
    const Color themeColor = Colors.greenAccent; // <-- Changed to Green
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2A08), Colors.black], // Subtle dark green tint
        ),
      ),
      padding: const EdgeInsets.fromLTRB(40, 160, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: themeColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 24),
              const Text(
                'SHOPPING',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (urgent.isNotEmpty)
                  Expanded(
                    child: _buildShopColumn(
                      'PRIORITY',
                      Colors.redAccent,
                      urgent,
                      true,
                      false,
                    ),
                  ),

                if (urgent.isNotEmpty && regular.isNotEmpty)
                  const SizedBox(width: 40),

                if (regular.isNotEmpty)
                  Expanded(
                    child: _buildShopColumn(
                      'REGULAR',
                      Colors.white38,
                      regular,
                      false,
                      false,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- MOBILE SHOPPING VIEW (One dedicated list per slide) ---
  // --- MOBILE SHOPPING VIEW (One dedicated list per slide) ---
  Widget _buildSlide_Shopping_Mobile(
    List<QueryDocumentSnapshot> items,
    bool isUrgent,
  ) {
    // --- FIXED: Changed from peach to greenAccent! ---
    const Color themeColor = Colors.greenAccent;
    final String title = isUrgent ? 'PRIORITY SHOPPING' : 'SHOPPING';
    final Color color = isUrgent ? Colors.redAccent : Colors.white38;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // --- FIXED: Dark green gradient instead of orange/brown! ---
          colors: [Color(0xFF0D2A08), Colors.black],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 120, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.12), // <-- Uses themeColor
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: themeColor, // <-- Uses themeColor
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: items
                  .map((t) => _buildShopRow(t, isUrgent, true))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER BUILDERS ---
  Widget _buildShopColumn(
    String title,
    Color color,
    List<QueryDocumentSnapshot> items,
    bool isUrgent,
    bool isMobile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: items
                .map((t) => _buildShopRow(t, isUrgent, isMobile))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildShopRow(QueryDocumentSnapshot t, bool isUrgent, bool isMobile) {
    final d = t.data() as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            isUrgent ? Icons.error_rounded : Icons.circle_outlined,
            color: isUrgent ? Colors.redAccent : Colors.white38,
            size: isMobile ? 24 : 28, // Smaller icon on mobile
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              d['text'],
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 22 : 32,
              ), // Scales text for mobile!
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AFFIRMATION SLIDE
  // ---------------------------------------------------------------------------
  void _showAddQuoteDialog() {
    final textCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Add Custom Quote",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Enter a quote, inside joke, or affirmation...",
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
                  hintText: "Author (Leave blank for 'Us')",
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
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.pinkAccent),
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
                                ? "Us"
                                : authorCtrl.text.trim(),
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                      if (mounted) {
                        Navigator.pop(ctx);
                        _pickRandomQuote(); // Instantly show the new quote!
                        _showControlsOverlay(); // Keep dashboard awake
                      }
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
                      "Save Quote",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide_Affirmations() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D0D0D), Color(0xFF1A0A1A)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Colors.pinkAccent,
                    size: 60,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '"$_quoteText"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                      height: 1.4,
                    ),
                  ),
                  if (_quoteAuthor.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    Text(
                      '— $_quoteAuthor',
                      style: TextStyle(
                        color: Colors.pinkAccent.withOpacity(0.8),
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // --- NEW: Add Quote Button ---
        Positioned(
          bottom: 40,
          right: 40,
          child: IconButton(
            icon: const Icon(
              Icons.add_comment_rounded,
              color: Colors.white24,
              size: 36,
            ),
            onPressed: _showAddQuoteDialog,
            tooltip: "Add Custom Quote",
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // WEATHER SLIDE
  // ---------------------------------------------------------------------------
  Widget _buildSlide_RichWeather() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 120, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.wb_cloudy_rounded,
                    color: Colors.blueAccent,
                    size: 22,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'FORECAST',
                    style: TextStyle(
                      color: Colors.blueAccent,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _showCitySearchDialog,
                icon: const Icon(
                  Icons.add_rounded,
                  color: Colors.white38,
                  size: 18,
                ),
                label: const Text(
                  'Add city',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoadingWeather
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  )
                : ListView(
                    children: _savedCities.map((cityMap) {
                      final String name = cityMap['name'];
                      final data = _weatherCache[name];
                      if (data == null) return const SizedBox();

                      // --- USE THE NEW SMART WIDGET! ---
                      return CityWeatherCard(
                        name: name,
                        isPrimary: name == _primaryCityName,
                        data: data,
                        onSetPrimary: () => _setPrimaryCity(name),
                        onDelete: () => _deleteCity(name),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide_Photos(bool isMobile) {
    if (_currentPhotoUrl == null) return const SizedBox();

    return Container(
      margin: EdgeInsets.fromLTRB(
        isMobile ? 24 : 40,
        isMobile ? 120 : 160,
        isMobile ? 24 : 40,
        40,
      ),
      decoration: BoxDecoration(
        color: Colors.black, // Dark background for the letterboxing
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. The Image, perfectly rounded on its actual edges!
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(_currentPhotoUrl!, fit: BoxFit.contain),
            ),
          ),

          // 2. The dark gradient overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  stops: const [0.6, 1.0],
                ),
              ),
              padding: EdgeInsets.all(isMobile ? 24 : 40),
              alignment: Alignment.bottomRight,
              child: Icon(
                Icons.photo_camera_back,
                color: Colors.white54,
                size: isMobile ? 24 : 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER & CONTROLS
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    final int? currentCode = _primaryWeatherCode();
    final double temp = (_weatherCache[_primaryCityName] != null)
        ? (_weatherCache[_primaryCityName]['current']['temperature_2m'] as num)
              .toDouble()
        : 0.0;
    // --- NEW: Grab the isDay flag! ---
    final int isDay = (_weatherCache[_primaryCityName] != null)
        ? (_weatherCache[_primaryCityName]['current']['is_day'] as num?)
                  ?.toInt() ??
              1
        : 1;
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)).asBroadcastStream(),
      builder: (context, _) {
        final now = DateTime.now();
        return Container(
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(now),
                        style: const TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.0,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat(':ss').format(now),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withOpacity(0.35),
                          height: 1.0,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('EEEE, d MMMM').format(now).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.pinkAccent,
                      fontSize: 14,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  if (_slides.isNotEmpty && _pageController.hasClients) {
                    // --- NEW: Find the nearest weather slide in the infinite loop! ---
                    int currentRaw = _pageController.page?.round() ?? 0;
                    int currentMod = currentRaw % _slides.length;
                    int distance = _weatherSlideIndex - currentMod;

                    _pageController.animateToPage(
                      currentRaw + distance,
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      currentCode != null
                          ? _getWeatherIcon(
                              currentCode,
                              isDay,
                              size: 26,
                            ) // <-- PASS IT HERE!
                          : const Icon(
                              Icons.cloud_rounded,
                              color: Colors.white38,
                              size: 26,
                            ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _weatherCache.containsKey(_primaryCityName)
                                ? '${temp.round()}°'
                                : '--°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _primaryCityName,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              letterSpacing: 0.5,
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
      duration: const Duration(milliseconds: 300),
      opacity: _showControls ? 1.0 : 0.0,
      child: _showControls
          ? Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 60),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 28,
                      ),
                      onPressed: () =>
                          Navigator.pop(context), // Exits Dashboard
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPlaying = !_isPlaying;
                          if (_isPlaying)
                            _resumeAutoPlayAt = null; // Force instant resume!
                        });
                        _showControlsOverlay();
                      },
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white54,
                        size: 28,
                      ),
                      onPressed: () {
                        // 1. Hide controls and pause the dashboard while reading settings
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
                                // 2. Instantly save the new speed to Firestore!
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
                          // 3. When the settings menu closes, wake the dashboard back up and reset the clock!
                          if (mounted) {
                            setState(() {
                              _isPlaying = true;
                              _secondsSinceLastSlide =
                                  0; // Start counting from 0 right now
                              _resumeAutoPlayAt =
                                  null; // Clear any manual swipe pauses
                            });
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(),
    );
  }

  void _startTimer() {
    _slideTimer?.cancel();
    // Tick every 1 second
    _slideTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_slides.isEmpty) return;

      // --- NEW: 5-Minute Auto-Unpause Logic ---
      if (!_isPlaying || _showControls) {
        _pausedSeconds++;
        if (_pausedSeconds >= 300) {
          // 300 seconds = 5 minutes
          if (mounted) {
            setState(() {
              _isPlaying = true;
              _showControls = false;
              _pausedSeconds = 0;
              _resumeAutoPlayAt = null; // Clear any manual wait timers
            });
          }
        }
        return; // Stop here if paused
      } else {
        _pausedSeconds = 0; // Reset counter if we are playing normally
      }
      // -----------------------------------------

      // If we are in a manual timeout pause (from swiping), wait it out
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

        // --- NEW: Just keep going forward forever! ---
        int next = (_pageController.page?.round() ?? 0) + 1;

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

  double _cachedScreenWidth = 0;

  void _rebuildSlides(double screenWidth) {
    if (_hubMembers.isEmpty) return;
    setState(() {
      _slides = _generateSlides(screenWidth);
      _cachedScreenWidth = screenWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    if (_slides.isEmpty || screenWidth != _cachedScreenWidth) {
      if (_hubMembers.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rebuildSlides(screenWidth);
        });
      }
    }

    final List<Widget> displaySlides = _slides.isNotEmpty
        ? _slides
        : [
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.pinkAccent),
              ),
            ),
          ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showControlsOverlay,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (i) {
                // Keep the UI slide counter accurate using Modulo math!
                setState(() => _currentPageIndex = i % displaySlides.length);

                // --- NEW: FIRE CONFETTI! ---
                if (_currentPageIndex == _birthdaySlideIndex &&
                    _hasBirthdayToday) {
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
                // Loop through the slides infinitely
                return displaySlides[index % displaySlides.length];
              },
            ),
            _buildHeader(),
            _buildControlsOverlay(),

            // --- NEW: THE CONFETTI CANNON ---
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: pi / 2, // Fires straight down from the ceiling!
                maxBlastForce: 5,
                minBlastForce: 2,
                emissionFrequency: 0.05,
                numberOfParticles:
                    50, // Enough to be festive, but won't lag the TV
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
        ),
      ),
    );
  }
}

/// ============================================================================
// DASHBOARD OPTIONS SCREEN
// ============================================================================
class DashboardOptionsScreen extends StatefulWidget {
  final double slideDuration;
  final ValueChanged<double> onDurationChanged;
  final List<Map<String, dynamic>>
  savedCities; // Kept so your existing Navigator call doesn't break!
  final String
  primaryCity; // Kept so your existing Navigator call doesn't break!
  final Function(String) onSetPrimary;
  final Function(String) onDeleteCity;
  final VoidCallback onAddCityTap;

  const DashboardOptionsScreen({
    super.key,
    required this.slideDuration,
    required this.onDurationChanged,
    required this.savedCities,
    required this.primaryCity,
    required this.onSetPrimary,
    required this.onDeleteCity,
    required this.onAddCityTap,
  });

  @override
  State<DashboardOptionsScreen> createState() => _DashboardOptionsScreenState();
}

class _DashboardOptionsScreenState extends State<DashboardOptionsScreen> {
  late double _currentSlideDuration;

  @override
  void initState() {
    super.initState();
    // Grab the initial speed when the screen opens
    _currentSlideDuration = widget.slideDuration;
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Dashboard Options',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'SLIDE SPEED',
            style: TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '${_currentSlideDuration.toInt()} seconds per slide',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                Slider(
                  value: _currentSlideDuration,
                  min: 5,
                  max: 60,
                  activeColor: Colors.pink,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    // Update the UI instantly, while sending the data back to the parent!
                    setState(() => _currentSlideDuration = v);
                    widget.onDurationChanged(v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'WEATHER CITIES',
                style: TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              TextButton.icon(
                onPressed: widget.onAddCityTap,
                icon: const Icon(Icons.add, color: Colors.blueAccent, size: 18),
                label: const Text(
                  'Add City',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- NEW: Live StreamBuilder for instant UI updates! ---
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  ),
                );
              }

              final data = snapshot.data!.data() as Map<String, dynamic>?;
              final List<dynamic> rawCities = data?['weatherCities'] ?? [];
              final List<Map<String, dynamic>> liveCities = rawCities.isEmpty
                  ? [
                      {'name': 'Brighton', 'lat': 50.82, 'lng': -0.13},
                    ] // Fallback
                  : List<Map<String, dynamic>>.from(rawCities);
              final String livePrimary =
                  data?['primaryCity'] ?? liveCities.first['name'];

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: liveCities.map((city) {
                    final bool isPrimary = city['name'] == livePrimary;
                    return ListTile(
                      title: Text(
                        city['name'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      leading: Icon(
                        isPrimary
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: isPrimary ? Colors.amber : Colors.white38,
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => widget.onDeleteCity(city['name']),
                      ),
                      onTap: () => widget.onSetPrimary(city['name']),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SMART CITY WEATHER CARD (Interactive 7-Day / Hourly)
// ============================================================================
class CityWeatherCard extends StatefulWidget {
  final String name;
  final bool isPrimary;
  final Map<String, dynamic> data;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const CityWeatherCard({
    super.key,
    required this.name,
    required this.isPrimary,
    required this.data,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  State<CityWeatherCard> createState() => _CityWeatherCardState();
}

class _CityWeatherCardState extends State<CityWeatherCard> {
  final ScrollController _scrollController = ScrollController();
  int _activeDayIndex = 0;
  int _nowHourlyIndex = 0;
  List<dynamic> _hourlyTimes = [];
  List<dynamic> _dailyTimes = [];

  @override
  void initState() {
    super.initState();
    _hourlyTimes = widget.data['hourly']?['time'] ?? [];
    _dailyTimes = widget.data['daily']?['time'] ?? [];

    // 1. Find the index for "Right Now"
    final now = DateTime.now();
    for (int i = 0; i < _hourlyTimes.length; i++) {
      final dt = DateTime.tryParse(_hourlyTimes[i]);
      if (dt != null &&
          dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day &&
          dt.hour == now.hour) {
        _nowHourlyIndex = i;
        break;
      }
    }

    // 2. Listen to scrolling to highlight the active day!
    _scrollController.addListener(() {
      double offset = _scrollController.offset;
      // Each hour card is roughly 82px wide. We use this to guess the visible hour index.
      int visibleOffset = (offset / 82.0).round();
      int firstVisibleIndex = (_nowHourlyIndex + visibleOffset).clamp(
        0,
        _hourlyTimes.length - 1,
      );

      final visibleDt = DateTime.tryParse(_hourlyTimes[firstVisibleIndex]);
      if (visibleDt != null) {
        final visibleDateStr = DateFormat('yyyy-MM-dd').format(visibleDt);
        int dayIdx = _dailyTimes.indexWhere(
          (d) => (d as String).startsWith(visibleDateStr),
        );
        if (dayIdx != -1 && dayIdx != _activeDayIndex) {
          setState(() => _activeDayIndex = dayIdx);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Jumps the hourly list to the start of the tapped day
  void _jumpToDay(int dayIndex) {
    final targetDateStr = _dailyTimes[dayIndex];
    int targetHourlyIndex = dayIndex == 0
        ? _nowHourlyIndex // If they click "Today", jump to right NOW
        : _hourlyTimes.indexWhere(
            (h) => (h as String).startsWith(targetDateStr),
          );

    if (targetHourlyIndex != -1 && targetHourlyIndex >= _nowHourlyIndex) {
      setState(() => _activeDayIndex = dayIndex);
      int listIndex = targetHourlyIndex - _nowHourlyIndex;
      _scrollController.animateTo(
        listIndex * 82.0, // 82 is the approximate width of one hour card
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  // Self-contained weather icon logic (supports day/night!)
  Widget _getIcon(int code, int isDay, double size) {
    IconData icon;
    Color color;
    if (code == 0 || code == 1) {
      icon = isDay == 1 ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
      color = isDay == 1 ? Colors.orangeAccent : Colors.indigo.shade200;
    } else if (code <= 3) {
      icon = Icons.cloud_rounded;
      color = Colors.grey.shade400;
    } else if (code <= 48) {
      icon = Icons.foggy;
      color = Colors.blueGrey;
    } else if (code >= 95) {
      icon = Icons.flash_on_rounded;
      color = Colors.yellowAccent;
    } else if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      icon = Icons.water_drop_rounded;
      color = Colors.lightBlueAccent;
    } else if (code >= 71 && code <= 77) {
      icon = Icons.ac_unit_rounded;
      color = Colors.cyanAccent;
    } else {
      icon = Icons.cloud_rounded;
      color = Colors.grey;
    }
    return Icon(icon, color: color, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final int hourlyCount = _hourlyTimes.length - _nowHourlyIndex;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isPrimary
              ? [Colors.blueAccent.withOpacity(0.2), Colors.transparent]
              : [Colors.white.withOpacity(0.05), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isPrimary
              ? Colors.blueAccent.withOpacity(0.5)
              : Colors.white12,
          width: widget.isPrimary ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.isPrimary) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!widget.isPrimary)
                  IconButton(
                    tooltip: 'Set as primary',
                    icon: const Icon(
                      Icons.star_border_rounded,
                      color: Colors.white38,
                      size: 22,
                    ),
                    onPressed: widget.onSetPrimary,
                  ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white24,
                    size: 18,
                  ),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),

          // 2. The 7-Day Header List
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 0, 10),
            child: SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _dailyTimes.length,
                itemBuilder: (ctx, i) {
                  final bool isActive = i == _activeDayIndex;
                  final dt = DateTime.tryParse(_dailyTimes[i]);
                  final String dayLabel = i == 0
                      ? 'TODAY'
                      : (dt != null
                            ? DateFormat('EEE d').format(dt).toUpperCase()
                            : 'DAY');

                  // --- THE FIX: Grab 1 PM's weather instead of the "Worst of the day" ---
                  int c = (widget.data['daily']['weather_code'][i] as num)
                      .toInt(); // Fallback
                  if (dt != null) {
                    int middayIdx = _hourlyTimes.indexWhere((h) {
                      final hDt = DateTime.tryParse(h as String);
                      return hDt != null &&
                          hDt.year == dt.year &&
                          hDt.month == dt.month &&
                          hDt.day == dt.day &&
                          hDt.hour == 13;
                    });
                    if (middayIdx != -1) {
                      c =
                          (widget.data['hourly']['weather_code'][middayIdx]
                                  as num)
                              .toInt();
                    }
                  }

                  final double maxT =
                      (widget.data['daily']['temperature_2m_max'][i] as num)
                          .toDouble();
                  final double minT =
                      (widget.data['daily']['temperature_2m_min'][i] as num)
                          .toDouble();

                  return GestureDetector(
                    onTap: () => _jumpToDay(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 90,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.blueAccent.withOpacity(0.2)
                            : Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? Colors.blueAccent.withOpacity(0.8)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayLabel,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white38,
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _getIcon(c, 1, 32),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${maxT.round()}°',
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${minT.round()}°',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          Divider(color: Colors.white.withOpacity(0.05), height: 1),
          const SizedBox(height: 16),

          // 3. The Infinite Scrolling Hourly List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 120,
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: hourlyCount,
                itemBuilder: (ctx, i) {
                  final int idx = _nowHourlyIndex + i;
                  if (idx >= _hourlyTimes.length) return const SizedBox();

                  final int c =
                      (widget.data['hourly']['weather_code'][idx] as num)
                          .toInt();
                  final double t =
                      (widget.data['hourly']['temperature_2m'][idx] as num)
                          .toDouble();
                  final int r =
                      (widget.data['hourly']['precipitation_probability'][idx]
                              as num)
                          .toInt();
                  final int isDay = widget.data['hourly']['is_day'] != null
                      ? (widget.data['hourly']['is_day'][idx] as num).toInt()
                      : 1;

                  final dt = DateTime.tryParse(_hourlyTimes[idx]);
                  final String timeLabel = dt != null
                      ? '${dt.hour.toString().padLeft(2, '0')}:00'
                      : '--:--';

                  final bool isNow = i == 0;
                  final bool isMidnight = dt != null && dt.hour == 0;

                  return Row(
                    children: [
                      // --- THE MIDNIGHT DIVIDER! ---
                      if (isMidnight && !isNow)
                        Container(
                          width: 2,
                          height: 60,
                          margin: const EdgeInsets.only(right: 12, left: 6),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      Container(
                        width: 76,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: isNow
                              ? Colors.blueAccent.withOpacity(0.15)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isNow
                                ? Colors.blueAccent.withOpacity(0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              timeLabel,
                              style: TextStyle(
                                color: isNow ? Colors.white : Colors.white54,
                                fontSize: 13,
                                fontWeight: isNow
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _getIcon(c, isDay, 36),
                            const SizedBox(height: 8),
                            Text(
                              '${t.round()}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.water_drop_rounded,
                                  size: 11,
                                  color: Colors.lightBlueAccent.withOpacity(
                                    0.7,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$r%',
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent.withOpacity(
                                      0.8,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
