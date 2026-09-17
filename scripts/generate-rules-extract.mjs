#!/usr/bin/env node
// docs/MOJO-RULES.md — the "Mojo dialect and FFI rules" section of CLAUDE.md,
// extracted so it ships in the npm package.
//
// WHY IT SHIPS: napi-mojo ships SOURCE that downstream compiles against
// (-I node_modules/napi-mojo/src), but CLAUDE.md is not in package.json
// "files". A consumer — or an agent working in a consumer's checkout — gets
// src/, the tutorial and the API reference with none of the rules that keep
// this code from crashing: bare `capturing` reading a dead stack slot, the
// bitcast spelled inline, `_ = x^` as a keep-alive. Those are the mistakes
// the section exists to prevent.
//
// WHY IT IS GENERATED: a hand-maintained extract is itself a lazily checked
// artifact — it drifts from CLAUDE.md silently, and a rules file that is
// subtly wrong is worse than none. So the section is copied verbatim and
// `--check` fails CI when the copy and the source disagree, the same lockstep
// rule src/generated/ and docs/api/ live under.
//
// Relative Markdown links in the section point at files that do not ship, so
// they are rewritten to the repository on GitHub.
//
// Usage:
//   node scripts/generate-rules-extract.mjs          # write docs/MOJO-RULES.md
//   node scripts/generate-rules-extract.mjs --check  # fail if it is stale

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const SRC = 'CLAUDE.md';
const OUT = 'docs/MOJO-RULES.md';
const HEADING = '## Mojo dialect and FFI rules';
const REPO = 'https://github.com/codetalcott/napi-mojo/blob/main/';

export function render(claude) {
  const lines = claude.split('\n');
  const start = lines.indexOf(HEADING);
  if (start < 0) throw new Error(`${SRC}: heading not found: ${HEADING}`);
  let end = start + 1;
  while (end < lines.length && !/^## /.test(lines[end])) end++;
  const section = lines
    .slice(start, end)
    .join('\n')
    .replace(/\s+$/, '')
    // Relative link targets → the repository. Only a target that looks like a
    // repo path (at least one `/`) is rewritten: absolute URLs and anchors
    // stay, and so does Mojo's `name[T](n)` in inline code, which a naive
    // `](…)` match mistakes for a link — it did, on `parallelize[func](n)`.
    .replace(/\]\(((?!https?:\/\/)[\w.-]+(?:\/[\w.-]+)+(?:#[\w-]+)?)\)/g, (_, target) => `](${REPO}${target})`);
  return [
    '# Mojo dialect and FFI rules for napi-mojo',
    '',
    `<!-- GENERATED from ${SRC} by scripts/generate-rules-extract.mjs. Do not edit;`,
    `     edit ${SRC} and run \`npm run generate:rules\`. CI fails if this file is stale. -->`,
    '',
    `> This is the "${HEADING.replace(/^## /, '')}" section of the napi-mojo repository's`,
    `> \`${SRC}\`, extracted verbatim so it ships with the package: it is the same text`,
    '> the framework\'s own maintainers and agents work from. It is written for',
    '> someone changing napi-mojo itself, so some rules cite files that are not in',
    '> the npm tarball; the links point at the repository.',
    '',
    section,
    '',
  ].join('\n');
}

const claude = readFileSync(SRC, 'utf8');
const want = render(claude);

if (process.argv.includes('--check')) {
  const have = existsSync(OUT) ? readFileSync(OUT, 'utf8') : null;
  if (have !== want) {
    console.error(
      `${OUT} is ${have === null ? 'missing' : 'stale'}: it no longer matches the "${HEADING.replace(/^## /, '')}" section of ${SRC}.\n` +
        'Run\n  node scripts/generate-rules-extract.mjs\nand commit the result in the same change.'
    );
    process.exit(1);
  }
  console.log(`${OUT} is up to date with ${SRC}.`);
} else {
  writeFileSync(OUT, want);
  console.log(`wrote ${OUT} (${want.split('\n').length} lines)`);
}
