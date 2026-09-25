import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'web_build.dart';

/// Live `appMeta/web` build id for the signed-in member.
///
/// Emits null when nobody is signed in (rules require auth) or the field
/// is missing. Errors from a dropped listener surface to the host, which
/// ignores them and retries on focus, resume, and the periodic timer.
Stream<String?> watchWebBuildStamp() {
  return FirebaseAuth.instance.authStateChanges().asyncExpand((user) {
    if (user == null) {
      return Stream<String?>.value(null);
    }
    return FirebaseFirestore.instance
        .doc(kWebBuildStampPath)
        .snapshots()
        .map((snap) => buildIdFromFields(snap.data()));
  });
}

/// One-shot read used on resume, window focus, and the slow timer.
Future<String?> fetchWebBuildStamp() async {
  if (FirebaseAuth.instance.currentUser == null) return null;
  final snap = await FirebaseFirestore.instance.doc(kWebBuildStampPath).get();
  return buildIdFromFields(snap.data());
}
