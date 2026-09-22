import 'package:flutter/material.dart';

import '../models/event_model.dart';

/// Shared calendar colour system for the Calendar tab and Dashboard glances.
///
/// Event chips are a **split pill**: left ~1/3 is **who**, right ~2/3 is
/// **kind** (category). Title and time sit on the category side with
/// contrast-safe ink. Syncfusion / month appointment blocks only take one
/// colour, so those use the person fill.
class CalendarColors {
  CalendarColors._();

  // Who — left third of the split pill
  static const Color tom = Color(0xFF3B7DD8); // clear blue
  static const Color maria = Color(0xFFE0B84A); // kitchen-tablet yellow
  static const Color shared = Color(0xFFC45BA0); // cooler magenta / pink

  // Kind — right two-thirds of the split pill
  static const Color work = Color(0xFF6E7175); // stone grey
  static const Color personal = Color(0xFF2F9A62); // leisure / general green

  // Special category fills / icon accents
  static const Color birthday = Color(0xFF8B5BB5); // purple category fill
  static const Color meal = Color(0xFFC48462); // quiet terracotta accent

  static const Color darkInk = Color(0xFF1C1914);
  static const Color lightInk = Color(0xFFF7F3EC);

  /// Extra household members stay distinct from Tom / Maria / Shared.
  static const List<Color> extraMemberHues = [
    Color(0xFF4A90A8), // clear teal
    Color(0xFFD0896A), // warm clay
    Color(0xFF6A9A5A), // olive
    Color(0xFF7A6AA8), // cool violet
  ];

  static const Color unknownMember = Color(0xFF7A7A80);

  /// Readable ink for a solid fill. Maria yellow needs dark; the rest
  /// of the kitchen-tablet palette reads better in warm white.
  static Color inkOn(Color fill) {
    return fill.computeLuminance() > 0.45 ? darkInk : lightInk;
  }

  /// Right-side category fill. Birthday is purple; meals fold into leisure
  /// so the glance set stays grey / green / purple.
  static Color categoryFill(String category) {
    switch (category) {
      case 'work':
        return work;
      case 'birthday':
        return birthday;
      default:
        return personal;
    }
  }

  /// Lift a booked colour toward warm paper so a tentative shift reads as a
  /// sketch: still the same hue, quieter than Tom blue or work grey, dark ink.
  static Color mute(Color color) {
    return Color.lerp(const Color(0xFFE6E1D6), color, 0.30)!;
  }

  static CalendarEventStyle resolve({
    required String assignedTo,
    String category = 'general',
    String? status,
    HubMemberPalette? palette,
  }) {
    final whoPalette = palette ?? HubMemberPalette.empty;
    final who = whoPalette.whoColor(assignedTo);
    final kind = categoryFill(category);
    Color? special;
    if (category == 'birthday') {
      special = birthday;
    } else if (category == 'meal') {
      special = meal;
    }
    final tentative = isTentativeEventStatus(status);
    if (!tentative) {
      return CalendarEventStyle(who: who, kind: kind, special: special);
    }
    return CalendarEventStyle(
      who: mute(who),
      kind: mute(kind),
      special: special == null ? null : mute(special),
      tentative: true,
    );
  }

  static CalendarEventStyle fromEvent(
    EventModel event, {
    HubMemberPalette? palette,
  }) {
    return resolve(
      assignedTo: event.assignedTo,
      category: event.category,
      status: event.status,
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
      status: data['status']?.toString(),
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

/// Resolved colours for one event.
///
/// [who] paints the left third. [kind] paints the right two-thirds
/// (work grey, leisure green, or birthday purple). [special] is an icon
/// accent — birthday purple or meal terracotta.
class CalendarEventStyle {
  const CalendarEventStyle({
    required this.who,
    required this.kind,
    this.special,
    this.tentative = false,
  });

  final Color who;
  final Color kind;
  final Color? special;

  /// Provisional work date. Chips mute [who] and [kind] and show a question mark.
  final bool tentative;

  /// Category fill used by chips, dots, and the right half of the pill.
  Color get signal => kind;

  /// Syncfusion `Appointment.color` — person only; list chips stay split.
  Color get appointmentColor => who;

  /// Heatmap / month-grid dot. Category first; person is a tiny accent.
  Color get glanceDot => kind;

  Color get inkOnWho => CalendarColors.inkOn(who);
  Color get inkOnKind => CalendarColors.inkOn(kind);

  Color washLight([double strength = 0.18]) =>
      Color.lerp(const Color(0xFFFFFBF7), kind, strength)!;

  Color washDark([double strength = 0.16]) => kind.withValues(alpha: strength);

  Color outlineLight([double strength = 0.32]) =>
      Color.lerp(Colors.white, kind, strength)!;
}

/// Stable who-colour map for a hub. Tom and Maria keep the approved colours
/// when their display names contain those tokens; everyone else gets a
/// distinct extra hue. `assignedTo == 'shared'` is always cooler magenta.
class HubMemberPalette {
  const HubMemberPalette({
    Map<String, Color> whoByUid = const {},
    Map<String, String> namesByUid = const {},
  }) : _whoByUid = whoByUid,
       _namesByUid = namesByUid;

  static const HubMemberPalette empty = HubMemberPalette();

  final Map<String, Color> _whoByUid;
  final Map<String, String> _namesByUid;

  factory HubMemberPalette.fromMembers(Iterable<Map<String, dynamic>> members) {
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
      whoByUid[member.uid] = CalendarColors
          .extraMemberHues[extraIndex % CalendarColors.extraMemberHues.length];
      extraIndex++;
    }

    return HubMemberPalette(whoByUid: whoByUid, namesByUid: namesByUid);
  }

  Color whoColor(String assignedTo) {
    if (assignedTo.isEmpty || assignedTo == 'shared') {
      return CalendarColors.shared;
    }
    final direct = _whoByUid[assignedTo];
    if (direct != null) return direct;
    for (final uid in _whoByUid.keys) {
      if (samePerson(assignedTo, uid)) {
        return _whoByUid[uid]!;
      }
    }
    // Imported rota rows use the tokens Roger was given, even before the
    // hub member list has loaded.
    final token = assignedTo.trim().toLowerCase();
    if (token == 'tom') return CalendarColors.tom;
    if (token == 'maria') return CalendarColors.maria;
    return CalendarColors.unknownMember;
  }

  /// True when [assignedTo] is this member's uid or a name token such as `tom`.
  bool samePerson(String assignedTo, String uid) {
    if (assignedTo == uid) return true;
    final token = assignedTo.trim().toLowerCase();
    if (token.isEmpty || token == 'shared') return false;
    final name = (_namesByUid[uid] ?? '').toLowerCase();
    if (name.isEmpty) return false;
    final first = name.split(RegExp(r'\s+')).first;
    if (name == token || first == token) return true;
    if ((token == 'tom' || token == 'maria') && name.contains(token)) {
      return true;
    }
    return false;
  }

  /// Member chip filter: shared stays visible; `tom` matches Tom's uid.
  bool visibleForFilter(String assignedTo, String? selectedUid) {
    if (selectedUid == null || selectedUid.isEmpty) return true;
    if (assignedTo == 'shared') return true;
    if (assignedTo == selectedUid) return true;
    return samePerson(assignedTo, selectedUid);
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
    CalendarLegendSwatch(
      color: CalendarColors.work,
      label: 'Work',
      category: true,
    ),
    CalendarLegendSwatch(
      color: CalendarColors.personal,
      label: 'Leisure',
      category: true,
    ),
    CalendarLegendSwatch(
      color: CalendarColors.birthday,
      label: 'Birthdays',
      category: true,
    ),
  ];
}

class CalendarLegendSwatch {
  const CalendarLegendSwatch({
    required this.color,
    required this.label,
    this.category = false,
  });

  final Color color;
  final String label;
  final bool category;
}
