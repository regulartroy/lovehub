import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/dashboard/dashboard_theme.dart';

class DashboardOptionsScreen extends StatefulWidget {
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

  final double slideDuration;
  final ValueChanged<double> onDurationChanged;
  final List<Map<String, dynamic>> savedCities;
  final String primaryCity;
  final Function(String) onSetPrimary;
  final Function(String) onDeleteCity;
  final VoidCallback onAddCityTap;

  @override
  State<DashboardOptionsScreen> createState() => _DashboardOptionsScreenState();
}

class _DashboardOptionsScreenState extends State<DashboardOptionsScreen> {
  late double _currentSlideDuration;

  @override
  void initState() {
    super.initState();
    _currentSlideDuration = widget.slideDuration;
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: DashboardTheme.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Dashboard options',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          const Text(
            'SLIDE SPEED',
            style: TextStyle(
              color: DashboardTheme.inkMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            decoration: DashboardTheme.glassCard(tint: DashboardTheme.accent),
            child: Column(
              children: [
                Text(
                  '${_currentSlideDuration.toInt()} seconds per slide',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  value: _currentSlideDuration,
                  min: 5,
                  max: 60,
                  activeColor: DashboardTheme.accent,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    setState(() => _currentSlideDuration = v);
                    widget.onDurationChanged(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'WEATHER CITIES',
                  style: TextStyle(
                    color: DashboardTheme.inkMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.onAddCityTap,
                icon: const Icon(Icons.add, color: DashboardTheme.weather, size: 18),
                label: const Text(
                  'Add city',
                  style: TextStyle(color: DashboardTheme.weather),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (uid == null)
            const Text(
              'Sign in to manage weather cities.',
              style: TextStyle(color: DashboardTheme.inkMuted),
            )
          else
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Could not load cities. Try again in a moment.',
                      style: TextStyle(color: DashboardTheme.inkMuted),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: DashboardTheme.weather,
                      ),
                    ),
                  );
                }

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final List<dynamic> rawCities = data?['weatherCities'] ?? [];
                final List<Map<String, dynamic>> liveCities = rawCities.isEmpty
                    ? (widget.savedCities.isNotEmpty
                          ? widget.savedCities
                          : [
                              {'name': 'Brighton', 'lat': 50.82, 'lng': -0.13},
                            ])
                    : List<Map<String, dynamic>>.from(rawCities);
                final String livePrimary =
                    data?['primaryCity'] ?? widget.primaryCity;

                return Container(
                  decoration: DashboardTheme.glassCard(tint: DashboardTheme.weather),
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
