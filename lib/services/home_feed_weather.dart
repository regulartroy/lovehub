import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'home_feed_logic.dart';

/// Turns an Open-Meteo forecast (same query as the dashboard forecast slide)
/// into a [FeedWeather]. Pure, for tests.
FeedWeather? parseHomeFeedWeather(
  String city,
  Map<String, dynamic> json,
  DateTime now,
) {
  final current = json['current'] as Map<String, dynamic>?;
  final hourly = json['hourly'] as Map<String, dynamic>?;
  final daily = json['daily'] as Map<String, dynamic>?;
  if (hourly == null) return null;
  final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
  final probs = (hourly['precipitation_probability'] as List?) ?? const [];
  var maxProb = 0;
  DateTime? rainFrom;
  final limit = now.add(const Duration(hours: 12));
  for (var i = 0; i < times.length && i < probs.length; i++) {
    final t = DateTime.tryParse(times[i]);
    if (t == null || t.isBefore(now.subtract(const Duration(hours: 1)))) {
      continue;
    }
    if (t.isAfter(limit)) break;
    final p = (probs[i] as num?)?.toInt() ?? 0;
    if (p > maxProb) maxProb = p;
    if (rainFrom == null && p >= 50) rainFrom = t;
  }
  double? first(String key) {
    final list = daily?[key] as List?;
    if (list == null || list.isEmpty) return null;
    return (list.first as num?)?.toDouble();
  }

  return FeedWeather(
    city: city,
    tempNow: (current?['temperature_2m'] as num?)?.toDouble(),
    todayMax: first('temperature_2m_max'),
    todayMin: first('temperature_2m_min'),
    rainChance: maxProb,
    rainFrom: rainFrom,
  );
}

/// The user's primary weather city (Brighton by default), from Open-Meteo.
/// Returns null on any failure: the weather card just stays hidden.
Future<FeedWeather?> fetchHomeFeedWeather(String uid) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = snap.data();
    final cities = List<Map<String, dynamic>>.from(
      (data?['weatherCities'] as List?) ?? const [],
    );
    final primary = data?['primaryCity'];
    final city =
        cities.where((c) => c['name'] == primary).firstOrNull ??
        (cities.isNotEmpty
            ? cities.first
            : {'name': 'Brighton', 'lat': 50.82, 'lng': -0.13});
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${city['lat']}'
      '&longitude=${city['lng']}&current=temperature_2m,weather_code'
      '&hourly=precipitation_probability'
      '&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return parseHomeFeedWeather(
      (city['name'] ?? 'Weather').toString(),
      json.decode(res.body) as Map<String, dynamic>,
      DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}
