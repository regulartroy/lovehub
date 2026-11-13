'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  MembershipError,
  assertHubMember,
  createRateLimiter,
} = require('./membership');

function fakeDb(docs) {
  return {
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              const data = docs[`${name}/${id}`];
              return {
                exists: data != null,
                get(field) {
                  return data ? data[field] : undefined;
                },
              };
            },
          };
        },
      };
    },
  };
}

test('allows a member via joinedHubs or the hub members list', async () => {
  const db = fakeDb({
    'users/tom': { joinedHubs: { home: { name: 'Home', role: 'admin' } } },
    'users/sophie': {},
    'hubs/home': { members: ['sophie'] },
    'hubs/other': { members: ['someone-else'] },
  });
  await assertHubMember('tom', 'home', db);
  await assertHubMember('sophie', 'home', db);
  await assert.rejects(
    () => assertHubMember('tom', 'other', db),
    (error) => error instanceof MembershipError && error.code === 'permission-denied',
  );
});

test('rejects a missing sign-in, a bad hub id, and a stranger', async () => {
  const db = fakeDb({});
  await assert.rejects(
    () => assertHubMember('', 'home', db),
    (error) => error instanceof MembershipError && error.code === 'unauthenticated',
  );
  await assert.rejects(
    () => assertHubMember('tom', '../secrets', db),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  await assert.rejects(
    () => assertHubMember('tom', 'missing', db),
    (error) => error instanceof MembershipError && error.code === 'permission-denied',
  );
});

test('rate limiter allows a short burst and then stops', () => {
  let clock = 1_000;
  const assertRate = createRateLimiter({ max: 2, windowMs: 1000, now: () => clock });
  assertRate('tom');
  assertRate('tom');
  assert.throws(
    () => assertRate('tom'),
    (error) => error instanceof MembershipError && error.code === 'resource-exhausted',
  );
  clock += 1001;
  assertRate('tom');
});

test('allows a member listed only on sharedHubs during dual-running', async () => {
  const db = fakeDb({
    'users/dan': {},
    'sharedHubs/preview': { members: ['dan'] },
  });
  await assertHubMember('dan', 'preview', db);
});

const { HUBS_COLLECTION } = require('./hubs_collection');

test('functions stay on live hubs until the cutover env switch', () => {
  assert.equal(HUBS_COLLECTION, 'hubs');
});
