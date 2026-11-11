'use strict';

const { GoogleAuth } = require('google-auth-library');
const { MembershipError } = require('./membership');

// Must stay in lockstep with lib/services/shopping_aisle_sort.dart.
const AISLES = [
  [10, 'Fruit & veg'],
  [20, 'Bakery'],
  [30, 'Meat & fish'],
  [40, 'Dairy & eggs'],
  [50, 'Chilled'],
  [60, 'Frozen'],
  [70, 'Tins & dry goods'],
  [80, 'Breakfast & cereal'],
  [90, 'Snacks & sweets'],
  [100, 'Drinks'],
  [110, 'Alcohol'],
  [120, 'Household & cleaning'],
  [130, 'Toiletries & health'],
  [140, 'Pet'],
  [150, 'Baby'],
  [160, 'Other'],
];

const MAX_ITEMS = 80;
const MAX_ID_LEN = 128;
const MAX_TEXT_LEN = 200;
const MIN_SORT_INDEX = 1;
const MAX_SORT_INDEX = 999;
const ID_RE = /^[A-Za-z0-9_-]+$/;

// Function stays in europe-west2 (London). Gemini on Vertex is called in
// europe-west1, where the model is available, still in the EU.
const VERTEX_LOCATION = 'europe-west1';
const VERTEX_MODEL = 'gemini-2.5-flash';

class SmartSortError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'SmartSortError';
    this.code = code;
  }
}

function projectId() {
  return (
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    'lovehub-26107'
  );
}

function parseSortItems(data) {
  const raw = data && data.items;
  if (!Array.isArray(raw)) {
    throw new MembershipError('invalid-argument', 'Missing shopping items.');
  }
  if (raw.length === 0) {
    throw new MembershipError('invalid-argument', 'Missing shopping items.');
  }
  if (raw.length > MAX_ITEMS) {
    throw new MembershipError(
      'invalid-argument',
      `At most ${MAX_ITEMS} items can be sorted at once.`,
    );
  }
  const seen = new Set();
  const items = [];
  for (const row of raw) {
    if (!row || typeof row !== 'object') {
      throw new MembershipError('invalid-argument', 'Each item needs an id and text.');
    }
    const id = typeof row.id === 'string' ? row.id.trim() : '';
    const text = typeof row.text === 'string' ? row.text.trim() : '';
    if (!id || !ID_RE.test(id) || id.length > MAX_ID_LEN) {
      throw new MembershipError('invalid-argument', 'Each item needs a valid id.');
    }
    if (!text || text.length > MAX_TEXT_LEN) {
      throw new MembershipError(
        'invalid-argument',
        'Each item needs text of at most 200 characters.',
      );
    }
    if (seen.has(id)) {
      throw new MembershipError('invalid-argument', 'Duplicate item ids.');
    }
    seen.add(id);
    items.push({ id, text });
  }
  return items;
}

function buildPrompt(items) {
  const aisleLines = AISLES.map(([index, label]) => `${index}: ${label}`).join('\n');
  const payload = items.map((item) => ({ id: item.id, text: item.text }));
  return `You are a supermarket layout expert for a typical large UK supermarket.
Assign each shopping item a sortIndex for a shopper walking the aisles in this order:
${aisleLines}

Use those aisle numbers. You may add a 0-9 offset within an aisle (for example 11 after 10) so similar items sit together in a sensible walking order. Stay between 1 and 999.

Return ONLY a JSON array of objects. Each object MUST have the "id" (exactly as provided) and the "sortIndex" (integer).
Do NOT omit any IDs. Do not wrap the array in an object. Do not use markdown.
Items: ${JSON.stringify(payload)}`;
}

function extractText(result) {
  if (typeof result === 'string') return result;
  const parts = result?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts
    .map((part) => (part && typeof part.text === 'string' ? part.text : ''))
    .join('');
}

function parseModelText(raw, allowedIds) {
  let text = typeof raw === 'string' ? raw : extractText(raw);
  text = text.replace(/```json/gi, '').replace(/```/g, '').trim();
  if (!text) {
    throw new SmartSortError('unavailable', "Couldn't sort the shopping list.");
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    throw new SmartSortError('unavailable', "Couldn't sort the shopping list.");
  }
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed) && parsed.sortIndexes) {
    parsed = Object.entries(parsed.sortIndexes).map(([id, sortIndex]) => ({ id, sortIndex }));
  }
  if (!Array.isArray(parsed)) {
    throw new SmartSortError('unavailable', "Couldn't sort the shopping list.");
  }
  const out = {};
  for (const row of parsed) {
    if (!row || typeof row !== 'object') continue;
    const id = typeof row.id === 'string' ? row.id : '';
    const sortIndex = row.sortIndex;
    if (!allowedIds.has(id)) continue;
    if (typeof sortIndex !== 'number' || !Number.isFinite(sortIndex)) continue;
    const index = Math.trunc(sortIndex);
    if (index < MIN_SORT_INDEX || index > MAX_SORT_INDEX) continue;
    out[id] = index;
  }
  if (Object.keys(out).length === 0) {
    throw new SmartSortError('unavailable', "Couldn't sort the shopping list.");
  }
  return out;
}

async function defaultGenerate(prompt) {
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const project = projectId();
  const url = `https://${VERTEX_LOCATION}-aiplatform.googleapis.com/v1/projects/${project}/locations/${VERTEX_LOCATION}/publishers/google/models/${VERTEX_MODEL}:generateContent`;
  const response = await client.request({
    url,
    method: 'POST',
    data: {
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 0,
      },
    },
  });
  return extractText(response.data);
}

async function generateSortIndexes(items, { generate } = {}) {
  const raw = await (generate || defaultGenerate)(buildPrompt(items));
  return parseModelText(raw, new Set(items.map((item) => item.id)));
}

module.exports = {
  AISLES,
  MAX_ITEMS,
  MAX_TEXT_LEN,
  SmartSortError,
  VERTEX_LOCATION,
  VERTEX_MODEL,
  buildPrompt,
  generateSortIndexes,
  parseModelText,
  parseSortItems,
};
