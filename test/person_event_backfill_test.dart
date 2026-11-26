import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/event_import/person_event_backfill.dart';

PersonBackfillCandidate cand({
  required String hubId,
  required String eventId,
  required String summary,
  String category = 'work',
  String assignedTo = 'tom-uid',
  String? ownerId = 'tom-uid',
  String? source,
  String? externalId,
  String? status,
  DateTime? updateTime,
}) {
  return PersonBackfillCandidate(
    hubId: hubId,
    eventId: eventId,
    updateTime: updateTime,
    fields: {
      'summary': summary,
      'category': category,
      'assignedTo': assignedTo,
      if (ownerId != null) 'ownerId': ownerId,
      if (source != null) 'source': source,
      if (externalId != null) 'externalId': externalId,
      if (status != null) 'status': status,
      'start': DateTime.utc(2026, 12, 6, 15),
      'end': DateTime.utc(2026, 12, 6, 20),
      'allDay': false,
    },
  );
}

void main() {
  const burroni = defaultBurroniHubId;
  const paddyHub = 'EJZWvXNbW3YopoKvBsch';
  const tom = 'tom-uid';
  const maria = 'maria-uid';
  const paddy = 'paddy-uid';

  test('skips joint shared events including the 28 Nov date day', () {
    final plan = planPersonEventBackfill([
      cand(
        hubId: burroni,
        eventId: 'renoir:2026-11-28-date-day',
        summary: 'Date day',
        category: 'personal',
        assignedTo: 'shared',
        ownerId: tom,
        source: 'renoir',
        externalId: '2026-11-28-date-day',
      ),
      cand(
        hubId: burroni,
        eventId: 'meal-1',
        summary: 'Pizza',
        category: 'meal',
        assignedTo: 'shared',
        ownerId: null,
      ),
    ]);
    expect(plan.writes, isEmpty);
    expect(plan.skippedJoint, hasLength(2));
    expect(
      plan.skippedJoint.map((c) => c.eventId),
      contains('renoir:2026-11-28-date-day'),
    );
  });

  test('Burroni is canonical for drifted c2-rota including Electric Six', () {
    final plan = planPersonEventBackfill([
      cand(
        hubId: burroni,
        eventId: 'c2-rota:2026-12-06',
        summary: 'C2 — Electric Six',
        source: 'c2-rota',
        externalId: '2026-12-06',
        status: 'confirmed',
        updateTime: DateTime.utc(2026, 11, 25),
      ),
      cand(
        hubId: paddyHub,
        eventId: 'c2-rota:2026-12-06',
        summary: 'C2 — Electric Six',
        source: 'c2-rota',
        externalId: '2026-12-06',
        status: 'tentative',
        updateTime: DateTime.utc(2026, 11, 26),
      ),
    ]);
    expect(plan.writes, hasLength(1));
    final write = plan.writes.single;
    expect(write.ownerUid, tom);
    expect(write.eventId, 'c2-rota:2026-12-06');
    expect(write.fromHubId, burroni);
    expect(write.fields['status'], 'confirmed');
    expect(write.reason, 'canonical-burroni-c2-rota');
    expect(write.losers, hasLength(1));
    expect(write.losers.single.hubId, paddyHub);
  });

  test('Maria-assigned events with ownerId Tom land under Tom', () {
    final plan = planPersonEventBackfill([
      cand(
        hubId: burroni,
        eventId: 'maria-appt',
        summary: "Maria's appointment",
        category: 'general',
        assignedTo: maria,
        ownerId: tom,
      ),
    ]);
    expect(plan.writes.single.ownerUid, tom);
    expect(plan.writes.single.fields['assignedTo'], maria);
    expect(plan.writes.single.fields['ownerId'], tom);
  });

  test("Paddy's own events land under Paddy", () {
    final plan = planPersonEventBackfill([
      cand(
        hubId: paddyHub,
        eventId: 'the-lab:2026-11-22',
        summary: 'Shift at The Lab',
        assignedTo: paddy,
        ownerId: paddy,
        source: 'the-lab',
        externalId: '2026-11-22',
      ),
    ]);
    expect(plan.writes.single.ownerUid, paddy);
    expect(plan.countsByOwner, {paddy: 1});
  });
}
