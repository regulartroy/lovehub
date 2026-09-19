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

  test('Tom and Maria keep the approved who colours', () {
    final palette = HubMemberPalette.fromMembers(members);

    expect(palette.whoColor('uid-tom'), CalendarColors.tom);
    expect(palette.whoColor('uid-maria'), CalendarColors.maria);
    expect(palette.whoColor('shared'), CalendarColors.shared);
    expect(CalendarColors.tom, const Color(0xFF5B8A8A));
    expect(CalendarColors.maria, const Color(0xFF3F8A70));
    expect(CalendarColors.shared, const Color(0xFFA89070));
  });

  test('Maria is a greener teal, not rose', () {
    expect(CalendarColors.maria.g, greaterThan(CalendarColors.maria.r));
    expect(CalendarColors.maria.g, greaterThan(CalendarColors.maria.b));
    expect(CalendarColors.maria.b, lessThan(CalendarColors.tom.b));
    expect(CalendarColors.maria.r, lessThan(CalendarColors.tom.r));
  });

  test('name matching is case-insensitive and ignores a Me label', () {
    final palette = HubMemberPalette.fromMembers([
      {'uid': 'uid-tom', 'name': 'Me', 'displayName': 'tom'},
      {'uid': 'uid-maria', 'displayName': 'MARIA'},
    ]);

    expect(palette.whoColor('uid-tom'), CalendarColors.tom);
    expect(palette.whoColor('uid-maria'), CalendarColors.maria);
  });

  test('extra members get distinct muted hues without stealing Tom or Maria', () {
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

  test('work is grey; leisure/personal is green; category beats who', () {
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
    expect(work.appointmentColor, CalendarColors.work);
    expect(work.glanceDot, CalendarColors.work);
    expect(personal.who, CalendarColors.maria);
    expect(personal.kind, CalendarColors.personal);
    expect(personal.glanceDot, CalendarColors.personal);
    expect(CalendarColors.work, const Color(0xFF6E7175));
    expect(CalendarColors.personal, const Color(0xFF3F9A55));
    expect(CalendarColors.work.r, closeTo(CalendarColors.work.g, 0.04));
    expect(CalendarColors.work.g, closeTo(CalendarColors.work.b, 0.04));
    expect(CalendarColors.personal.g, greaterThan(CalendarColors.personal.r));
    expect(CalendarColors.personal.g, greaterThan(CalendarColors.personal.b));
  });

  test('birthday purple is the glance signal; meal stays a quiet overlay', () {
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
    expect(birthday.special, CalendarColors.birthday);
    expect(birthday.glanceDot, CalendarColors.birthday);
    expect(birthday.signal, CalendarColors.birthday);
    expect(CalendarColors.birthday, const Color(0xFF7A4E9A));
    expect(CalendarColors.birthday.b, greaterThan(CalendarColors.birthday.r));
    expect(meal.who, CalendarColors.maria);
    expect(meal.special, CalendarColors.meal);
    expect(meal.kind, CalendarColors.personal);
    expect(meal.glanceDot, CalendarColors.meal);
    expect(CalendarColors.meal, const Color(0xFF8C7A64));
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
      dashboardGlanceColor(
        {'assignedTo': 'uid-tom', 'category': 'work'},
        palette: palette,
      ),
    );
  });
}
