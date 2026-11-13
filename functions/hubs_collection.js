'use strict';

// Single switch for Cloud Functions that read hub membership.
// Live cutover (13 Nov 2026): production reads `sharedHubs`. The old `hubs`
// collection stays in Firestore as a read-only backup. Set
// HUBS_COLLECTION=hubs only to roll functions back to the old collection.
const HUBS_COLLECTION = process.env.HUBS_COLLECTION || 'sharedHubs';

// Membership also accepts the other collection so a phone still running an
// older cached build (writing hub ids that only exist in `hubs`) keeps
// authorizing importRecipePage / fetchRecipeImage / smartSortShopping
// until it reloads.
const OTHER_HUBS_COLLECTION =
  HUBS_COLLECTION === 'sharedHubs' ? 'hubs' : 'sharedHubs';

module.exports = { HUBS_COLLECTION, OTHER_HUBS_COLLECTION };
