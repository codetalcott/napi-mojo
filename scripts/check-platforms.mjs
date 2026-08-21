#!/usr/bin/env node
//
// Asserts that every place naming a prebuild platform agrees with the one
// declaration in scripts/platforms.mjs.
//
// Adding a platform touches six files. publish.yml's own comments record what
// happens when one of them is missed: "the same wrong assumption in four
// places", and a broken @napi-mojo/linux-x64 package that shipped for several
// releases because each layer between the bundler and the registry silently
// subtracted a file. That failure is invisible until a consumer's require()
// finds it, and it cannot be caught by any test that runs on the machine that
// built the binary.
//
// This is the cheap structural half of that problem — it cannot tell you a
// binary is good, only that no layer forgot the platform exists. The publish
// pipeline still verifies the actual tarballs.
//
// Usage: node scripts/check-platforms.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PLATFORMS, PLATFORM_KEYS, PLATFORM_PKGS } from './platforms.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(join(root, rel), 'utf8');
const readJson = (rel) => JSON.parse(read(rel));

const problems = [];
const fail = (where, msg) => problems.push(`${where}: ${msg}`);
const sameSet = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

// --- 1. npm/<key>/package.json ----------------------------------------------
const npmDirs = readdirSync(join(root, 'npm'), { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name)
  .sort();

if (!sameSet(npmDirs, PLATFORM_KEYS)) {
  fail('npm/', `directories ${JSON.stringify(npmDirs)} != platforms ${JSON.stringify(PLATFORM_KEYS)}`);
}

for (const p of PLATFORMS) {
  const rel = `npm/${p.key}/package.json`;
  if (!existsSync(join(root, rel))) {
    fail(rel, 'missing — every platform needs its own npm package');
    continue;
  }
  const m = readJson(rel);
  if (m.name !== p.pkg) fail(rel, `name is ${JSON.stringify(m.name)}, expected ${JSON.stringify(p.pkg)}`);
  if (m.main !== 'index.node') fail(rel, `main is ${JSON.stringify(m.main)}, expected "index.node"`);
  if (!sameSet(m.os ?? [], [p.os])) fail(rel, `os is ${JSON.stringify(m.os)}, expected ${JSON.stringify([p.os])}`);
  if (!sameSet(m.cpu ?? [], [p.cpu])) fail(rel, `cpu is ${JSON.stringify(m.cpu)}, expected ${JSON.stringify([p.cpu])}`);
  // The files glob needs the trailing `*`: Linux sonames are versioned
  // (libstdc++.so.6), and a bare "*.so" silently drops them from the tarball.
  // That is a documented past failure, not a hypothetical.
  if (!(m.files ?? []).includes(p.libGlob)) {
    fail(rel, `files is missing ${JSON.stringify(p.libGlob)} — versioned sonames would be dropped from the tarball`);
  }
  if (!(m.files ?? []).includes('index.node')) fail(rel, 'files is missing "index.node"');
}

// --- 2. root package.json optionalDependencies -------------------------------
const rootPkg = readJson('package.json');
const optDeps = Object.keys(rootPkg.optionalDependencies ?? {}).sort();
if (!sameSet(optDeps, PLATFORM_PKGS)) {
  fail('package.json', `optionalDependencies ${JSON.stringify(optDeps)} != ${JSON.stringify(PLATFORM_PKGS)}`);
}

// --- 3. demo.js loader map ---------------------------------------------------
// demo.js is CJS and ships to consumers, so it carries its own copy of the map
// rather than importing platforms.mjs. Parse the literal it declares.
const demo = read('demo.js');
const mapBlock = /const PLATFORMS = \{([\s\S]*?)\};/.exec(demo);
if (!mapBlock) {
  fail('demo.js', 'could not find the `const PLATFORMS = {...}` loader map');
} else {
  const entries = [...mapBlock[1].matchAll(/'([^']+)'\s*:\s*'([^']+)'/g)];
  const keys = entries.map((e) => e[1]).sort();
  if (!sameSet(keys, PLATFORM_KEYS)) {
    fail('demo.js', `PLATFORMS keys ${JSON.stringify(keys)} != ${JSON.stringify(PLATFORM_KEYS)}`);
  }
  for (const [, key, pkg] of entries) {
    const want = PLATFORMS.find((p) => p.key === key)?.pkg;
    if (want && pkg !== want) fail('demo.js', `PLATFORMS["${key}"] is ${pkg}, expected ${want}`);
  }
}

// --- 4. pixi.toml platforms --------------------------------------------------
// The toolchain has to be installable for the platform before anything can be
// built for it, and setup-pixi runs `--locked`, so pixi.lock must cover it too.
const pixiToml = read('pixi.toml');
const platLine = /^platforms\s*=\s*\[([^\]]*)\]/m.exec(pixiToml);
if (!platLine) {
  fail('pixi.toml', 'no `platforms = [...]` key in the [workspace] table');
} else {
  const subdirs = [...platLine[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  for (const p of PLATFORMS) {
    if (!subdirs.includes(p.condaSubdir)) {
      fail('pixi.toml', `platforms is missing "${p.condaSubdir}" (needed to build ${p.key})`);
    }
  }
}
const pixiLock = read('pixi.lock');
for (const p of PLATFORMS) {
  if (!new RegExp(`^- name: ${p.condaSubdir}$`, 'm').test(pixiLock)) {
    fail('pixi.lock', `no solved environment for "${p.condaSubdir}" — run \`pixi lock\` and commit it alongside pixi.toml`);
  }
}

// --- 5. package-lock.json entries --------------------------------------------
// `npm ci` on npm 11+ REFUSES to install when an optionalDependency has no
// lock entry ("Missing: <pkg>@ from lock file"), and npm cannot write one for
// a version that is not published yet — which is every platform's first
// release. npm 10 tolerated it, so this fails only on the Node 24 job, which
// is a confusing place to discover it.
//
// The entry is therefore added by hand, in the shape sync-versions.mjs already
// maintains for the others: version + os + cpu + optional, and deliberately NO
// resolved/integrity (that script strips those, because a stale tarball URL is
// what once made three suites run against a v0.2.10 binary). This check exists
// so the requirement is enforced rather than rediscovered.
const lock = readJson('package-lock.json');
for (const p of PLATFORMS) {
  const key = `node_modules/${p.pkg}`;
  const entry = lock.packages?.[key];
  if (!entry) {
    fail('package-lock.json', `no "${key}" entry — \`npm ci\` on npm 11+ fails with "Missing: ${p.pkg}@ from lock file". Add it by hand: {version, os, cpu, optional} with no resolved/integrity.`);
    continue;
  }
  if (!sameSet(entry.os ?? [], [p.os])) fail('package-lock.json', `${key}.os is ${JSON.stringify(entry.os)}, expected ${JSON.stringify([p.os])}`);
  if (!sameSet(entry.cpu ?? [], [p.cpu])) fail('package-lock.json', `${key}.cpu is ${JSON.stringify(entry.cpu)}, expected ${JSON.stringify([p.cpu])}`);
  if (entry.optional !== true) fail('package-lock.json', `${key} is not marked optional:true — npm would treat a missing prebuild as a hard install failure`);
}
const lockOpt = Object.keys(lock.packages?.['']?.optionalDependencies ?? {}).sort();
if (!sameSet(lockOpt, PLATFORM_PKGS)) {
  fail('package-lock.json', `packages[""].optionalDependencies ${JSON.stringify(lockOpt)} != ${JSON.stringify(PLATFORM_PKGS)}`);
}

// --- 6. sync-versions.mjs platform manifests ---------------------------------
// It carries its own list (it is copied alone into a test fixture, and runs in
// publish.yml), so verify rather than import.
const sync = read('scripts/sync-versions.mjs');
const syncBlock = /const platformPkgs = \[([\s\S]*?)\];/.exec(sync);
if (!syncBlock) {
  fail('scripts/sync-versions.mjs', 'could not find the `const platformPkgs = [...]` list');
} else {
  const listed = [...syncBlock[1].matchAll(/'([^']+)'/g)].map((m) => m[1]).sort();
  const want = PLATFORMS.map((p) => `npm/${p.key}/package.json`).sort();
  if (!sameSet(listed, want)) {
    fail('scripts/sync-versions.mjs', `platformPkgs ${JSON.stringify(listed)} != ${JSON.stringify(want)} — a platform package would publish at the wrong version`);
  }
}

// --- 7. publish.yml ----------------------------------------------------------
// Text assertions rather than a YAML parse: the literal strings are what the
// runner executes, and there is no YAML parser in this repo's dependencies.
const publish = read('.github/workflows/publish.yml');
for (const p of PLATFORMS) {
  if (!publish.includes(`platform: ${p.key}`)) {
    fail('publish.yml', `build matrix has no \`platform: ${p.key}\` entry — nothing would build it`);
  }
  if (!publish.includes(`os: ${p.runner}`)) {
    fail('publish.yml', `build matrix has no \`os: ${p.runner}\` entry for ${p.key}`);
  }
  if (!publish.includes(`Publish ${p.pkg}`)) {
    fail('publish.yml', `no publish step for ${p.pkg} — it would build and never ship`);
  }
}
// The staging and tarball-verification loops each enumerate the platforms.
for (const label of ['Stage platform packages', 'Verify packed tarballs']) {
  const idx = publish.indexOf(label);
  if (idx < 0) {
    fail('publish.yml', `step "${label}" not found`);
    continue;
  }
  const block = publish.slice(idx, idx + 3000);
  for (const p of PLATFORMS) {
    if (!block.includes(p.key)) {
      fail('publish.yml', `"${label}" does not mention ${p.key} — it would be built but not packaged`);
    }
  }
}

// --- 8. README's supported-platform prose ------------------------------------
// Prose goes stale silently; CLAUDE.md says so about embedded counts. Only
// check that each key appears somewhere, not how it is phrased.
const readme = read('README.md');
for (const p of PLATFORMS) {
  if (!readme.includes(p.key)) {
    fail('README.md', `does not mention ${p.key} — consumers cannot tell it is supported`);
  }
}

// --- report ------------------------------------------------------------------
if (problems.length) {
  console.error(`platforms: ${problems.length} inconsistenc${problems.length === 1 ? 'y' : 'ies'} with scripts/platforms.mjs:`);
  for (const p of problems) console.error(`  - ${p}`);
  console.error('\nscripts/platforms.mjs is the single declaration; fix the others to match it.');
  process.exit(1);
}

console.log(
  `platforms: ${PLATFORMS.length} prebuild target(s) — ${PLATFORM_KEYS.join(', ')} — ` +
  'consistent across npm/, package.json, demo.js, pixi.toml, pixi.lock, publish.yml and README.',
);
