'use strict';

// Single switch for Cloud Functions that read hub membership.
// Deployed production functions stay on `hubs` until the live cutover.
// Set HUBS_COLLECTION=sharedHubs (or change the default) when deploying
// functions as part of go-live. Do not silently switch production tonight.
const HUBS_COLLECTION = process.env.HUBS_COLLECTION || 'hubs';

// During the dual-running period, membership also accepts the other
// collection so a preview-only hub or a not-yet-cutover live hub still
// authorizes importRecipePage / fetchRecipeImage / smartSortShopping.
const OTHER_HUBS_COLLECTION =
  HUBS_COLLECTION === 'sharedHubs' ? 'hubs' : 'sharedHubs';

module.exports = { HUBS_COLLECTION, OTHER_HUBS_COLLECTION };
