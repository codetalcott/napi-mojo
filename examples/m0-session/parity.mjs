// examples/m0-session/parity.mjs — m0's session and grant code, compiled into
// this addon, checked against an issuer written here on node:crypto.
//
//   node --test examples/m0-session/parity.mjs
//
// The oracle below is the OTHER side of both formats, written from their
// definitions (the docstrings of m0serve's grant.py and m0_http's
// session.mojo), so the Mojo code is never checked only against itself: the
// role grant.py and scripts/notes_session.py play in mojo-http. The pinned
// vectors are mojo-http's own constants, which ties all three together.
//
// Named without `.test.` so Jest's default match never collects it into
// `npm test`, where no m0 build exists.

import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { createRequire } from 'node:module';
import { test } from 'node:test';

const m0 = createRequire(import.meta.url)('./build/index.node');

// --- The oracle ---------------------------------------------------------------

const b64url = (bytes) => Buffer.from(bytes).toString('base64url');
const sha256 = (data) => createHash('sha256').update(data).digest();
const hmac = (key, message) => createHmac('sha256', key).update(message).digest();
const keyId = (key) => sha256(key).toString('hex').slice(0, 8);
const binding = (cookie) => b64url(sha256(cookie).subarray(0, 16));

// v1.<kid>.<exp>.<channel>.<sb>.<sig>, with sb `-` for a grant bound to no session.
function issueGrant(key, exp, channel, cookie) {
  const sb = cookie === null ? '-' : binding(cookie);
  const signed = ['v1', keyId(key), exp, channel, sb].join('.');
  return `${signed}.${b64url(hmac(key, signed))}`;
}

// v1.<kid>.<exp>.<subject>.<tag>
function issueSession(key, subject, exp) {
  const signed = ['v1', keyId(key), exp, subject].join('.');
  return `${signed}.${b64url(hmac(key, signed))}`;
}

// A MAC over the session's own tag, under a domain-separating prefix.
const csrfFor = (key, cookie) => b64url(hmac(key, `m0csrf1.${cookie.split('.')[4]}`));

function fnv1a(text) {
  let h = 0x811c9dc5;
  for (const byte of Buffer.from(text, 'utf8')) h = Math.imul(h ^ byte, 0x01000193) >>> 0;
  return h;
}

// --- Pinned vectors -----------------------------------------------------------
// mojo-http's constants at m0 0.2.0. Grants: packages/m0-http/test/
// test_grant.mojo, the bound ones bound to the cookie value "abc". Sessions:
// packages/m0-http/test/test_session.mojo.

const G = {
  key: 'test-key-0123456789abcdef0123456789abcdef',
  prev: 'previous-key-fedcba9876543210fedcba98765432',
  now: 1800000000,
  cookie: 'abc',
  ok: 'v1.6a41f8cf.1800000600.news.ungWv48Bz-pBQUDeXa4iIw.hnaLpdsfR7frsJ1FsmGJ9oCivG0p5SgTr750iyCswpM',
  unbound: 'v1.6a41f8cf.1800000600.news.-.Pvw91j4fNsFENJQAsdDmT9cwFNRLi9FUINLgC7mzEH0',
  expired: 'v1.6a41f8cf.1799999999.news.ungWv48Bz-pBQUDeXa4iIw.j0pn4AhYG3_BAyS5xf2Odcq6iXpKULSv7S0eFzOX7tY',
  prevSigned: 'v1.45867b91.1800000600.notate_submission_7.ungWv48Bz-pBQUDeXa4iIw.Yy2N2KP-xpM6OqUH4risFVYIMPXOwasjhqFSgN3HCV4',
  tampered: 'v1.6a41f8cf.1800000600.news.ungWv48Bz-pBQUDeXa4iIw.hnaLpdsfR7frsJ1FsmGJ9oCivG0p5SgTr750iyCswpA',
};

const S = {
  key: 'notes-key-0123456789abcdef0123456789abcdef',
  prev: 'notes-prev-fedcba9876543210fedcba9876543210',
  now: 1800000000,
  kid: '4d2d3960',
  ok: 'v1.4d2d3960.1800000600.notes.1nhjo_vzwsmxxb_Oj3UMceZX4aaSVIyfpYlVqTr7LhI',
  csrf: 'MuYjaJBt1_pCz3Z6w84ZuldquOsbgb_-dQSSITRAVXo',
  expired: 'v1.4d2d3960.1799999999.notes.X1QjhBIosY5t_URHbIxG0eB9HMuhEsq7iIppXpHSez0',
  prevSigned: 'v1.543627e7.1800000600.notes.nUDjdN8_-uqwibCFzL8KMpCACrvuP8V-XJQ1mXpuhMw',
  otherSubject: 'v1.4d2d3960.1800000600.someone_else.1E8m-dHMnykYUwSfczqpmVvJoP-pJEvjzWHDNprp44s',
  tampered: 'v1.4d2d3960.1800000600.notes.1nhjo_vzwsmxxb_Oj3UMceZX4aaSVIyfpYlVqTr7LhA',
};

const granted = (channel) => ({ ok: true, channel, reason: '' });
const notGranted = (reason) => ({ ok: false, channel: '', reason });
const session = (subject, csrf) => ({ ok: true, subject, csrf, reason: '' });
const noSession = (reason) => ({ ok: false, subject: '', csrf: '', reason });

// Before the oracle judges the addon, it must reproduce what mojo-http's own
// Python issuers signed.
test('the oracle reproduces the pinned vectors', () => {
  assert.equal(keyId(G.key), '6a41f8cf');
  assert.equal(issueGrant(G.key, G.now + 600, 'news', G.cookie), G.ok);
  assert.equal(issueGrant(G.key, G.now + 600, 'news', null), G.unbound);
  assert.equal(issueGrant(G.key, G.now - 1, 'news', G.cookie), G.expired);
  assert.equal(issueGrant(G.prev, G.now + 600, 'notate_submission_7', G.cookie), G.prevSigned);
  assert.equal(keyId(S.key), S.kid);
  assert.equal(issueSession(S.key, 'notes', S.now + 600), S.ok);
  assert.equal(csrfFor(S.key, S.ok), S.csrf);
  assert.equal(issueSession(S.key, 'notes', S.now - 1), S.expired);
  assert.equal(issueSession(S.prev, 'notes', S.now + 600), S.prevSigned);
  assert.equal(issueSession(S.key, 'someone_else', S.now + 600), S.otherSubject);
});

test('the addon answers the pinned vectors as mojo-http does', () => {
  assert.equal(m0.grantKeyId(G.key), '6a41f8cf');
  assert.equal(m0.sessionBinding(G.cookie), 'ungWv48Bz-pBQUDeXa4iIw');
  assert.deepEqual(m0.verifyGrant(G.ok, [G.key], G.now, G.cookie), granted('news'));
  assert.deepEqual(m0.verifyGrant(G.unbound, [G.key], G.now, null), granted('news'));
  assert.deepEqual(m0.verifyGrant(G.expired, [G.key], G.now, G.cookie), notGranted('expired'));
  assert.deepEqual(
    m0.verifyGrant(G.prevSigned, [G.key, G.prev], G.now, G.cookie), granted('notate_submission_7'));
  assert.deepEqual(m0.verifyGrant(G.prevSigned, [G.key], G.now, G.cookie), notGranted('unknown key'));
  assert.deepEqual(m0.verifyGrant(G.tampered, [G.key], G.now, G.cookie), notGranted('bad signature'));

  assert.deepEqual(m0.verifySession(S.ok, [S.key], S.now), session('notes', S.csrf));
  assert.deepEqual(m0.verifySession(S.expired, [S.key], S.now), noSession('expired'));
  assert.deepEqual(
    m0.verifySession(S.prevSigned, [S.key, S.prev], S.now),
    session('notes', csrfFor(S.prev, S.prevSigned)));
  assert.deepEqual(m0.verifySession(S.prevSigned, [S.key], S.now), noSession('unknown key'));
  assert.deepEqual(m0.verifySession(S.tampered, [S.key], S.now), noSession('bad signature'));
  assert.equal(m0.issueSession([S.key], 'notes', S.now + 600), S.ok);
  // The first key in the ring signs; the rest only verify, during a rotation.
  assert.equal(m0.issueSession([S.key, S.prev], 'notes', S.now + 600), S.ok);
  assert.equal(m0.issueSession([S.prev, S.key], 'notes', S.now + 600), S.prevSigned);
});

// --- Seeded random parity -----------------------------------------------------

// mulberry32: small, seeded, so a failure names a case that reproduces.
function generator(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) >>> 0;
    let t = seed;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const SEED = 20260926;
const ALNUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const CHANNEL = [...ALNUM, '_', ':', '-'];
const SUBJECT = [...ALNUM, '_', '-', ':', '@'];
// Keys and cookies are text that m0 takes as UTF-8 bytes, as createHmac and
// createHash do, so non-ASCII here checks that a JS string crosses the
// boundary as exactly those bytes.
const TEXT = [...ALNUM, ' ', '.', 'é', 'ß', 'Ж', '中', '🔥'];

test('seeded random grants and sessions agree on both sides', () => {
  const rand = generator(SEED);
  const pick = (chars, min, max) => {
    const n = min + Math.floor(rand() * (max - min + 1));
    return Array.from({ length: n }, () => chars[Math.floor(rand() * chars.length)]).join('');
  };
  for (let i = 0; i < 300; i++) {
    const where = `case ${i} of seed ${SEED}`;
    const key = pick(TEXT, 1, 48);
    const now = 1_700_000_000 + Math.floor(rand() * 1e8);
    const exp = now + 1 + Math.floor(rand() * 1e6);

    assert.equal(m0.grantKeyId(key), keyId(key), where);
    const channel = pick(CHANNEL, 1, 64);
    const cookie = pick(TEXT, 0, 40);
    assert.equal(m0.sessionBinding(cookie), binding(cookie), where);
    const grant = issueGrant(key, exp, channel, cookie);
    assert.deepEqual(m0.verifyGrant(grant, [key], now, cookie), granted(channel), where);
    assert.deepEqual(m0.verifyGrant(grant, [key], now, `${cookie}x`), notGranted('session mismatch'), where);

    const subject = pick(SUBJECT, 1, 64);
    const cookieValue = issueSession(key, subject, exp);
    assert.equal(m0.issueSession([key], subject, exp), cookieValue, where);
    assert.deepEqual(
      m0.verifySession(cookieValue, [key], now), session(subject, csrfFor(key, cookieValue)), where);
  }
});

// --- Refusals -----------------------------------------------------------------

test('every refusal comes back as m0 names it', () => {
  const key = 'refusal-key';
  const now = 1_800_000_000;
  const tamper = (token) => token.slice(0, -1) + (token.endsWith('A') ? 'B' : 'A');
  const reason = (...args) => m0.verifyGrant(...args).reason;
  const grant = issueGrant(key, now + 60, 'room:1', 'cookie');

  assert.equal(reason(tamper(grant), [key], now, 'cookie'), 'bad signature');
  assert.equal(reason(grant, ['another key'], now, 'cookie'), 'unknown key');
  assert.equal(reason(grant, [key], now + 60, 'cookie'), 'expired');
  // The signature is checked before the expiry, so a forgery is never
  // reported as merely expired.
  assert.equal(reason(tamper(grant), [key], now + 60, 'cookie'), 'bad signature');
  assert.equal(reason(grant, [key], now, 'another cookie'), 'session mismatch');
  assert.equal(reason(grant, [key], now, null), 'no session cookie');
  assert.equal(reason(grant, [key], now), 'no session cookie');
  assert.equal(reason(grant, [key], now, ''), 'session mismatch'); // "" is a cookie
  assert.deepEqual(
    m0.verifyGrant(issueGrant(key, now + 60, 'room:1', null), [key], now, null), granted('room:1'));
  for (const bad of [
    '', 'v1', `${grant}.extra`, grant.replace('room:1', 'room/1'),
    grant.replace('v1.', 'v2.'), `v1.é${grant.slice(4)}`,
  ]) {
    assert.equal(reason(bad, [key], now, 'cookie'), 'malformed', JSON.stringify(bad));
  }

  const sreason = (...args) => m0.verifySession(...args).reason;
  const cookieValue = issueSession(key, 'user@example', now + 60);
  assert.equal(sreason(tamper(cookieValue), [key], now), 'bad signature');
  assert.equal(sreason(cookieValue, ['another key'], now), 'unknown key');
  assert.equal(sreason(cookieValue, [key], now + 60), 'expired');
  assert.equal(sreason(tamper(cookieValue), [key], now + 60), 'bad signature');
  for (const bad of [
    '', 'not-a-session-cookie-at-all', `${cookieValue}.extra`,
    cookieValue.replace('user@example', 'user example'), cookieValue.replace('user@example', 'usér'),
  ]) {
    assert.equal(sreason(bad, [key], now), 'malformed', JSON.stringify(bad));
  }
  // Under one key, a grant is never a session and a session never a grant.
  assert.equal(sreason(grant, [key], now), 'malformed');
  assert.equal(reason(cookieValue, [key], now, 'cookie'), 'malformed');
});

test('issueSession refuses what m0 refuses, in its words', () => {
  const refuses = (args, message) => assert.throws(() => m0.issueSession(...args), { message });
  refuses([[], 'notes', 1], 'issue_session: no key');
  refuses([['k'], 'notes', -1], 'issue_session: negative expiry');
  refuses([['k'], '', 1], 'issue_session: subject length');
  refuses([['k'], 'x'.repeat(65), 1], 'issue_session: subject length');
  refuses([['k'], 'a.b', 1], 'issue_session: subject byte');
});

test('arguments are checked, and the message names the function and argument', () => {
  const throwsWith = (fn, message) => assert.throws(fn, { message });
  throwsWith(() => m0.verifyGrant(1, [], 0, null), 'verifyGrant: grant must be a string');
  throwsWith(() => m0.verifyGrant('g', 'k', 0, null), 'verifyGrant: keys must be an array of key strings');
  throwsWith(() => m0.verifyGrant('g', ['k', 2], 0, null), 'verifyGrant: keys[1] must be a string');
  throwsWith(() => m0.verifyGrant('g', ['k'], 1.5, null), 'verifyGrant: now must be a whole number');
  throwsWith(() => m0.verifyGrant('g', ['k'], NaN, null), 'verifyGrant: now must be a whole number');
  throwsWith(() => m0.verifyGrant('g', ['k'], 0, 7), 'verifyGrant: cookie must be a string');
  throwsWith(() => m0.verifyGrant('g', ['k']), 'expected at least 3 arguments');
  throwsWith(() => m0.verifySession('c', ['k'], '0'), 'verifySession: now must be a whole number');
  throwsWith(() => m0.issueSession(['k'], 'notes', 2 ** 53), 'issueSession: exp must be a whole number');
  throwsWith(() => m0.xxhash32('a', 2 ** 32), 'xxhash32: seed must be a whole number from 0 to 4294967295');
});

// --- Hashes -------------------------------------------------------------------

test('hashes match the pinned vectors and read the UTF-8 bytes', () => {
  // mojo-http: packages/m0-core/test/test_hashing.mojo and the smoke-ffi task.
  assert.equal(m0.fnv1a('a'), 0xe40c292c);
  assert.equal(m0.fnv1a('foobar'), 0xbf9cf968);
  assert.equal(m0.xxhash32(''), 0x02cc5d05);
  assert.equal(m0.xxhash32('', 0), 0x02cc5d05);
  assert.notEqual(m0.xxhash32('hello', 42), m0.xxhash32('hello'));
  // Past the 256-byte fast path of the string read, a NUL inside, and a lone
  // surrogate (which both sides encode as U+FFFD).
  for (const text of ['', 'é', 'Ж中🔥', `${'x'.repeat(1000)}🔥`, 'nul\u0000inside', 'lone \ud800']) {
    assert.equal(m0.fnv1a(text), fnv1a(text), JSON.stringify(text));
  }
});
