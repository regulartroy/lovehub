'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  MAX_ITEMS,
  buildPrompt,
  generateSortIndexes,
  parseModelText,
  parseSortItems,
} = require('./smart_sort');
const { MembershipError } = require('./membership');

const items = [
  { id: 'a', text: 'Bananas' },
  { id: 'b', text: 'Dog food' },
  { id: 'c', text: 'Milk' },
];

test('parseSortItems accepts a valid list and rejects oversize or bad rows', () => {
  assert.deepEqual(parseSortItems({ items }), items);

  assert.throws(
    () => parseSortItems({ items: [] }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  assert.throws(
    () => parseSortItems({ items: [{ id: 'a' }] }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  assert.throws(
    () => parseSortItems({ items: [{ id: '../x', text: 'Milk' }] }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  assert.throws(
    () => parseSortItems({
      items: [
        { id: 'a', text: 'Milk' },
        { id: 'a', text: 'Eggs' },
      ],
    }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  assert.throws(
    () => parseSortItems({
      items: Array.from({ length: MAX_ITEMS + 1 }, (_, i) => ({
        id: `id${i}`,
        text: 'Milk',
      })),
    }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
  assert.throws(
    () => parseSortItems({ items: [{ id: 'a', text: 'x'.repeat(201) }] }),
    (error) => error instanceof MembershipError && error.code === 'invalid-argument',
  );
});

test('parseModelText reads an array, or sortIndexes map, and ignores junk', () => {
  const allowed = new Set(['a', 'b', 'c']);
  assert.deepEqual(
    parseModelText(
      '```json\n[{"id":"a","sortIndex":10},{"id":"b","sortIndex":140},{"id":"zzz","sortIndex":1}]\n```',
      allowed,
    ),
    { a: 10, b: 140 },
  );
  assert.deepEqual(
    parseModelText(
      JSON.stringify({ sortIndexes: { a: 11.8, b: 140, c: 0, d: 40 } }),
      allowed,
    ),
    { a: 11, b: 140 },
  );
  assert.throws(
    () => parseModelText('not json', allowed),
    (error) => error.name === 'SmartSortError',
  );
  assert.throws(
    () => parseModelText('[{"id":"zzz","sortIndex":10}]', allowed),
    (error) => error.name === 'SmartSortError',
  );
});

test('generateSortIndexes uses the model text and the injected generate hook', async () => {
  const prompt = buildPrompt(items);
  assert.match(prompt, /Fruit & veg/);
  assert.match(prompt, /Pet/);
  assert.match(prompt, /Bananas/);

  const out = await generateSortIndexes(items, {
    generate: async () =>
      JSON.stringify([
        { id: 'a', sortIndex: 12 },
        { id: 'c', sortIndex: 40 },
        { id: 'b', sortIndex: 140 },
      ]),
  });
  assert.deepEqual(out, { a: 12, c: 40, b: 140 });

  await assert.rejects(
    () => generateSortIndexes(items, { generate: async () => '[]' }),
    (error) => error.name === 'SmartSortError',
  );
});

test('generateSortIndexes reads a Vertex-shaped response', async () => {
  const out = await generateSortIndexes(items, {
    generate: async () => ({
      candidates: [
        {
          content: {
            parts: [{ text: '[{"id":"a","sortIndex":10},{"id":"b","sortIndex":140},{"id":"c","sortIndex":40}]' }],
          },
        },
      ],
    }),
  });
  assert.deepEqual(out, { a: 10, b: 140, c: 40 });
});
