import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/event_model.dart';
import '../models/friend_model.dart';
import '../services/event_store.dart';
import '../services/hub_collection.dart';

/// Live merge of person-owned events and hub-shared events for one hub view.
///
/// Person-event queries always include a `category in [...]` filter derived
/// from the friends sharing toggles. An empty category set means that query
/// is not started at all (never an unfiltered collection listen).
Stream<List<EventModel>> streamPersonHubEvents({
  required FirebaseFirestore db,
  required String hubId,
  required String viewerUid,
}) {
  late StreamController<List<EventModel>> controller;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? hubSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? friendsSub;
  final querySubs =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final buckets = <String, List<EventModel>>{};
  var members = <String>[];
  var friendships = <Friendship>[];

  var neededKeys = <String>{};

  void emit() {
    if (controller.isClosed) return;
    if (!neededKeys.every(buckets.containsKey)) return;
    final liveShared = <EventModel>[
      ...?buckets['sharedAssigned'],
      ...?buckets['sharedMeals'],
    ];
    final preview = buckets['preview'] ?? const <EventModel>[];
    final person = <EventModel>[];
    for (final entry in buckets.entries) {
      if (entry.key.startsWith('person:')) {
        person.addAll(entry.value);
      }
    }
    controller.add(
      mergeVisibleEvents(
        liveShared: liveShared,
        previewShared: preview,
        personEvents: person,
      ),
    );
  }

  List<EventModel> eventsFrom(QuerySnapshot<Map<String, dynamic>> snap) {
    return snap.docs.map(EventModel.fromFirestore).toList();
  }

  void listenQuery(String key, Query<Map<String, dynamic>> query) {
    querySubs[key] = query.snapshots().listen((snap) {
      buckets[key] = eventsFrom(snap);
      emit();
    }, onError: controller.addError);
  }

  void syncQueries() {
    final indexed = friendshipsIndexedByOtherUid(
      viewerUid: viewerUid,
      friendships: friendships,
    );
    final needed = <String, Query<Map<String, dynamic>>>{};

    final mine = whereInCategories(
      categoriesSharedWithAnyMember(
        viewerUid: viewerUid,
        memberUids: members,
        friendshipsByOtherUid: indexed,
      ),
    );
    if (mine.isNotEmpty) {
      needed['person:$viewerUid:${mine.join(',')}'] = db
          .collection('users')
          .doc(viewerUid)
          .collection('events')
          .where('category', whereIn: mine);
    }

    for (final other in members) {
      if (other == viewerUid) continue;
      final theirs = whereInCategories(
        categoriesTheyShareWithMe(
          viewerUid: viewerUid,
          otherUid: other,
          friendship: indexed[other],
        ),
      );
      if (theirs.isEmpty) continue;
      needed['person:$other:${theirs.join(',')}'] = db
          .collection('users')
          .doc(other)
          .collection('events')
          .where('category', whereIn: theirs);
    }

    needed['sharedAssigned'] = db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('events')
        .where('assignedTo', isEqualTo: kSharedAssignee);
    needed['sharedMeals'] = db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection('events')
        .where('category', isEqualTo: kMealEventCategory);
    needed['preview'] = db
        .collection(kHubsCollection)
        .doc(hubId)
        .collection(kPreviewSharedEventsCollection);

    neededKeys = needed.keys.toSet();
    for (final key in querySubs.keys.toList()) {
      if (needed.containsKey(key)) continue;
      querySubs.remove(key)?.cancel();
      buckets.remove(key);
    }
    for (final entry in needed.entries) {
      if (querySubs.containsKey(entry.key)) continue;
      listenQuery(entry.key, entry.value);
    }
    emit();
  }

  void cancelAll() {
    hubSub?.cancel();
    friendsSub?.cancel();
    hubSub = null;
    friendsSub = null;
    for (final sub in querySubs.values) {
      sub.cancel();
    }
    querySubs.clear();
    buckets.clear();
  }

  controller = StreamController<List<EventModel>>.broadcast(
    onListen: () {
      hubSub = db.collection(kHubsCollection).doc(hubId).snapshots().listen((
        doc,
      ) {
        final data = doc.data() ?? {};
        members = ((data['members'] as List?) ?? [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
        syncQueries();
      }, onError: controller.addError);

      friendsSub = db
          .collection('friends')
          .where('members', arrayContains: viewerUid)
          .snapshots()
          .listen((snap) {
            friendships = snap.docs
                .map((doc) => Friendship.fromMap(doc.data(), id: doc.id))
                .toList();
            syncQueries();
          }, onError: controller.addError);
    },
    onCancel: cancelAll,
  );

  return controller.stream;
}
