'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  initializeApp,
  getApps,
  deleteApp,
  getApp,
} = require('firebase-admin/app');

async function resetApps() {
  await Promise.all(getApps().map((app) => deleteApp(app)));
}

function pickAdminApp() {
  const apps = getApps();
  return apps.length > 0 ? apps[0] : initializeApp();
}

test('pickAdminApp uses the Functions SDK named app when the default is missing', async () => {
  await resetApps();
  initializeApp(
    {
      projectId: 'lovehub-26107',
      credential: {
        getAccessToken: async () => ({ access_token: 'test', expires_in: 3600 }),
      },
    },
    '__FIREBASE_FUNCTIONS_SDK__',
  );

  const app = pickAdminApp();
  assert.equal(app.name, '__FIREBASE_FUNCTIONS_SDK__');
  assert.throws(() => getApp(), (error) => error.code === 'app/no-app');

  await resetApps();
});

test('pickAdminApp creates the default app when none exist', async () => {
  await resetApps();
  const app = pickAdminApp();
  assert.equal(app.name, '[DEFAULT]');
  await resetApps();
});
