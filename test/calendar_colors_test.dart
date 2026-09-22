import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/models/event_model.dart';
import 'package:lovehub/theme/calendar_colors.dart';
import 'package:lovehub/widgets/dashboard/dashboard_calendar_overview.dart';

void main() {
  final members = [
    {'uid': 'uid-tom', 'displayName': 'Tom Hughes'},
    {'uid': 'uid-maria', 'name': 'maria cole'},
  ];

  test('Tom, Maria, and Shared keep the approved who colours', () {
    final palette = HubMemberPalette.fromMembers(members);

    expect(palette.whoColor('uid-tom'), CalendarColors.tom);
    expect(palette.whoColor('uid-maria'), CalendarColors.maria);
    expect(palette.whoColor('shared'), CalendarColors.shared);
    expect(CalendarColors.tom, const Color(0xFF3B7DD8));
    expect(CalendarColors.maria, const Color(0xFFE0B84A));
    expect(CalendarColors.shared, const Color(0xFFC45BA0));
  });

  test('Maria yellow is distinct from Shared pink', () {
    expect(CalendarColors.maria, isNot(CalendarColors.shared));
    expect(CalendarColors.maria.g, greaterThan(CalendarColors.shared.g));
    expect(CalendarColors.maria.b, lessThan(CalendarColors.shared.b));
    expect(CalendarColors.tom.b, greaterThan(CalendarColors.tom.r));
  });

  test('name matching is case-insensitive and ignores a Me label', () {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'uid-tom', 'name': 'Me', 'displayName': 'tom'},
      {'uid': 'uid-maria', 'displayName': 'MARIA'},
    ]);

    expect(palette.whoColor('uid-tom'), CalendarColors.tom);
    expect(palette.whoColor('uid-maria'), CalendarColors.maria);
  });

  test('extra members get distinct hues without stealing Tom or Maria', () {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'a', 'name': 'Alex'},
      {'uid': 'b', 'name': 'Blake'},
      {'uid': 't', 'name': 'Tom'},
      {'uid': 'm', 'name': 'Maria'},
    ]);

    expect(palette.whoColor('t'), CalendarColors.tom);
    expect(palette.whoColor('m'), CalendarColors.maria);
    expect(palette.whoColor('a'), isNot(CalendarColors.tom));
    expect(palette.whoColor('a'), isNot(CalendarColors.maria));
    expect(palette.whoColor('a'), isNot(CalendarColors.shared));
    expect(palette.whoColor('b'), isNot(palette.whoColor('a')));
    expect(
      CalendarColors.extraMemberHues,
      containsAll([palette.whoColor('a'), palette.whoColor('b')]),
    );
  });

  test(
    'work is grey; leisure is green; appointments keep the person colour',
    () {
      final palette = HubMemberPalette.fromMembers(members);

      final work = CalendarColors.resolve(
        assignedTo: 'uid-tom',
        category: 'work',
        palette: palette,
      );
      final personal = CalendarColors.resolve(
        assignedTo: 'uid-maria',
        category: 'general',
        palette: palette,
      );

      expect(work.who, CalendarColors.tom);
      expect(work.kind, CalendarColors.work);
      expect(work.appointmentColor, CalendarColors.tom);
      expect(work.glanceDot, CalendarColors.work);
      expect(personal.who, CalendarColors.maria);
      expect(personal.kind, CalendarColors.personal);
      expect(personal.glanceDot, CalendarColors.personal);
      expect(CalendarColors.work, const Color(0xFF6E7175));
      expect(CalendarColors.personal, const Color(0xFF2F9A62));
      expect(CalendarColors.work.r, closeTo(CalendarColors.work.g, 0.04));
      expect(CalendarColors.work.g, closeTo(CalendarColors.work.b, 0.04));
      expect(CalendarColors.personal.g, greaterThan(CalendarColors.personal.r));
      expect(CalendarColors.personal.g, greaterThan(CalendarColors.personal.b));
    },
  );

  test('birthday purple fills the category side; meals fold into leisure', () {
    final palette = HubMemberPalette.fromMembers(members);
    final birthday = CalendarColors.fromMap({
      'assignedTo': 'shared',
      'category': 'birthday',
    }, palette: palette);
    final meal = CalendarColors.fromMap({
      'assignedTo': 'uid-maria',
      'category': 'meal',
    }, palette: palette);

    expect(birthday.who, CalendarColors.shared);
    expect(birthday.kind, CalendarColors.birthday);
    expect(birthday.special, CalendarColors.birthday);
    expect(birthday.glanceDot, CalendarColors.birthday);
    expect(birthday.signal, CalendarColors.birthday);
    expect(CalendarColors.birthday, const Color(0xFF8B5BB5));
    expect(CalendarColors.birthday.b, greaterThan(CalendarColors.birthday.r));
    expect(meal.who, CalendarColors.maria);
    expect(meal.special, CalendarColors.meal);
    expect(meal.kind, CalendarColors.personal);
    expect(meal.glanceDot, CalendarColors.personal);
    expect(CalendarColors.meal, const Color(0xFFC48462));
  });

  test(
    'ink on Maria yellow is dark; ink on green, blue, grey, and purple is light',
    () {
      expect(
        CalendarColors.inkOn(CalendarColors.maria),
        CalendarColors.darkInk,
      );
      expect(
        CalendarColors.inkOn(CalendarColors.personal),
        CalendarColors.lightInk,
      );
      expect(
        CalendarColors.inkOn(CalendarColors.work),
        CalendarColors.lightInk,
      );
      expect(CalendarColors.inkOn(CalendarColors.tom), CalendarColors.lightInk);
      expect(
        CalendarColors.inkOn(CalendarColors.birthday),
        CalendarColors.lightInk,
      );
      expect(
        CalendarColors.inkOn(CalendarColors.shared),
        CalendarColors.lightInk,
      );
    },
  );

  test('imported tom token is Tom blue and work grey', () {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'firebaseUidTom', 'displayName': 'Tom Workman'},
      {'uid': 'firebaseUidMaria', 'displayName': 'Maria Cole'},
    ]);

    final style = CalendarColors.resolve(
      assignedTo: 'tom',
      category: 'work',
      palette: palette,
    );

    expect(style.who, CalendarColors.tom);
    expect(style.kind, CalendarColors.work);
    expect(style.appointmentColor, CalendarColors.tom);
    expect(style.glanceDot, CalendarColors.work);
    expect(palette.samePerson('tom', 'firebaseUidTom'), isTrue);
    expect(palette.samePerson('tom', 'firebaseUidMaria'), isFalse);
    expect(palette.visibleForFilter('tom', 'firebaseUidTom'), isTrue);
    expect(palette.visibleForFilter('tom', 'firebaseUidMaria'), isFalse);
    expect(palette.visibleForFilter('shared', 'firebaseUidTom'), isTrue);
    expect(
      CalendarColors.resolve(
        assignedTo: 'tom',
        category: 'work',
        palette: HubMemberPalette.empty,
      ).who,
      CalendarColors.tom,
    );
  });

  test('EventModel and glance helper share the same category colour', () {
    final palette = HubMemberPalette.fromMembers(members);
    final event = EventModel(
      id: '1',
      summary: 'Shift',
      start: DateTime(2026, 9, 19, 8),
      end: DateTime(2026, 9, 19, 16),
      category: 'work',
      assignedTo: 'uid-tom',
    );

    expect(
      CalendarColors.fromEvent(event, palette: palette).glanceDot,
      dashboardGlanceColor({
        'assignedTo': 'uid-tom',
        'category': 'work',
      }, palette: palette),
    );
  });
}
