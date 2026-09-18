import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/dashboard/dashboard_theme.dart';
import 'dashboard_weather_icons.dart';

class CityWeatherCard extends StatefulWidget {
  const CityWeatherCard({
    super.key,
    required this.name,
    required this.isPrimary,
    required this.data,
    required this.onSetPrimary,
    required this.onDelete,
  });

  final String name;
  final bool isPrimary;
  final Map<String, dynamic> data;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

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

    final now = DateTime.now();
    for (int i = 0; i < _hourlyTimes.length; i++) {
      final dt = DateTime.tryParse(_hourlyTimes[i].toString());
      if (dt != null &&
          dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day &&
          dt.hour == now.hour) {
        _nowHourlyIndex = i;
        break;
      }
    }

    _scrollController.addListener(() {
      if (_hourlyTimes.isEmpty) return;
      final offset = _scrollController.offset;
      final visibleOffset = (offset / 82.0).round();
      final firstVisibleIndex = (_nowHourlyIndex + visibleOffset).clamp(
        0,
        _hourlyTimes.length - 1,
      );

      final visibleDt = DateTime.tryParse(
        _hourlyTimes[firstVisibleIndex].toString(),
      );
      if (visibleDt != null) {
        final visibleDateStr = DateFormat('yyyy-MM-dd').format(visibleDt);
        final dayIdx = _dailyTimes.indexWhere(
          (d) => d.toString().startsWith(visibleDateStr),
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

  void _jumpToDay(int dayIndex) {
    if (dayIndex < 0 || dayIndex >= _dailyTimes.length) return;
    final targetDateStr = _dailyTimes[dayIndex].toString();
    final targetHourlyIndex = dayIndex == 0
        ? _nowHourlyIndex
        : _hourlyTimes.indexWhere(
            (h) => h.toString().startsWith(targetDateStr),
          );

    if (targetHourlyIndex != -1 && targetHourlyIndex >= _nowHourlyIndex) {
      setState(() => _activeDayIndex = dayIndex);
      final listIndex = targetHourlyIndex - _nowHourlyIndex;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          listIndex * 82.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  num? _numAt(dynamic list, int index) {
    if (list is! List || index < 0 || index >= list.length) return null;
    final value = list[index];
    return value is num ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final daily = widget.data['daily'] as Map<String, dynamic>? ?? {};
    final hourly = widget.data['hourly'] as Map<String, dynamic>? ?? {};
    final hourlyCount = (_hourlyTimes.length - _nowHourlyIndex).clamp(0, 1 << 20);

    if (_dailyTimes.isEmpty && hourlyCount == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: DashboardTheme.glassCard(tint: DashboardTheme.weather),
        child: Text(
          'No forecast yet for ${widget.name}.',
          style: const TextStyle(color: DashboardTheme.inkMuted, fontSize: 16),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: DashboardTheme.glassCard(
        tint: DashboardTheme.weather,
        emphasized: widget.isPrimary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 0, 10),
            child: SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _dailyTimes.length,
                itemBuilder: (ctx, i) {
                  final bool isActive = i == _activeDayIndex;
                  final dt = DateTime.tryParse(_dailyTimes[i].toString());
                  final String dayLabel = i == 0
                      ? 'TODAY'
                      : (dt != null
                            ? DateFormat('EEE d').format(dt).toUpperCase()
                            : 'DAY');

                  int code = _numAt(daily['weather_code'], i)?.toInt() ?? 1;
                  if (dt != null) {
                    final middayIdx = _hourlyTimes.indexWhere((h) {
                      final hDt = DateTime.tryParse(h.toString());
                      return hDt != null &&
                          hDt.year == dt.year &&
                          hDt.month == dt.month &&
                          hDt.day == dt.day &&
                          hDt.hour == 13;
                    });
                    final middayCode = _numAt(hourly['weather_code'], middayIdx);
                    if (middayCode != null) code = middayCode.toInt();
                  }

                  final maxT = _numAt(daily['temperature_2m_max'], i)?.toDouble() ?? 0;
                  final minT = _numAt(daily['temperature_2m_min'], i)?.toDouble() ?? 0;

                  return GestureDetector(
                    onTap: () => _jumpToDay(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 90,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? DashboardTheme.fade(Colors.blueAccent, 0.2)
                            : DashboardTheme.fade(Colors.white, 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive
                              ? DashboardTheme.fade(Colors.blueAccent, 0.8)
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
                          DashboardWeatherIcon(code: code, isDay: 1, size: 32),
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
          Divider(color: DashboardTheme.fade(Colors.white, 0.06), height: 1),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 120,
              child: hourlyCount == 0
                  ? const Center(
                      child: Text(
                        'Hourly forecast unavailable',
                        style: TextStyle(color: DashboardTheme.inkMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: hourlyCount,
                      itemBuilder: (ctx, i) {
                        final idx = _nowHourlyIndex + i;
                        if (idx >= _hourlyTimes.length) {
                          return const SizedBox.shrink();
                        }

                        final c = _numAt(hourly['weather_code'], idx)?.toInt() ?? 1;
                        final t =
                            _numAt(hourly['temperature_2m'], idx)?.toDouble() ??
                            0;
                        final r = _numAt(
                              hourly['precipitation_probability'],
                              idx,
                            )?.toInt() ??
                            0;
                        final isDay =
                            _numAt(hourly['is_day'], idx)?.toInt() ?? 1;

                        final dt = DateTime.tryParse(_hourlyTimes[idx].toString());
                        final timeLabel = dt != null
                            ? '${dt.hour.toString().padLeft(2, '0')}:00'
                            : '--:--';

                        final bool isNow = i == 0;
                        final bool isMidnight = dt != null && dt.hour == 0;

                        return Row(
                          children: [
                            if (isMidnight && !isNow)
                              Container(
                                width: 2,
                                height: 60,
                                margin: const EdgeInsets.only(
                                  right: 12,
                                  left: 6,
                                ),
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
                                    ? DashboardTheme.fade(Colors.blueAccent, 0.15)
                                    : DashboardTheme.fade(Colors.white, 0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isNow
                                      ? DashboardTheme.fade(
                                          Colors.blueAccent,
                                          0.5,
                                        )
                                      : Colors.transparent,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    timeLabel,
                                    style: TextStyle(
                                      color: isNow
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 13,
                                      fontWeight: isNow
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  DashboardWeatherIcon(
                                    code: c,
                                    isDay: isDay,
                                    size: 36,
                                  ),
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
                                        color: DashboardTheme.fade(
                                          Colors.lightBlueAccent,
                                          0.7,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '$r%',
                                        style: TextStyle(
                                          color: DashboardTheme.fade(
                                            Colors.lightBlueAccent,
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
