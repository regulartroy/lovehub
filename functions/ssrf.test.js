'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  BLOCKED_MESSAGE,
  RecipeFetchError,
  assertPublicHttpUrl,
  fetchPublicPage,
  inflateBody,
  isPrivateAddress,
  pinnedLookup,
} = require('./ssrf');

function htmlResponse(body, status = 200, headers = {}) {
  return {
    status,
    headers: { 'content-type': 'text/html; charset=UTF-8', ...headers },
    body: Buffer.from(body),
  };
}

function publicResolve() {
  return async () => [{ address: '93.184.216.34', family: 4 }];
}

test('private and public addresses', () => {
  const blocked = [
    '0.0.0.0',
    '10.1.2.3',
    '100.64.0.1',
    '100.127.255.255',
    '127.0.0.1',
    '127.0.0.2',
    '169.254.169.254',
    '172.16.0.1',
    '172.31.255.255',
    '192.0.0.1',
    '192.0.2.1',
    '192.168.1.1',
    '198.18.0.1',
    '198.51.100.1',
    '203.0.113.1',
    '224.0.0.1',
    '240.0.0.1',
    '255.255.255.255',
    '::1',
    'fc00::1',
    'fd12:3456::1',
    'fe80::1',
    '2001:db8::1',
    '::ffff:127.0.0.1',
    '::ffff:10.1.2.3',
    '2002:7f00:1::',
    '64:ff9b::127.0.0.1',
  ];
  for (const ip of blocked) {
    assert.equal(isPrivateAddress(ip), true, ip);
  }
  const allowed = [
    '1.1.1.1',
    '8.8.8.8',
    '172.15.0.1',
    '172.32.0.1',
    '100.128.0.1',
    '2606:4700:4700::1111',
    '2001:4860:4860::8888',
    '::ffff:8.8.8.8',
  ];
  for (const ip of allowed) {
    assert.equal(isPrivateAddress(ip), false, ip);
  }
});

test('pinned lookup does not use the requested hostname', () => {
  const lookup = pinnedLookup('1.2.3.4', 4);
  lookup('evil.example', (error, address, family) => {
    assert.equal(error, null);
    assert.equal(address, '1.2.3.4');
    assert.equal(family, 4);
  });
  lookup('evil.example', { all: true }, (error, addresses) => {
    assert.equal(error, null);
    assert.deepEqual(addresses, [{ address: '1.2.3.4', family: 4 }]);
  });
});

test('rejects schemes, ports, credentials, and internal hosts before DNS', async () => {
  const cases = [
    'file:///etc/passwd',
    'javascript:alert(1)',
    'ftp://example.com/recipe',
    'https://user:pass@example.com/recipe',
    'https://example.com:22/recipe',
    'http://127.0.0.1/latest',
    'http://169.254.169.254/computeMetadata/v1/',
    'http://10.1.2.3/',
    'http://192.168.0.1/',
    'http://172.16.0.1/',
    'http://[::1]/',
    'http://[fc00::1]/',
    'http://localhost/recipe',
    'http://metadata.google.internal/',
    'http://2130706433/',
    'http://0177.0.0.1/',
    'http://printer/recipe',
  ];
  let lookedUp = false;
  for (const input of cases) {
    await assert.rejects(
      () =>
        fetchPublicPage(input, {
          resolve: async () => {
            lookedUp = true;
            return [{ address: '93.184.216.34', family: 4 }];
          },
          request: async () => htmlResponse('<html></html>'),
        }),
      (error) => error instanceof RecipeFetchError,
      input,
    );
  }
  assert.equal(lookedUp, false);
  assert.throws(() => assertPublicHttpUrl('http://127.0.0.1/'), RecipeFetchError);
  assert.equal(assertPublicHttpUrl('https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice').hostname, 'www.nigella.com');
});

test('blocks a public name that resolves to a private address', async () => {
  const requested = [];
  await assert.rejects(
    () =>
      fetchPublicPage('https://evil.example/recipe', {
        resolve: async () => [{ address: '10.0.0.5', family: 4 }],
        request: async (options) => {
          requested.push(options.address);
          return htmlResponse('<html></html>');
        },
      }),
    (error) => error instanceof RecipeFetchError && error.message === BLOCKED_MESSAGE,
  );
  assert.deepEqual(requested, []);
});

test('blocks a redirect onto a private address', async () => {
  const seen = [];
  await assert.rejects(
    () =>
      fetchPublicPage('https://recipes.example/start', {
        resolve: async (hostname) => {
          if (hostname === '127.0.0.1') return [{ address: '127.0.0.1', family: 4 }];
          return [{ address: '93.184.216.34', family: 4 }];
        },
        request: async ({ url }) => {
          seen.push(url.hostname);
          return {
            status: 302,
            headers: { location: 'http://127.0.0.1/latest' },
            body: Buffer.alloc(0),
          };
        },
      }),
    (error) => error instanceof RecipeFetchError && error.message === BLOCKED_MESSAGE,
  );
  assert.deepEqual(seen, ['recipes.example']);
});

test('follows a safe redirect and returns the final html', async () => {
  const page = await fetchPublicPage('https://recipes.example/old', {
    resolve: publicResolve(),
    request: async ({ url, address }) => {
      assert.equal(address, '93.184.216.34');
      if (url.pathname === '/old') {
        return {
          status: 301,
          headers: { location: '/guests/persian-style-saffron-chicken-rice' },
          body: Buffer.alloc(0),
        };
      }
      return htmlResponse('<html><title>Rice</title></html>');
    },
  });
  assert.equal(
    page.finalUrl,
    'https://recipes.example/guests/persian-style-saffron-chicken-rice',
  );
  assert.match(page.html, /Rice/);
});

test('stops after too many redirects and rejects a huge page', async () => {
  await assert.rejects(
    () =>
      fetchPublicPage('https://recipes.example/loop', {
        resolve: publicResolve(),
        request: async ({ url }) => ({
          status: 302,
          headers: { location: `${url.origin}/loop?n=1` },
          body: Buffer.alloc(0),
        }),
      }),
    (error) =>
      error instanceof RecipeFetchError &&
      error.message === 'That page redirected too many times.',
  );

  await assert.rejects(
    () =>
      fetchPublicPage('https://recipes.example/big', {
        resolve: publicResolve(),
        request: async () => ({
          status: 200,
          headers: { 'content-type': 'text/html' },
          body: Buffer.alloc(1_500_001, 65),
        }),
      }),
    (error) =>
      error instanceof RecipeFetchError &&
      error.code === 'resource-exhausted',
  );

  await assert.rejects(
    () =>
      fetchPublicPage('https://recipes.example/photo.jpg', {
        resolve: publicResolve(),
        request: async () => ({
          status: 200,
          headers: { 'content-type': 'image/jpeg' },
          body: Buffer.from('not a page'),
        }),
      }),
    (error) =>
      error instanceof RecipeFetchError &&
      error.message === "That page isn't a recipe page we can read.",
  );
});

test('gives up when the overall budget is spent', async () => {
  let clock = 0;
  await assert.rejects(
    () =>
      fetchPublicPage('https://recipes.example/slow', {
        now: () => clock,
        resolve: publicResolve(),
        request: async () => {
          clock = 21000;
          return {
            status: 302,
            headers: { location: 'https://recipes.example/next' },
            body: Buffer.alloc(0),
          };
        },
      }),
    (error) => error instanceof RecipeFetchError && error.code === 'deadline-exceeded',
  );
});

test('inflateBody decodes gzip and rejects unknown encodings', () => {
  const zlib = require('zlib');
  const plain = Buffer.from('<html>ok</html>');
  const gzipped = zlib.gzipSync(plain);
  assert.equal(inflateBody(gzipped, 'gzip').toString('utf8'), '<html>ok</html>');
  assert.equal(inflateBody(plain, 'identity').toString('utf8'), '<html>ok</html>');
  assert.equal(inflateBody(plain, '').toString('utf8'), '<html>ok</html>');
  assert.throws(
    () => inflateBody(plain, 'xz'),
    (error) => error instanceof RecipeFetchError,
  );
});

test('fetchPublicPage gunzips a compressed HTML body', async () => {
  const zlib = require('zlib');
  const html = '<html><title>Gzipped</title></html>';
  const page = await fetchPublicPage('https://recipes.example/gz', {
    resolve: publicResolve(),
    request: async () => ({
      status: 200,
      headers: {
        'content-type': 'text/html; charset=UTF-8',
        'content-encoding': 'gzip',
      },
      body: zlib.gzipSync(Buffer.from(html)),
    }),
  });
  assert.match(page.html, /Gzipped/);
});

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

test('fetchPublicImage returns image bytes and checks the real type', async () => {
  const { fetchPublicImage } = require('./ssrf');
  let accept;
  const image = await fetchPublicImage('https://recipes.example/pic.jpg', {
    resolve: publicResolve(),
    request: async (args) => {
      accept = args.accept;
      assert.equal(args.maxBytes, 5_000_000);
      return { status: 200, headers: { 'content-type': 'image/jpeg' }, body: JPEG };
    },
  });
  assert.equal(image.contentType, 'image/jpeg');
  assert.deepEqual(image.bytes, JPEG);
  assert.match(accept, /^image\//);
});

test('fetchPublicImage refuses html, svg, lying headers, and oversize pictures', async () => {
  const { fetchPublicImage, MAX_IMAGE_BYTES } = require('./ssrf');
  const reply = (headers, body) => ({ resolve: publicResolve(), request: async () => ({ status: 200, headers, body }) });
  await assert.rejects(
    fetchPublicImage('https://recipes.example/p', reply({ 'content-type': 'text/html' }, Buffer.from('<html>'))),
    /isn't a picture/,
  );
  await assert.rejects(
    fetchPublicImage('https://recipes.example/p.svg', reply({ 'content-type': 'image/svg+xml' }, Buffer.from('<svg/>'))),
    /isn't a picture/,
  );
  await assert.rejects(
    fetchPublicImage('https://recipes.example/p', reply({ 'content-type': 'text/plain' }, JPEG)),
    /isn't a picture/,
  );
  await assert.rejects(
    fetchPublicImage(
      'https://recipes.example/p',
      reply({ 'content-type': 'image/jpeg' }, Buffer.alloc(MAX_IMAGE_BYTES + 1, 0xff)),
    ),
    (error) => error.code === 'resource-exhausted',
  );
});

test('fetchPublicImage keeps the SSRF guards', async () => {
  const { fetchPublicImage } = require('./ssrf');
  let requested = false;
  await assert.rejects(
    fetchPublicImage('http://169.254.169.254/latest/meta-data', {
      resolve: publicResolve(),
      request: async () => {
        requested = true;
        return { status: 200, headers: {}, body: JPEG };
      },
    }),
    /can't be fetched/,
  );
  await assert.rejects(
    fetchPublicImage('https://pics.example/p.jpg', {
      resolve: async () => [{ address: '10.0.0.5', family: 4 }],
      request: async () => {
        requested = true;
        return { status: 200, headers: {}, body: JPEG };
      },
    }),
    /can't be fetched/,
  );
  assert.equal(requested, false);
});
