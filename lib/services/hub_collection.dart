/// Firestore collection that holds hub documents and their subcollections.
///
/// The friends-preview cutover points this at `sharedHubs` so the live
/// `hubs` collection is not read or written by the preview app, or by
/// import/sync tools run from this branch. Flip to `'hubs'` only to target
/// the live collection.
///
/// Cloud Functions use a separate switch in `functions/hubs_collection.js`,
/// which stays on `hubs` until the live cutover is approved and deployed.
const String kHubsCollection = 'sharedHubs';
