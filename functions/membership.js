'use strict';

const { HUBS_COLLECTION, OTHER_HUBS_COLLECTION } = require('./hubs_collection');

function validHubId(hubId) {
  if (typeof hubId !== 'string') return false;
  if (hubId.length < 1 || hubId.length > 128) return false;
  if (hubId === '.' || hubId === '..') return false;
  if (/[\s/\\]/.test(hubId)) return false;
  return true;
}

class MembershipError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'MembershipError';
    this.code = code;
  }
}

async function assertHubMember(uid, hubId, db, action = 'import a recipe') {
  if (!uid || typeof uid !== 'string') {
    throw new MembershipError('unauthenticated', `Sign in to ${action}.`);
  }
  if (!validHubId(hubId)) {
    throw new MembershipError('invalid-argument', 'Missing hub.');
  }
  const userSnap = await db.collection('users').doc(uid).get();
  const joined = userSnap.get('joinedHubs');
  if (joined && typeof joined === 'object' && Object.prototype.hasOwnProperty.call(joined, hubId)) {
    return;
  }
  if (await membersInclude(db, HUBS_COLLECTION, hubId, uid)) return;
  if (
    OTHER_HUBS_COLLECTION &&
    OTHER_HUBS_COLLECTION !== HUBS_COLLECTION &&
    (await membersInclude(db, OTHER_HUBS_COLLECTION, hubId, uid))
  ) {
    return;
  }
  throw new MembershipError(
    'permission-denied',
    `You need to be a member of this hub to ${action}.`,
  );
}

async function membersInclude(db, collection, hubId, uid) {
  const hubSnap = await db.collection(collection).doc(hubId).get();
  const members = hubSnap.get('members');
  return Array.isArray(members) && members.includes(uid);
}

function createRateLimiter({
  max = 20,
  windowMs = 60_000,
  now = Date.now,
  message = 'Too many imports. Wait a minute and try again.',
} = {}) {
  const hits = new Map();
  return function assertRate(uid) {
    const time = now();
    const recent = (hits.get(uid) || []).filter((stamp) => time - stamp < windowMs);
    if (recent.length >= max) {
      throw new MembershipError(
        'resource-exhausted',
        message,
      );
    }
    recent.push(time);
    hits.set(uid, recent);
  };
}

module.exports = {
  MembershipError,
  assertHubMember,
  createRateLimiter,
  validHubId,
  HUBS_COLLECTION,
  OTHER_HUBS_COLLECTION,
};
