import 'package:flutter/material.dart';

import '../models/event_model.dart';

/// Shared calendar colour system for the Calendar tab and Dashboard glances.
///
/// **Who** is the base fill / chip tint. **Kind** is a quieter accent
/// (left stripe, icon tint). Birthday and meal sit on top as muted overlays
/// so they never shout louder than the person colours.
class CalendarColors {
  CalendarColors._();

  // Who — approved household fills
  static const Color tom = Color(0xFF5B8A8A); // dusty teal
  static const Color maria = Color(0xFFB07A8A); // soft rose
  static const Color shared = Color(0xFFA89070); // warm sand

  // Kind — subtle accents, not neon fills
  static const Color work = Color(0xFF6B7C9C); // slate blue
  static const Color personal = Color(0xFF7A9A7E); // soft sage

  // Special overlays — readable, quieter than who colours
  static const Color birthday = Color(0xFF8A7A92); // muted lilac
  static const Color meal = Color(0xFF8C7A64); // muted terracotta

  /// Extra household members stay in the same dusty/muted family.
  static const List<Color> extraMemberHues = [
    Color(0xFF6E8088), // dusty slate
    Color(0xFF8C7A72), // muted clay
    Color(0xFF748878), // faded olive
    Color(0xFF7A7280), // muted mauve
  ];

  static const Color unknownMember = Color(0xFF7A7A74);

  static CalendarEventStyle resolve({
    required String assignedTo,
    String category = 'general',
    HubMemberPalette? palette,
  }) {
    final whoPalette = palette ?? HubMemberPalette.empty;
    final who = whoPalette.whoColor(assignedTo);
    final kind = category == 'work' ? work : personal;
    Color? special;
    if (category == 'birthday') {
      special = birthday;
    } else if (category == 'meal') {
      special = meal;
    }
    return CalendarEventStyle(who: who, kind: kind, special: special);
  }

  static CalendarEventStyle fromEvent(
    EventModel event, {
    HubMemberPalette? palette,
  }) {
    return resolve(
      assignedTo: event.assignedTo,
      category: event.category,
      palette: palette,
    );
  }

  static CalendarEventStyle fromMap(
    Map<String, dynamic> data, {
    HubMemberPalette? palette,
  }) {
    return resolve(
      assignedTo: (data['assignedTo'] ?? 'shared').toString(),
      category: (data['category'] ?? 'general').toString(),
      palette: palette,
    );
  }

  /// Filter / create-sheet chip colour for a category (kind or special).
  static Color categoryTint(String category) {
    switch (category) {
      case 'work':
        return work;
      case 'birthday':
        return birthday;
      case 'meal':
        return meal;
      default:
        return personal;
    }
  }
}

/// Resolved colours for one event. Use [who] as the fill, [kind] as the
/// accent stripe, and [special] only as a small overlay.
class CalendarEventStyle {
  const CalendarEventStyle({
    required this.who,
    required this.kind,
    this.special,
  });

  final Color who;
  final Color kind;
  final Color? special;

  /// Syncfusion `Appointment.color` and any other appointment API.
  Color get appointmentColor => who;

  /// Heatmap / month-grid dot. Person first; special stays an overlay.
  Color get glanceDot => who;

  Color washLight([double strength = 0.18]) =>
      Color.lerp(const Color(0xFFFFFBF7), who, strength)!;

  Color washDark([double strength = 0.16]) => who.withValues(alpha: strength);

  Color outlineLight([double strength = 0.32]) =>
      Color.lerp(Colors.white, who, strength)!;
}

/// Stable who-colour map for a hub. Tom and Maria keep the approved colours
/// when their display names contain those tokens; everyone else gets a muted
/// extra hue. `assignedTo == 'shared'` is always warm sand.
class HubMemberPalette {
  const HubMemberPalette({
    Map<String, Color> whoByUid = const {},
    Map<String, String> namesByUid = const {},
  }) : _whoByUid = whoByUid,
       _namesByUid = namesByUid;

  static const HubMemberPalette empty = HubMemberPalette();

  final Map<String, Color> _whoByUid;
  final Map<String, String> _namesByUid;

  factory HubMemberPalette.fromMembers(
    Iterable<Map<String, dynamic>> members,
  ) {
    final parsed = members
        .map((member) {
          final uid = (member['uid'] ?? '').toString();
          final name = (member['displayName'] ?? member['name'] ?? '')
              .toString();
          return (uid: uid, name: name);
        })
        .where((member) => member.uid.isNotEmpty && member.uid != 'shared')
        .toList();

    parsed.sort((a, b) => a.uid.compareTo(b.uid));

    String? tomUid;
    String? mariaUid;
    for (final member in parsed) {
      final lower = member.name.toLowerCase();
      if (tomUid == null && lower.contains('tom')) tomUid = member.uid;
      if (mariaUid == null && lower.contains('maria')) mariaUid = member.uid;
    }

    final whoByUid = <String, Color>{};
    final namesByUid = <String, String>{};
    if (tomUid != null) whoByUid[tomUid] = CalendarColors.tom;
    if (mariaUid != null) whoByUid[mariaUid] = CalendarColors.maria;

    var extraIndex = 0;
    for (final member in parsed) {
      namesByUid[member.uid] = member.name;
      if (whoByUid.containsKey(member.uid)) continue;
      whoByUid[member.uid] =
          CalendarColors.extraMemberHues[extraIndex %
              CalendarColors.extraMemberHues.length];
      extraIndex++;
    }

    return HubMemberPalette(whoByUid: whoByUid, namesByUid: namesByUid);
  }

  Color whoColor(String assignedTo) {
    if (assignedTo.isEmpty || assignedTo == 'shared') {
      return CalendarColors.shared;
    }
    return _whoByUid[assignedTo] ?? CalendarColors.unknownMember;
  }

  String labelFor(String uid) => _namesByUid[uid] ?? uid;

  List<CalendarLegendSwatch> whoLegend({
    String Function(String uid, String name)? labelForMember,
  }) {
    final items = <CalendarLegendSwatch>[];
    final uids = _whoByUid.keys.toList()..sort();
    for (final uid in uids) {
      final name = _namesByUid[uid] ?? uid;
      items.add(
        CalendarLegendSwatch(
          color: _whoByUid[uid]!,
          label: labelForMember?.call(uid, name) ?? name,
        ),
      );
    }
    items.add(
      const CalendarLegendSwatch(color: CalendarColors.shared, label: 'Shared'),
    );
    return items;
  }

  List<CalendarLegendSwatch> kindLegend() => const [
    CalendarLegendSwatch(color: CalendarColors.work, label: 'Work'),
    CalendarLegendSwatch(color: CalendarColors.personal, label: 'Personal'),
  ];
}

class CalendarLegendSwatch {
  const CalendarLegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;
}
