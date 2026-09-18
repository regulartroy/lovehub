import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math; // <-- NEW: For the circular progress ring

class CycleScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const CycleScreen({super.key, required this.user, required this.visibleHubs});

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  String? _hubId;
  List<Map<String, dynamic>> _cycles = [];
  bool _isLoading = true;

  // --- ALGORITHM DEFAULTS ---
  int _avgCycleLength = 28;
  int _avgPeriodLength = 5;

  @override
  void initState() {
    super.initState();
    if (widget.visibleHubs.isNotEmpty) {
      _hubId = widget.visibleHubs.first.key;
      _listenToCycles();
    }
  }

  void _listenToCycles() {
    FirebaseFirestore.instance
        .collection('hubs')
        .doc(_hubId)
        .collection('cycles')
        .orderBy('startDate', descending: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;

          final cycles = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();

          if (cycles.length >= 2) {
            int totalCycleDays = 0;
            int validCycles = 0;

            for (int i = 0; i < cycles.length - 1; i++) {
              // --- FIXED: Safely handle pending server timestamps! ---
              final tCurrent = cycles[i]['startDate'] as Timestamp?;
              final tPrevious = cycles[i + 1]['startDate'] as Timestamp?;

              if (tCurrent != null && tPrevious != null) {
                DateTime currentStart = tCurrent.toDate();
                DateTime previousStart = tPrevious.toDate();
                totalCycleDays += currentStart.difference(previousStart).inDays;
                validCycles++;
              }
            }

            if (validCycles > 0) {
              _avgCycleLength = (totalCycleDays / validCycles).round();
            }
          }

          setState(() {
            _cycles = cycles;
            _isLoading = false;
          });
        });
  }

  // --- DATABASE ACTIONS ---
  Future<void> _logPeriodStart() async {
    await FirebaseFirestore.instance
        .collection('hubs')
        .doc(_hubId)
        .collection('cycles')
        .add({
          'startDate': FieldValue.serverTimestamp(),
          'endDate': null, // Null means they are currently ON their period
          'loggedBy': widget.user.uid,
        });
  }

  Future<void> _logPeriodEnd(String cycleId) async {
    await FirebaseFirestore.instance
        .collection('hubs')
        .doc(_hubId)
        .collection('cycles')
        .doc(cycleId)
        .update({'endDate': FieldValue.serverTimestamp()});
  }

  Future<void> _deleteCycle(String cycleId) async {
    await FirebaseFirestore.instance
        .collection('hubs')
        .doc(_hubId)
        .collection('cycles')
        .doc(cycleId)
        .delete();
  }

  // --- NEW: Helper to check if a day is already part of a logged cycle ---
  bool _isDayAlreadyLogged(DateTime day) {
    final checkDate = DateUtils.dateOnly(day);
    for (var c in _cycles) {
      if (c['startDate'] == null) continue;

      DateTime start = DateUtils.dateOnly(
        (c['startDate'] as Timestamp).toDate(),
      );
      DateTime end = c['endDate'] != null
          ? DateUtils.dateOnly((c['endDate'] as Timestamp).toDate())
          : DateUtils.dateOnly(DateTime.now());

      if ((checkDate.isAtSameMomentAs(start) || checkDate.isAfter(start)) &&
          (checkDate.isAtSameMomentAs(end) || checkDate.isBefore(end))) {
        return true; // It's already logged!
      }
    }
    return false;
  }

  // --- NEW: Helper to find a valid initial date so the picker doesn't crash ---
  DateTime _getSafeInitialDate(DateTime proposed) {
    DateTime check = DateUtils.dateOnly(proposed);
    // Look backwards until we find a free day (caps at 100 days to prevent loops)
    for (int i = 0; i < 100; i++) {
      if (!_isDayAlreadyLogged(check)) return check;
      check = check.subtract(const Duration(days: 1));
    }
    return DateTime.now(); // Ultimate fallback
  }

  // --- NEW: BACKFILL HISTORICAL DATA (Upgraded UX with overlap protection) ---
  Future<void> _logPastCycle() async {
    final DateTime now = DateTime.now();
    final DateTime proposedStart = now.subtract(const Duration(days: 28));
    final DateTime safeInitialStart = _getSafeInitialDate(proposedStart);

    // STEP 1: Pick the Start Date
    final DateTime? startDate = await showDatePicker(
      context: context,
      initialDate: safeInitialStart,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'SELECT PERIOD START DATE',
      // --- NEW: Greys out days you've already logged! ---
      selectableDayPredicate: (DateTime day) => !_isDayAlreadyLogged(day),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.pinkAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (startDate == null) return; // User cancelled

    // STEP 2: Pick the End Date
    DateTime proposedEnd = startDate.add(const Duration(days: 4));
    if (proposedEnd.isAfter(now)) proposedEnd = now;
    final DateTime safeInitialEnd = _getSafeInitialDate(proposedEnd);

    final DateTime? endDate = await showDatePicker(
      context: context,
      initialDate: safeInitialEnd.isBefore(startDate)
          ? startDate
          : safeInitialEnd,
      firstDate: startDate,
      lastDate: now,
      helpText: 'SELECT PERIOD END DATE',
      // --- NEW: Greys out days you've already logged! ---
      selectableDayPredicate: (DateTime day) => !_isDayAlreadyLogged(day),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.pinkAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (endDate != null) {
      // Save both exact dates to the database!
      await FirebaseFirestore.instance
          .collection('hubs')
          .doc(_hubId)
          .collection('cycles')
          .add({
            'startDate': Timestamp.fromDate(startDate),
            'endDate': Timestamp.fromDate(endDate),
            'loggedBy': widget.user.uid,
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hubId == null) return const Center(child: Text("Join a hub first"));
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.pinkAccent),
      );

    final now = DateUtils.dateOnly(DateTime.now());

    // --- STATE CALCULATION ---
    Map<String, dynamic>? activeCycle;
    Map<String, dynamic>? lastCycle;

    if (_cycles.isNotEmpty) {
      if (_cycles.first['endDate'] == null) {
        activeCycle = _cycles.first;
      } else {
        lastCycle = _cycles.first;
      }
    }

    // Predictive Math
    DateTime? nextPeriodStart;
    DateTime? nextOvulation;
    String statusText = "Ready to log";
    String subStatusText = "Tap below to start your cycle";
    Color statusColor = Colors.grey.shade400;

    int currentDayOfCycle = 1; // <-- NEW: Universal tracker for the ring

    if (activeCycle != null) {
      DateTime start =
          (activeCycle['startDate'] as Timestamp?)?.toDate() ?? now;
      // --- FIXED: Capture the day for the ring! ---
      currentDayOfCycle = now.difference(DateUtils.dateOnly(start)).inDays + 1;

      statusText = "Day $currentDayOfCycle";
      subStatusText = "Period";
      statusColor = Colors.redAccent;
    } else if (lastCycle != null) {
      DateTime lastStart =
          (lastCycle['startDate'] as Timestamp?)?.toDate() ?? now;
      // --- FIXED: Capture the day for the ring! ---
      currentDayOfCycle =
          now.difference(DateUtils.dateOnly(lastStart)).inDays + 1;

      nextPeriodStart = lastStart.add(Duration(days: _avgCycleLength));

      // Ovulation is always 14 days BEFORE the next period
      nextOvulation = nextPeriodStart.subtract(const Duration(days: 14));

      DateTime fertileStart = nextOvulation.subtract(const Duration(days: 5));
      DateTime fertileEnd = nextOvulation.add(const Duration(days: 1));

      int daysUntilPeriod = DateUtils.dateOnly(
        nextPeriodStart,
      ).difference(now).inDays;

      if (daysUntilPeriod == 0) {
        statusText = "Today";
        subStatusText = "Period due";
        statusColor = Colors.redAccent;
      } else if (daysUntilPeriod < 0) {
        statusText = "${daysUntilPeriod.abs()} Days";
        subStatusText = "Late";
        statusColor = Colors.orangeAccent;
      } else if (now.isAfter(fertileStart.subtract(const Duration(days: 1))) &&
          now.isBefore(fertileEnd.add(const Duration(days: 1)))) {
        // IN FERTILE WINDOW
        if (DateUtils.isSameDay(now, nextOvulation)) {
          statusText = "Ovulation";
          subStatusText = "High chance of pregnancy";
          statusColor = Colors.tealAccent.shade700;
        } else {
          statusText = "Fertile";
          subStatusText = "Window";
          statusColor = Colors.teal.shade300;
        }
      } else {
        // REGULAR FOLLICULAR / LUTEAL PHASE
        statusText = "$daysUntilPeriod Days";
        subStatusText = "Until next period";
        statusColor = Colors.pinkAccent;
      }
    }

    return Scaffold(
      backgroundColor: Colors.pink.shade50,
      appBar: AppBar(
        title: Text(
          "Cycle",
          style: TextStyle(
            color: Colors.pink.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // --- THE MAIN STATUS RING ---
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // --- NEW: THE DOTTED CYCLE RING ---
                  SizedBox(
                    width: 310,
                    height: 310,
                    child: CustomPaint(
                      painter: CycleRingPainter(
                        totalDays: _avgCycleLength,
                        currentDay: currentDayOfCycle,
                        periodLength: _avgPeriodLength,
                      ),
                    ),
                  ),

                  // The Inner Status Circle
                  Container(
                    width: 240, // Scaled down slightly to fit inside the dots
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                      border: Border.all(
                        color: statusColor.withOpacity(0.1),
                        width: 4,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 32, // Scaled down slightly
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            subStatusText.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // --- THE ACTION BUTTON ---
            if (activeCycle != null)
              FilledButton.icon(
                onPressed: () => _logPeriodEnd(activeCycle!['id']),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text("End Period"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _logPeriodStart,
                icon: const Icon(Icons.water_drop),
                label: const Text("Log Period Start"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // --- NEW: The Historical Entry Button ---
            TextButton.icon(
              onPressed: _logPastCycle,
              icon: Icon(Icons.history, color: Colors.grey.shade600, size: 20),
              label: Text(
                "Log past cycle",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),

            const SizedBox(height: 32),

            // --- PREDICTIONS & STATS CARD ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "INSIGHTS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatColumn(
                          "Avg Cycle",
                          "$_avgCycleLength Days",
                          Icons.sync,
                        ),
                        _buildStatColumn(
                          "Avg Period",
                          "$_avgPeriodLength Days",
                          Icons.water_drop_outlined,
                        ),
                        if (nextOvulation != null)
                          _buildStatColumn(
                            "Ovulation",
                            DateFormat('d MMM').format(nextOvulation),
                            Icons.egg_alt_outlined,
                          )
                        else
                          _buildStatColumn(
                            "Ovulation",
                            "Need data",
                            Icons.egg_alt_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --- CYCLE HISTORY ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  "HISTORY",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (_cycles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "No cycles logged yet. Tap the button above when your period starts.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // To this:
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 40),
                itemCount: _cycles.length,
                itemBuilder: (context, index) {
                  final cycle = _cycles[index];
                  // --- FIXED: Safe parsing ---
                  DateTime start =
                      (cycle['startDate'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  DateTime? end = cycle['endDate'] != null
                      ? (cycle['endDate'] as Timestamp?)?.toDate()
                      : null;
                  String dateString = DateFormat('d MMM yyyy').format(start);
                  if (end != null) {
                    dateString += " - ${DateFormat('d MMM yyyy').format(end)}";
                  } else {
                    dateString += " - Present";
                  }

                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.water_drop,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        dateString,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        end != null
                            ? "Duration: ${end.difference(start).inDays + 1} days"
                            : "Active period",
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.grey,
                        ),
                        onPressed: () => _deleteCycle(cycle['id']),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.pink.shade300, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.pink.shade900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

// --- NEW: THE FLO-STYLE CYCLE RING PAINTER ---
class CycleRingPainter extends CustomPainter {
  final int totalDays;
  final int currentDay;
  final int periodLength;

  CycleRingPainter({
    required this.totalDays,
    required this.currentDay,
    required this.periodLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // Ovulation is always 14 days before the NEXT period (so Total - 14 + 1 for 1-indexing)
    int ovulationDay = totalDays - 14 + 1;

    for (int i = 1; i <= totalDays; i++) {
      // Start at the top (-pi/2) and draw clockwise
      double angle = -math.pi / 2 + (2 * math.pi * (i - 1) / totalDays);
      Offset dotCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      // 1. Color Code the Dots
      if (i <= periodLength) {
        paint.color = Colors.redAccent; // Period
      } else if (i >= ovulationDay - 5 && i <= ovulationDay) {
        // Fertile Window (6 days)
        paint.color = i == ovulationDay
            ? Colors.tealAccent.shade700
            : Colors.teal.shade300;
      } else {
        paint.color = Colors.grey.shade300; // Regular days
      }

      // 2. Size and Highlight the Current Day
      double dotRadius = 4.5;

      // If late, cap the visual highlight at the last day
      int displayDay = currentDay > totalDays ? totalDays : currentDay;

      if (i == displayDay) {
        dotRadius = 8.0;
        // Draw a soft glowing halo around the current day
        canvas.drawCircle(
          dotCenter,
          14,
          Paint()
            ..color = paint.color.withOpacity(0.3)
            ..style = PaintingStyle.fill,
        );
        // Draw a crisp ring around the halo
        canvas.drawCircle(
          dotCenter,
          14,
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      // Draw the actual day dot
      canvas.drawCircle(dotCenter, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
