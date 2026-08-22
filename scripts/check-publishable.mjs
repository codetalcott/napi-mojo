#!/usr/bin/env node
//
// Publish preflight: can every package this release will push actually be
// pushed, before we spend three platform builds finding out?
//
// WHY THIS EXISTS. The 0.13.0 release added @napi-mojo/linux-arm64 and failed
// at the very last step, after all three platform builds had completed:
//
//     npm error code E404
//     npm error 404 Not Found - PUT https://registry.npmjs.org/@napi-mojo%2flinux-arm64
//
// That is not a missing resource. npm returns 404 rather than 401/403 for
// scoped packages so a stranger cannot probe which private packages exist, so
// E404-on-PUT is an AUTHORIZATION failure wearing a disguise — the same
// disguise that made the v0.5.0 token failure hard to read.
//
// The cause: npm's OIDC trusted publishing cannot BOOTSTRAP a package. Trusted
// publishing is configured per package on npmjs.com, and a package that has
// never been published has no configuration to match against. So the first
// publish of any new platform package has to be done another way, and every
// release after that works over OIDC as normal.
//
// The damage was not the failure, it was the ORDER: darwin-arm64 and linux-x64
// published at the new version, linux-arm64 did not, and the root package's
// publish step never ran — leaving two orphaned platform versions and a root
// package still on the previous release. Nothing broke for consumers, because
// optionalDependencies pin exact versions, but the release was half-applied
// and needed a human to finish it.
//
// Usage:
//   node scripts/check-publishable.mjs           # report; exit 1 if blocked
//   node scripts/check-publishable.mjs --warn    # report; always exit 0
//
// --warn is for the workflow_dispatch rehearsal, which should exercise the
// pipeline without being blocked by a package that a real release would have
// to create first.

import { execFile } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PLATFORMS } from './platforms.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const rootPkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const warnOnly = process.argv.includes('--warn');

/** `npm view <pkg> version` → the published version, or null if absent. */
function published(pkg) {
  return new Promise((resolve) => {
    execFile(
      'npm',
      ['view', pkg, 'version'],
      { timeout: 60_000 },
      (err, stdout) => resolve(err ? null : stdout.trim() || null),
    );
  });
}

const targets = [
  { name: rootPkg.name, kind: 'root package' },
  ...PLATFORMS.map((p) => ({ name: p.pkg, kind: `${p.key} prebuild` })),
];

const results = await Promise.all(
  targets.map(async (t) => ({ ...t, version: await published(t.name) })),
);

const missing = results.filter((r) => r.version === null);

console.log(`publish preflight — target version ${rootPkg.version}`);
for (const r of results) {
  const state = r.version === null ? 'NEVER PUBLISHED' : `latest ${r.version}`;
  console.log(`  ${r.version === null ? '✗' : '✓'} ${r.name.padEnd(28)} ${state}   (${r.kind})`);
}

if (missing.length === 0) {
  console.log('\nAll packages exist; OIDC trusted publishing can push new versions of each.');
  process.exit(0);
}

const lines = [
  '',
  `${missing.length} package(s) have never been published, and npm's OIDC trusted`,
  'publishing CANNOT create a package — it matches against a per-package trusted',
  'publisher configured on npmjs.com, which a nonexistent package does not have.',
  'The publish step for each will fail with a misleading `E404 ... PUT`, which is',
  'an authorization failure, not a missing resource.',
  '',
  'To unblock, for each package below:',
  '',
];
for (const m of missing) {
  lines.push(`  cd npm/${m.name.split('/')[1] ?? '.'} && npm publish --access public`);
}
lines.push(
  '',
  'then add its trusted publisher on npmjs.com (repository codetalcott/napi-mojo,',
  'workflow publish.yml, environment npm) so later releases go over OIDC.',
  '',
  'Check first whether npmjs.com now lets you pre-configure a trusted publisher',
  'for a not-yet-existing package name; if it does, that skips the token entirely.',
);

if (warnOnly) {
  console.log(lines.join('\n'));
  console.log('\n(--warn: not failing. A real release would stop here.)');
  process.exit(0);
}

console.error(lines.join('\n'));
process.exit(1);
