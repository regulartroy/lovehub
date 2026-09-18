import 'package:flutter/material.dart';

class DashboardWeatherIcon extends StatelessWidget {
  const DashboardWeatherIcon({
    super.key,
    required this.code,
    required this.isDay,
    this.size = 24,
  });

  final int code;
  final int isDay;
  final double size;

  static bool isRainy(int code) =>
      (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;

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
    } else if (isRainy(code)) {
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
}
