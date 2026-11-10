'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { fetchPublicPage, RecipeFetchError } = require('./ssrf');
const {
  assertHubMember,
  createRateLimiter,
  MembershipError,
} = require('./membership');

const assertRate = createRateLimiter();

// firebase-functions initializes a named app ("__FIREBASE_FUNCTIONS_SDK__"),
// not the default. getFirestore() without an app always wants the default, so
// pick any already-initialized app (or create the default when none exists).
function firestore() {
  const apps = getApps();
  const app = apps.length > 0 ? apps[0] : initializeApp();
  return getFirestore(app);
}

function asHttpsError(error) {
  if (error instanceof HttpsError) return error;
  if (error instanceof RecipeFetchError || error instanceof MembershipError) {
    return new HttpsError(error.code, error.message);
  }
  return new HttpsError('internal', "Couldn't fetch that recipe.");
}

function logUnexpected(error) {
  const name = error && error.name ? String(error.name) : typeof error;
  const code = error && error.code != null ? String(error.code) : '';
  const message = error && error.message ? String(error.message) : '';
  // No request URLs, tokens, hub ids, or user data — reason only.
  console.error(
    'importRecipePage failed',
    JSON.stringify({ name, code, message: message.slice(0, 200) }),
  );
}

// App Check is not enforced on LoveHub. Leave enforceAppCheck off.
exports.importRecipePage = onCall(
  {
    region: 'europe-west2',
    timeoutSeconds: 30,
    memory: '256MiB',
    maxInstances: 5,
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    try {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'Sign in to import a recipe.');
      }
      assertRate(request.auth.uid);
      await assertHubMember(request.auth.uid, request.data?.hubId, firestore());
      const page = await fetchPublicPage(request.data?.url);
      return { finalUrl: page.finalUrl, html: page.html };
    } catch (error) {
      if (!(error instanceof HttpsError) &&
          !(error instanceof RecipeFetchError) &&
          !(error instanceof MembershipError)) {
        logUnexpected(error);
      }
      throw asHttpsError(error);
    }
  },
);
