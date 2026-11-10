'use strict';

// Picks one picture to suggest for an imported recipe page.
// Order: JSON-LD Recipe `image`, microdata itemprop="image", then
// og:image / twitter:image. Relative URLs resolve against the page URL.
// Only http(s) URLs come back. This only names a URL; fetchRecipeImage
// downloads it later with the SSRF guards.

const MAX_HTML = 1_500_000;

function decodeEntities(text) {
  return String(text)
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)));
}

function resolveUrl(raw, pageUrl) {
  if (typeof raw !== 'string') return null;
  const text = decodeEntities(raw).trim();
  if (!text || text.startsWith('data:')) return null;
  try {
    const url = new URL(text, pageUrl);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    url.hash = '';
    return url.toString();
  } catch (_) {
    return null;
  }
}

function isType(type, want) {
  const types = Array.isArray(type) ? type : [type];
  return types.some(
    (item) =>
      typeof item === 'string' &&
      item.split('/').pop().split('#').pop().toLowerCase() === want.toLowerCase(),
  );
}

function collectRecipes(node, out, depth) {
  if (node == null || depth > 8) return;
  if (Array.isArray(node)) {
    for (const item of node) collectRecipes(item, out, depth + 1);
    return;
  }
  if (typeof node !== 'object') return;
  if (isType(node['@type'], 'Recipe')) out.push(node);
  collectRecipes(node['@graph'], out, depth + 1);
  collectRecipes(node.mainEntity, out, depth + 1);
}

// `image` may be a string, an ImageObject, or an array of either.
// Prefer the widest ImageObject when widths are given, else the first.
function imageFromJsonLd(image) {
  if (image == null) return null;
  if (typeof image === 'string') return image;
  if (Array.isArray(image)) {
    let best = null;
    let bestWidth = -1;
    for (const item of image) {
      const url = imageFromJsonLd(item);
      if (!url) continue;
      const width = item && typeof item === 'object' ? Number(item.width) || 0 : 0;
      if (best == null || width > bestWidth) {
        best = url;
        bestWidth = width;
      }
    }
    return best;
  }
  if (typeof image === 'object') {
    if (typeof image.url === 'string') return image.url;
    if (typeof image.contentUrl === 'string') return image.contentUrl;
    if (typeof image['@id'] === 'string' && /^https?:|^\//.test(image['@id'])) {
      return image['@id'];
    }
  }
  return null;
}

function jsonLdCandidate(html) {
  const pattern =
    /<script\b[^>]*type\s*=\s*["']?application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi;
  for (const match of html.matchAll(pattern)) {
    let text = match[1].trim();
    text = text.replace(/^<!--/, '').replace(/-->$/, '').trim();
    let decoded;
    try {
      decoded = JSON.parse(text);
    } catch (_) {
      continue;
    }
    const recipes = [];
    collectRecipes(decoded, recipes, 0);
    for (const recipe of recipes) {
      const url = imageFromJsonLd(recipe.image);
      if (url) return url;
    }
  }
  return null;
}

function attr(tag, name) {
  const match = tag.match(
    new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i'),
  );
  if (!match) return null;
  return match[1] ?? match[2] ?? match[3] ?? null;
}

function microdataCandidate(html) {
  const tags = html.match(/<(img|meta|link|source)\b[^>]*\bitemprop\s*=\s*["']?[^"'>]*\bimage\b[^>]*>/gi);
  if (!tags) return null;
  for (const tag of tags) {
    const prop = (attr(tag, 'itemprop') || '').toLowerCase().split(/\s+/);
    if (!prop.includes('image')) continue;
    const name = tag.slice(1).split(/[\s>/]/)[0].toLowerCase();
    const value =
      name === 'meta'
        ? attr(tag, 'content')
        : name === 'link'
          ? attr(tag, 'href')
          : attr(tag, 'src') || attr(tag, 'data-src') || attr(tag, 'srcset')?.split(/\s+/)[0];
    if (value) return value;
  }
  return null;
}

function metaCandidate(html) {
  const metas = html.match(/<meta\b[^>]*>/gi) || [];
  const wanted = ['og:image:secure_url', 'og:image', 'og:image:url', 'twitter:image', 'twitter:image:src'];
  const found = new Map();
  for (const tag of metas) {
    const key = (attr(tag, 'property') || attr(tag, 'name') || '').toLowerCase().trim();
    if (!wanted.includes(key) || found.has(key)) continue;
    const content = attr(tag, 'content');
    if (content) found.set(key, content);
  }
  for (const key of wanted) {
    if (found.has(key)) return found.get(key);
  }
  return null;
}

function extractImageCandidate(html, pageUrl) {
  if (typeof html !== 'string' || !html) return null;
  const text = html.length > MAX_HTML ? html.slice(0, MAX_HTML) : html;
  for (const pick of [jsonLdCandidate, microdataCandidate, metaCandidate]) {
    const url = resolveUrl(pick(text), pageUrl);
    if (url) return url;
  }
  return null;
}

module.exports = { extractImageCandidate, imageFromJsonLd, resolveUrl };
