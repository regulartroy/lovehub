/// Firestore collection that holds hub documents and their subcollections.
///
/// Live since the 13 Nov 2026 cutover: the app, Roger's import/confirm CLI,
/// the Concorde rota reconciler, and the schedule export all read and write
/// `sharedHubs`. The old `hubs` collection is kept as a read-only backup.
///
/// Cloud Functions use the matching switch in `functions/hubs_collection.js`.
const String kHubsCollection = 'sharedHubs';
