import '../services/event_store_core.dart';

const defaultBurroniHubId = 'pobIb3qupVJudoQGMJjl';

const _copiedFields = {
  'summary',
  'start',
  'end',
  'allDay',
  'category',
  'assignedTo',
  'isLovehubContext',
  'gcalId',
  'ownerId',
  'source',
  'externalId',
  'notes',
  'status',
  'recipeId',
  'ingredients',
};

class PersonBackfillCandidate {
  const PersonBackfillCandidate({
    required this.hubId,
    required this.eventId,
    required this.fields,
    this.updateTime,
  });

  final String hubId;
  final String eventId;
  final Map<String, Object?> fields;
  final DateTime? updateTime;

  String get category => (fields['category'] as String?)?.trim() ?? 'general';
  String get assignedTo =>
      (fields['assignedTo'] as String?)?.trim() ?? kSharedAssignee;
  String? get source {
    final value = (fields['source'] as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String? get externalId {
    final value = (fields['externalId'] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    final id = eventId;
    if (source != null && id.startsWith('$source:')) {
      return id.substring(source!.length + 1);
    }
    return null;
  }

  String? get ownerId {
    final value = (fields['ownerId'] as String?)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  bool get isJoint =>
      isHubJointEvent(category: category, assignedTo: assignedTo);

  bool get isC2Rota => source == 'c2-rota' || eventId.startsWith('c2-rota:');
}

class PersonBackfillSelection {
  const PersonBackfillSelection({
    required this.ownerUid,
    required this.eventId,
    required this.fromHubId,
    required this.fields,
    required this.reason,
    required this.losers,
  });

  final String ownerUid;
  final String eventId;
  final String fromHubId;
  final Map<String, Object?> fields;
  final String reason;
  final List<PersonBackfillCandidate> losers;
}

class PersonBackfillPlan {
  const PersonBackfillPlan({
    required this.writes,
    required this.skippedJoint,
    required this.skippedNoOwner,
  });

  final List<PersonBackfillSelection> writes;
  final List<PersonBackfillCandidate> skippedJoint;
  final List<PersonBackfillCandidate> skippedNoOwner;

  Map<String, int> get countsByOwner {
    final counts = <String, int>{};
    for (final write in writes) {
      counts[write.ownerUid] = (counts[write.ownerUid] ?? 0) + 1;
    }
    return counts;
  }
}

/// Resolve who owns a non-joint event in the person store.
/// Prefer the stored [ownerId] (the creator). Fall back to [assignedTo]
/// only when it is a uid, so a legacy row is not dropped.
String? backfillOwnerUid(PersonBackfillCandidate candidate) {
  if (candidate.ownerId != null) return candidate.ownerId;
  final assigned = candidate.assignedTo;
  if (assigned.isNotEmpty && assigned != kSharedAssignee) return assigned;
  return null;
}

String backfillDedupeKey(PersonBackfillCandidate candidate) {
  final source = candidate.source;
  final externalId = candidate.externalId;
  if (source != null && externalId != null && externalId.isNotEmpty) {
    return 'src:$source:$externalId';
  }
  final owner = backfillOwnerUid(candidate) ?? '';
  return 'id:$owner:${candidate.eventId}';
}

PersonBackfillPlan planPersonEventBackfill(
  List<PersonBackfillCandidate> candidates, {
  String burroniHubId = defaultBurroniHubId,
}) {
  final skippedJoint = <PersonBackfillCandidate>[];
  final skippedNoOwner = <PersonBackfillCandidate>[];
  final groups = <String, List<PersonBackfillCandidate>>{};
  for (final candidate in candidates) {
    if (candidate.isJoint) {
      skippedJoint.add(candidate);
      continue;
    }
    if (backfillOwnerUid(candidate) == null) {
      skippedNoOwner.add(candidate);
      continue;
    }
    groups.putIfAbsent(backfillDedupeKey(candidate), () => []).add(candidate);
  }

  final writes = <PersonBackfillSelection>[];
  for (final group in groups.values) {
    writes.add(_pick(group, burroniHubId: burroniHubId));
  }
  writes.sort((a, b) {
    final byOwner = a.ownerUid.compareTo(b.ownerUid);
    if (byOwner != 0) return byOwner;
    return a.eventId.compareTo(b.eventId);
  });
  return PersonBackfillPlan(
    writes: writes,
    skippedJoint: skippedJoint,
    skippedNoOwner: skippedNoOwner,
  );
}

PersonBackfillSelection _pick(
  List<PersonBackfillCandidate> group, {
  required String burroniHubId,
}) {
  PersonBackfillCandidate winner;
  var reason = 'only-copy';
  if (group.length == 1) {
    winner = group.single;
  } else if (group.any((c) => c.isC2Rota)) {
    winner = group.firstWhere(
      (c) => c.hubId == burroniHubId,
      orElse: () => _latest(group),
    );
    reason = winner.hubId == burroniHubId
        ? 'canonical-burroni-c2-rota'
        : 'c2-rota-latest-no-burroni-copy';
  } else if (group.any((c) => c.hubId == burroniHubId)) {
    winner = group.firstWhere((c) => c.hubId == burroniHubId);
    reason = 'canonical-burroni-same-id';
  } else {
    winner = _latest(group);
    reason = 'latest-update';
  }
  final owner = backfillOwnerUid(winner)!;
  final fields = <String, Object?>{
    for (final key in _copiedFields)
      if (winner.fields.containsKey(key)) key: winner.fields[key],
    'ownerId': owner,
  };
  return PersonBackfillSelection(
    ownerUid: owner,
    eventId: winner.eventId,
    fromHubId: winner.hubId,
    fields: fields,
    reason: reason,
    losers: [
      for (final c in group)
        if (c != winner) c,
    ],
  );
}

PersonBackfillCandidate _latest(List<PersonBackfillCandidate> group) {
  final sorted = [...group]
    ..sort((a, b) {
      final aTime = a.updateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  return sorted.first;
}

Map<String, Object?> personBackfillWriteFields(PersonBackfillSelection write) {
  return write.fields;
}
