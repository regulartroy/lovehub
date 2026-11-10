'use strict';

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

async function assertHubMember(uid, hubId, db) {
  if (!uid || typeof uid !== 'string') {
    throw new MembershipError('unauthenticated', 'Sign in to import a recipe.');
  }
  if (!validHubId(hubId)) {
    throw new MembershipError('invalid-argument', 'Missing hub.');
  }
  const userSnap = await db.collection('users').doc(uid).get();
  const joined = userSnap.get('joinedHubs');
  if (joined && typeof joined === 'object' && Object.prototype.hasOwnProperty.call(joined, hubId)) {
    return;
  }
  const hubSnap = await db.collection('hubs').doc(hubId).get();
  const members = hubSnap.get('members');
  if (Array.isArray(members) && members.includes(uid)) return;
  throw new MembershipError(
    'permission-denied',
    'You need to be a member of this hub to import a recipe.',
  );
}

function createRateLimiter({ max = 20, windowMs = 60_000, now = Date.now } = {}) {
  const hits = new Map();
  return function assertRate(uid) {
    const time = now();
    const recent = (hits.get(uid) || []).filter((stamp) => time - stamp < windowMs);
    if (recent.length >= max) {
      throw new MembershipError(
        'resource-exhausted',
        'Too many imports. Wait a minute and try again.',
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
};
