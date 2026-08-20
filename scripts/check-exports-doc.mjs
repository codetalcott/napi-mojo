#!/usr/bin/env node
// Drift guard for docs/EXPORTS.md and the exported-function counts in prose.
//
// WHY THIS EXISTS
//
// CLAUDE.md already warns that "nothing updates numbers embedded in prose",
// and within a week of that warning the count went stale anyway: the
// continuation PR added thenDouble and deferredRequire, and README (x2),
// CLAUDE.md (x2) and the EXPORTS table all kept saying 150.
//
// Every other invariant in this repo has a gate — compile coverage, docstring
// floor, codegen drift, benchmark ceilings. This is the missing one. It turns
// a number embedded in prose from a liability into a checked fact, which is
// the only way an embedded number survives.
//
// Usage:
//   node scripts/check-exports-doc.mjs
import { readFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ADDON = 'build/index.node';
const DOC = 'docs/EXPORTS.md';

if (!existsSync(ADDON)) {
  console.error(`${ADDON} not found — run \`pixi run bash build.sh\` first.`);
  process.exit(1);
}

const addon = require(`../${ADDON}`);
const names = Object.getOwnPropertyNames(addon).filter((n) => n !== '__esModule');

let fnCount = 0;
let classCount = 0;
for (const n of names) {
  let v;
  try { v = addon[n]; } catch { continue; }
  if (typeof v !== 'function') continue;
  // Classes are the capitalised exports; everything else is a plain function.
  if (/^[A-Z]/.test(n)) classCount++;
  else fnCount++;
}

const doc = readFileSync(DOC, 'utf8');
const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const undocumented = names.filter(
  (n) => !new RegExp(`\\b${escape(n)}\\b`).test(doc)
);

const problems = [];

if (undocumented.length > 0) {
  problems.push(
    `${undocumented.length} export(s) missing from ${DOC}:\n` +
      undocumented.map((n) => `  ${n}`).join('\n')
  );
}

// Counts embedded in prose must match what the addon actually exports.
const CLAIM = /(\d+) exported functions/g;
for (const file of ['README.md', 'CLAUDE.md']) {
  const text = readFileSync(file, 'utf8');
  for (const m of text.matchAll(CLAIM)) {
    if (Number(m[1]) !== fnCount) {
      problems.push(
        `${file} claims "${m[1]} exported functions" but the addon exports ${fnCount}.`
      );
    }
  }
}

if (problems.length > 0) {
  console.error(`\n${problems.join('\n\n')}\n`);
  console.error(
    `Add the missing rows to ${DOC} and correct the counts, in the same commit\n` +
      `as the export that changed them.\n`
  );
  process.exit(1);
}

console.log(
  `exports doc: all ${names.length} exports (${fnCount} functions, ${classCount} classes) ` +
    `appear in ${DOC}, and the prose counts agree.`
);
