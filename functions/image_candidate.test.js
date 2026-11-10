'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const { extractImageCandidate } = require('./image_candidate');

const PAGE = 'https://www.nigella.com/recipes/guests/persian-style-saffron-chicken-rice';

test('Nigella microdata image resolves against the page URL', () => {
  const html = fs.readFileSync(
    path.join(__dirname, '..', 'test', 'fixtures', 'nigella_persian_saffron_chicken.html'),
    'utf8',
  );
  assert.equal(
    extractImageCandidate(html, PAGE),
    'https://www.nigella.com/assets/uploads/recipes/public-thumbnail/persianstylechickenrice-697b830922f48.jpg',
  );
});

test('JSON-LD image as a string, array, or ImageObject', () => {
  const page = (image) =>
    `<script type="application/ld+json">${JSON.stringify({
      '@context': 'https://schema.org',
      '@graph': [{ '@type': 'WebPage' }, { '@type': 'Recipe', name: 'x', image }],
    })}</script><meta property="og:image" content="https://cdn.example.com/og.jpg">`;
  assert.equal(extractImageCandidate(page('/img/a.jpg'), 'https://example.com/r/1'), 'https://example.com/img/a.jpg');
  assert.equal(
    extractImageCandidate(page(['https://cdn.example.com/1.jpg', 'https://cdn.example.com/2.jpg']), PAGE),
    'https://cdn.example.com/1.jpg',
  );
  assert.equal(
    extractImageCandidate(
      page([
        { '@type': 'ImageObject', url: 'https://cdn.example.com/small.jpg', width: 300 },
        { '@type': 'ImageObject', url: 'https://cdn.example.com/big.jpg', width: 1200 },
      ]),
      PAGE,
    ),
    'https://cdn.example.com/big.jpg',
  );
  assert.equal(
    extractImageCandidate(page({ '@type': 'ImageObject', contentUrl: 'https://cdn.example.com/c.jpg' }), PAGE),
    'https://cdn.example.com/c.jpg',
  );
});

test('falls back to og:image then twitter:image, decoding entities', () => {
  assert.equal(
    extractImageCandidate(
      '<meta name="twitter:image" content="https://t.example.com/t.jpg"><meta property="og:image" content="https://o.example.com/o.jpg?a=1&amp;b=2">',
      PAGE,
    ),
    'https://o.example.com/o.jpg?a=1&b=2',
  );
  assert.equal(
    extractImageCandidate('<meta name="twitter:image" content="//t.example.com/t.jpg">', PAGE),
    'https://t.example.com/t.jpg',
  );
});

test('ignores data: and non-http images, and pages with none', () => {
  assert.equal(extractImageCandidate('<meta property="og:image" content="data:image/png;base64,AAAA">', PAGE), null);
  assert.equal(extractImageCandidate('<meta property="og:image" content="javascript:alert(1)">', PAGE), null);
  assert.equal(extractImageCandidate('<p>No picture</p>', PAGE), null);
  assert.equal(extractImageCandidate('', PAGE), null);
});
