'use strict';

// Host and address rules match lib/recipe_import/recipe_url.dart.
// This file is the one that opens the connection.

const dns = require('dns');
const http = require('http');
const https = require('https');
const net = require('net');
const zlib = require('zlib');

const MAX_BYTES = 1_500_000;
const MAX_REDIRECTS = 4;
const REQUEST_TIMEOUT_MS = 8000;
const OVERALL_MS = 20000;

const BLOCKED_MESSAGE = "That link can't be fetched.";
const PASTE_MESSAGE = 'Paste a full http or https recipe link.';

const BLOCKED_HOSTS = new Set([
  'localhost',
  'localhost.localdomain',
  'metadata',
  'metadata.google.internal',
  'metadata.google.com',
]);

const BLOCKED_SUFFIXES = [
  '.local',
  '.localhost',
  '.internal',
  '.localdomain',
  '.home.arpa',
  '.intranet',
  '.lan',
  '.corp',
  '.localnet',
  '.cluster.local',
  '.svc',
];

const BLOCKED_V4 = [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
];

class RecipeFetchError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RecipeFetchError';
    this.code = code;
  }
}

function blocked() {
  return new RecipeFetchError('invalid-argument', BLOCKED_MESSAGE);
}

function paste() {
  return new RecipeFetchError('invalid-argument', PASTE_MESSAGE);
}

function ipv4ToInt(ip) {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  let value = 0;
  for (const part of parts) {
    if (!/^\d+$/.test(part)) return null;
    const octet = Number(part);
    if (octet > 255) return null;
    value = (value * 256 + octet) >>> 0;
  }
  return value;
}

function inCidrV4(ip, base, bits) {
  const address = ipv4ToInt(ip);
  const network = ipv4ToInt(base);
  if (address == null || network == null) return false;
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return (address & mask) === (network & mask);
}

function isPrivateV4(ip) {
  return BLOCKED_V4.some(([base, bits]) => inCidrV4(ip, base, bits));
}

function expandIpv6(ip) {
  if (ip.includes('%')) return null;
  let text = ip.toLowerCase();
  const dotted = text.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
  if (dotted) {
    const value = ipv4ToInt(dotted[2]);
    if (value == null) return null;
    const high = ((value >>> 16) & 0xffff).toString(16);
    const low = (value & 0xffff).toString(16);
    text = `${dotted[1]}${high}:${low}`;
  }
  let parts;
  if (text.includes('::')) {
    if (text.indexOf('::') !== text.lastIndexOf('::')) return null;
    const [headRaw, tailRaw] = text.split('::');
    const head = headRaw ? headRaw.split(':') : [];
    const tail = tailRaw ? tailRaw.split(':') : [];
    const missing = 8 - head.length - tail.length;
    if (missing < 0) return null;
    parts = [...head, ...Array(missing).fill('0'), ...tail];
  } else {
    parts = text.split(':');
  }
  if (parts.length !== 8) return null;
  const expanded = [];
  for (const part of parts) {
    if (!/^[0-9a-f]{1,4}$/.test(part)) return null;
    expanded.push(part.padStart(4, '0'));
  }
  return expanded.join(':');
}

function tailV4(expanded) {
  const parts = expanded.split(':');
  const high = parseInt(parts[6], 16);
  const low = parseInt(parts[7], 16);
  const value = (high << 16) + low;
  return `${(value >>> 24) & 255}.${(value >>> 16) & 255}.${(value >>> 8) & 255}.${value & 255}`;
}

function sixToFour(expanded) {
  const parts = expanded.split(':');
  const high = parseInt(parts[1], 16);
  const low = parseInt(parts[2], 16);
  return `${(high >> 8) & 255}.${high & 255}.${(low >> 8) & 255}.${low & 255}`;
}

function isPrivateV6(ip) {
  const expanded = expandIpv6(ip);
  if (!expanded) return true;
  if (expanded === '0000:0000:0000:0000:0000:0000:0000:0000') return true;
  if (expanded === '0000:0000:0000:0000:0000:0000:0000:0001') return true;
  const first = parseInt(expanded.slice(0, 4), 16);
  if ((first & 0xfe00) === 0xfc00) return true;
  if ((first & 0xffc0) === 0xfe80) return true;
  if ((first & 0xff00) === 0xff00) return true;
  if (expanded.startsWith('2001:0db8:')) return true;
  if (expanded.startsWith('0064:ff9b:0000:0000:0000:0000:')) return true;
  if (expanded.startsWith('0000:0000:0000:0000:0000:ffff:')) {
    return isPrivateV4(tailV4(expanded));
  }
  if (expanded.startsWith('2002:')) return isPrivateV4(sixToFour(expanded));
  return false;
}

function isPrivateAddress(ip) {
  const version = net.isIP(ip);
  if (version === 4) return isPrivateV4(ip);
  if (version === 6) return isPrivateV6(ip);
  if (ip.includes(':')) return isPrivateV6(ip);
  return true;
}

function isBlockedHostname(host) {
  if (BLOCKED_HOSTS.has(host)) return true;
  if (BLOCKED_SUFFIXES.some((suffix) => host.endsWith(suffix))) return true;
  const looksLikeIp = net.isIP(host) || host.includes(':');
  if (!looksLikeIp && !host.includes('.')) return true;
  return false;
}

function isObfuscatedHost(host) {
  if (/^\d+$/.test(host)) return true;
  if (host.startsWith('0x')) return true;
  const parts = host.split('.');
  if (
    parts.length >= 2 &&
    parts.length <= 4 &&
    parts.every((part) => /^\d+$/.test(part))
  ) {
    if (parts.length !== 4) return true;
    if (parts.some((part) => part.length > 1 && part.startsWith('0'))) return true;
  }
  return false;
}

function assertPublicHttpUrl(input) {
  if (typeof input !== 'string') throw paste();
  const raw = input.trim();
  if (!raw || raw.length > 2000) throw paste();
  if (/[\u0000-\u0020\\]/.test(raw)) throw paste();
  let url;
  try {
    url = new URL(raw);
  } catch (_) {
    throw paste();
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') throw paste();
  if (url.username || url.password) throw blocked();
  if (url.port && url.port !== '80' && url.port !== '443') throw blocked();
  const host = url.hostname.toLowerCase().replace(/\.$/, '');
  if (!host || isBlockedHostname(host) || isObfuscatedHost(host)) throw blocked();
  if (net.isIP(host) && isPrivateAddress(host)) throw blocked();
  if (!net.isIP(host) && host.includes(':') && isPrivateAddress(host)) throw blocked();
  url.hash = '';
  return url;
}

function pinnedLookup(address, family) {
  const fam = family === 6 ? 6 : 4;
  return (hostname, options, callback) => {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    if (options && options.all) callback(null, [{ address, family: fam }]);
    else callback(null, address, fam);
  };
}

async function defaultResolve(hostname) {
  const records = await dns.promises.lookup(hostname, { all: true, verbatim: true });
  return records.map((record) => ({
    address: record.address,
    family: record.family,
  }));
}

function header(headers, name) {
  if (!headers) return '';
  const value = headers[name] ?? headers[name.toLowerCase()];
  if (Array.isArray(value)) return value[0] || '';
  return value == null ? '' : String(value);
}

function assertContentType(contentType, body) {
  if (!contentType) {
    const start = body.slice(0, 64).toString('utf8').trim().toLowerCase();
    if (start.startsWith('<') || start.startsWith('{') || start.startsWith('[')) return;
    throw new RecipeFetchError(
      'failed-precondition',
      "That page isn't a recipe page we can read.",
    );
  }
  const type = contentType.toLowerCase();
  const allowed = [
    'text/html',
    'application/xhtml+xml',
    'text/plain',
    'application/json',
    'application/ld+json',
    'application/xml',
    'text/xml',
  ];
  if (!allowed.some((item) => type.includes(item))) {
    throw new RecipeFetchError(
      'failed-precondition',
      "That page isn't a recipe page we can read.",
    );
  }
}

function inflateBody(body, contentEncoding) {
  const encoding = (contentEncoding || '').toLowerCase().trim();
  if (!encoding || encoding === 'identity') return body;
  try {
    if (encoding === 'gzip' || encoding === 'x-gzip') {
      return zlib.gunzipSync(body);
    }
    if (encoding === 'deflate') {
      return zlib.inflateSync(body);
    }
    if (encoding === 'br') {
      return zlib.brotliDecompressSync(body);
    }
  } catch (_) {
    throw new RecipeFetchError(
      'failed-precondition',
      "That page isn't a recipe page we can read.",
    );
  }
  throw new RecipeFetchError(
    'failed-precondition',
    "That page isn't a recipe page we can read.",
  );
}

function decodeBody(body) {
  let bytes = body;
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xef &&
    bytes[1] === 0xbb &&
    bytes[2] === 0xbf
  ) {
    bytes = bytes.subarray(3);
  }
  return bytes.toString('utf8');
}

function defaultRequest({ url, address, family }) {
  return new Promise((resolve, reject) => {
    const lib = url.protocol === 'https:' ? https : http;
    const req = lib.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: `${url.pathname}${url.search}`,
        method: 'GET',
        headers: {
          Host: url.host,
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          Accept:
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
          'Accept-Language': 'en-GB,en;q=0.9',
        },
        lookup: pinnedLookup(address, family),
        servername: url.hostname,
        timeout: REQUEST_TIMEOUT_MS,
      },
      (res) => {
        const chunks = [];
        let received = 0;
        const length = Number(res.headers['content-length'] || 0);
        if (length > MAX_BYTES) {
          res.resume();
          req.destroy();
          reject(
            new RecipeFetchError(
              'resource-exhausted',
              'That page is too large to import.',
            ),
          );
          return;
        }
        res.on('data', (chunk) => {
          received += chunk.length;
          if (received > MAX_BYTES) {
            res.resume();
            req.destroy();
            reject(
              new RecipeFetchError(
                'resource-exhausted',
                'That page is too large to import.',
              ),
            );
            return;
          }
          chunks.push(chunk);
        });
        res.on('end', () => {
          resolve({
            status: res.statusCode || 0,
            headers: res.headers,
            body: Buffer.concat(chunks),
          });
        });
        res.on('error', reject);
      },
    );
    req.on('timeout', () => {
      req.destroy();
      reject(
        new RecipeFetchError(
          'deadline-exceeded',
          'The recipe site took too long to answer.',
        ),
      );
    });
    req.on('error', (error) => {
      if (error instanceof RecipeFetchError) {
        reject(error);
        return;
      }
      reject(error);
    });
    req.end();
  });
}

async function resolveHost(hostname, resolve) {
  if (net.isIP(hostname)) {
    if (isPrivateAddress(hostname)) throw blocked();
    return [{ address: hostname, family: net.isIP(hostname) }];
  }
  let records;
  try {
    records = await resolve(hostname);
  } catch (error) {
    if (error instanceof RecipeFetchError) throw error;
    throw new RecipeFetchError('not-found', "Couldn't find that website.");
  }
  if (!records || records.length === 0) {
    throw new RecipeFetchError('not-found', "Couldn't find that website.");
  }
  for (const record of records) {
    if (!record.address || isPrivateAddress(record.address)) throw blocked();
  }
  return records;
}

function isRedirect(status) {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

async function fetchPublicPage(rawUrl, deps = {}) {
  const resolve = deps.resolve || defaultResolve;
  const request = deps.request || defaultRequest;
  const now = deps.now || Date.now;
  const started = now();
  let current = assertPublicHttpUrl(rawUrl).toString();

  for (let hop = 0; hop <= MAX_REDIRECTS; hop += 1) {
    if (now() - started > OVERALL_MS) {
      throw new RecipeFetchError(
        'deadline-exceeded',
        'The recipe site took too long to answer.',
      );
    }
    const url = assertPublicHttpUrl(current);
    const records = await resolveHost(url.hostname, resolve);
    let response;
    try {
      response = await request({
        url,
        address: records[0].address,
        family: records[0].family,
      });
    } catch (error) {
      if (error instanceof RecipeFetchError) throw error;
      const code = error && error.code;
      if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
        throw new RecipeFetchError('not-found', "Couldn't find that website.");
      }
      throw new RecipeFetchError('unavailable', "The recipe site couldn't be reached.");
    }
    const status = response.status;
    if (isRedirect(status)) {
      if (hop === MAX_REDIRECTS) {
        throw new RecipeFetchError(
          'failed-precondition',
          'That page redirected too many times.',
        );
      }
      const location = header(response.headers, 'location');
      if (!location) {
        throw new RecipeFetchError(
          'failed-precondition',
          'That page redirected without a destination.',
        );
      }
      current = new URL(location, url).toString();
      continue;
    }
    if (status < 200 || status >= 300) {
      throw new RecipeFetchError(
        'failed-precondition',
        `The recipe site returned HTTP ${status}.`,
      );
    }
    const body = response.body || Buffer.alloc(0);
    if (body.length > MAX_BYTES) {
      throw new RecipeFetchError('resource-exhausted', 'That page is too large to import.');
    }
    const inflated = inflateBody(body, header(response.headers, 'content-encoding'));
    assertContentType(header(response.headers, 'content-type'), inflated);
    return { finalUrl: url.toString(), html: decodeBody(inflated) };
  }
  throw new RecipeFetchError(
    'failed-precondition',
    'That page redirected too many times.',
  );
}

module.exports = {
  BLOCKED_MESSAGE,
  MAX_BYTES,
  RecipeFetchError,
  assertPublicHttpUrl,
  fetchPublicPage,
  inflateBody,
  isPrivateAddress,
  pinnedLookup,
};
