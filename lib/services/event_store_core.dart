import '../models/friend_model.dart';

/// Compile-time event store. Live Hosting builds omit the define, so this
/// stays `hub` and the app keeps reading and writing `sharedHubs/{hub}/events`.
/// The `person-sync` preview is built with `--dart-define=EVENT_STORE=person`.
const String kEventStoreDefine = String.fromEnvironment(
  'EVENT_STORE',
  defaultValue: 'hub',
);

const String kEventStorePersonValue = 'person';
const String kPreviewSharedEventsCollection = 'previewSharedEvents';
const String kPreviewDeletedField = 'previewDeleted';

const String kWorkEventCategory = 'work';
const String kGeneralEventCategory = 'general';
const String kPersonalEventCategory = 'personal';
const String kMealEventCategory = 'meal';
const String kBirthdayEventCategory = 'birthday';
const String kSharedAssignee = 'shared';

/// Categories covered by the Personal friends-sharing toggle.
const List<String> kPersonalShareCategories = [
  kGeneralEventCategory,
  kPersonalEventCategory,
  kMealEventCategory,
];

enum EventStoreMode { hub, person }

enum EventWriteTarget { hubEvents, personEvents, previewSharedEvents }

EventStoreMode eventStoreModeFromName(String raw) {
  return raw.trim() == kEventStorePersonValue
      ? EventStoreMode.person
      : EventStoreMode.hub;
}

EventStoreMode get compileTimeEventStoreMode =>
    eventStoreModeFromName(kEventStoreDefine);

bool get usePersonEventStore =>
    compileTimeEventStoreMode == EventStoreMode.person;

/// Maps a stored event category to the friends-sharing toggle that gates it.
String? shareFieldForCategory(String category) {
  switch (category.trim()) {
    case kWorkEventCategory:
      return 'shareWork';
    case kGeneralEventCategory:
    case kPersonalEventCategory:
    case kMealEventCategory:
      return 'sharePersonal';
    case kBirthdayEventCategory:
      return 'shareBirthdays';
    default:
      // Unknown categories follow Personal, same as the calendar's green fill.
      return 'sharePersonal';
  }
}

/// Categories a person makes visible when the given sharing map is on.
Set<String> categoriesSharedBy(FriendSharing sharing) {
  return {
    if (sharing.shareWork) kWorkEventCategory,
    if (sharing.sharePersonal) ...kPersonalShareCategories,
    if (sharing.shareBirthdays) kBirthdayEventCategory,
  };
}

/// Categories [viewerUid] has chosen to share with at least one other hub member.
Set<String> categoriesSharedWithAnyMember({
  required String viewerUid,
  required Iterable<String> memberUids,
  required Map<String, Friendship> friendshipsByOtherUid,
}) {
  final categories = <String>{};
  for (final other in memberUids) {
    if (other == viewerUid) continue;
    final friendship = friendshipsByOtherUid[other];
    if (friendship == null) continue;
    categories.addAll(categoriesSharedBy(friendship.mySharing(viewerUid)));
  }
  return categories;
}

/// Categories [otherUid] has chosen to share with [viewerUid].
Set<String> categoriesTheyShareWithMe({
  required String viewerUid,
  required String otherUid,
  Friendship? friendship,
}) {
  if (friendship == null) return {};
  return categoriesSharedBy(friendship.mySharing(otherUid));
}

Map<String, Friendship> friendshipsIndexedByOtherUid({
  required String viewerUid,
  required Iterable<Friendship> friendships,
}) {
  final map = <String, Friendship>{};
  for (final friendship in friendships) {
    final other = friendship.otherUid(viewerUid);
    if (other == null) continue;
    map[other] = friendship;
  }
  return map;
}

/// Joint events stay on the hub (or the preview shadow), not under a person.
bool isHubJointEvent({required String category, required String assignedTo}) {
  return assignedTo.trim() == kSharedAssignee ||
      category.trim() == kMealEventCategory;
}

EventWriteTarget eventWriteTarget({
  required EventStoreMode mode,
  required String category,
  required String assignedTo,
}) {
  if (mode != EventStoreMode.person) return EventWriteTarget.hubEvents;
  if (isHubJointEvent(category: category, assignedTo: assignedTo)) {
    return EventWriteTarget.previewSharedEvents;
  }
  return EventWriteTarget.personEvents;
}

/// Person-store writes go under the existing owner, or the viewer for a new doc.
String personEventOwnerUid({
  required String? ownerId,
  required String viewerUid,
}) {
  final owner = ownerId?.trim() ?? '';
  return owner.isEmpty ? viewerUid : owner;
}

String eventDedupeKeyFor({
  required String id,
  required String category,
  required String assignedTo,
  String? ownerId,
  String? source,
  String? externalId,
}) {
  final src = source?.trim() ?? '';
  final ext = externalId?.trim() ?? '';
  if (src.isNotEmpty && ext.isNotEmpty) {
    return 'src:$src:$ext';
  }
  if (isHubJointEvent(category: category, assignedTo: assignedTo)) {
    return 'joint:$id';
  }
  final owner = ownerId?.trim() ?? '';
  return 'id:$owner:$id';
}

/// Merge live hub-shared events, preview-only joint edits, and person-owned
/// events. Preview records flagged [isDeleted] hide the live event with the
/// same key. Person events win over hub copies of the same key.
List<T> mergeVisibleEventRecords<T>({
  required List<T> liveShared,
  required List<T> previewShared,
  required List<T> personEvents,
  required bool Function(T event) isJoint,
  required bool Function(T event) isDeleted,
  required String Function(T event) keyOf,
}) {
  final byKey = <String, T>{};
  for (final event in liveShared) {
    if (!isJoint(event)) continue;
    byKey[keyOf(event)] = event;
  }
  for (final event in previewShared) {
    final key = keyOf(event);
    if (isDeleted(event)) {
      byKey.remove(key);
    } else {
      byKey[key] = event;
    }
  }
  for (final event in personEvents) {
    byKey[keyOf(event)] = event;
  }
  return byKey.values.toList();
}

/// Sorted list for a Firestore `whereIn` of at most 10 values. Empty means
/// "run no query" — never issue an unfiltered collection listen.
List<String> whereInCategories(Set<String> categories) {
  final list = categories.toSet().toList()..sort();
  return list;
}

String personEventsCollectionPath(String uid) => 'users/$uid/events';

String previewSharedEventsCollectionPath(String hubId) =>
    'sharedHubs/$hubId/$kPreviewSharedEventsCollection';
