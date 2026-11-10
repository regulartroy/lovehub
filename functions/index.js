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

function firestore() {
  if (getApps().length === 0) initializeApp();
  return getFirestore();
}

function asHttpsError(error) {
  if (error instanceof HttpsError) return error;
  if (error instanceof RecipeFetchError || error instanceof MembershipError) {
    return new HttpsError(error.code, error.message);
  }
  return new HttpsError('internal', "Couldn't fetch that recipe.");
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
        console.error('importRecipePage failed');
      }
      throw asHttpsError(error);
    }
  },
);
