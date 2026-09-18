import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/circle_model.dart';

class CircleRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream all circles the current user is a member of
  Stream<List<Circle>> streamUserCircles(String uid) {
    return _db
        .collection('circles')
        .where('members', arrayContains: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Circle.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // Create a new Hub (Circle)
  Future<void> createCircle(
    String name,
    CircleType type,
    String creatorUid,
  ) async {
    await _db.collection('circles').add({
      'name': name,
      'type': type.toString().split('.').last,
      'members': [creatorUid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
