#!/usr/bin/env node
// Every Mojo code sample in the prose docs must be a verbatim copy of Mojo
// that CI compiles.
//
// WHY
//
// The README, tutorial, CLAUDE.md and CONTRIBUTING.md carry Mojo blocks, and
// nothing compiled any of them. A retired idiom in one (a bare `capturing`, an
// `UnsafePointer`, a `len(s)` on a String) is exactly what a reader copies
// first, and it rots with every signal green — the same class as an
// uncalled framework method (docs/plan-lazily-checked-artifacts.md). test.yml
// already says the tutorial "quotes examples/tutorial/ line for line"; this
// makes that sentence a check instead of a hope.
//
// THE RULE
//
//   Each ```mojo block in DOCS is split into stanzas on blank lines. Leading
//   comment-only lines of a stanza are a caption and are dropped. Every
//   remaining stanza must appear verbatim — indentation included — in at
//   least one file CI compiles (COMPILED below).
//
//   Stanza-level rather than block-level so a doc can quote an import and a
//   def that are not adjacent in the source. The failure being guarded is a
//   spelling that changed, and any stanza catches that as well as the block.
//
//   A block fenced as ```mojo fragment is exempt: a snippet that has no
//   compilable home (an `...` body, a two-line idiom). Exemptions are counted
//   and printed so they stay visible; any other word after `mojo` is an error.
//
// KNOWN LIMIT: "verbatim in a compiled file" is not "elaborated". A framework
// method body nobody calls compiles unchecked (CLAUDE.md, "Elaboration is
// per-method"); this gate inherits that, and the compile-coverage target is
// the answer to it, not this script.
//
// Usage:
//   node scripts/check-doc-samples.mjs              # check the docs
//   node scripts/check-doc-samples.mjs --self-test  # prove the matcher on a
//                                                   # synthetic doc: passes on a
//                                                   # verbatim copy, fails on a
//                                                   # one-character drift

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Prose a reader writes code from. NOT included, with reasons:
//   docs/toolchain-migrations.md, docs/plan-*.md — dated records that quote
//     the OLD spelling on purpose (that is what a migration note is).
//   docs/MOJO-RULES.md — generated verbatim from CLAUDE.md, which is checked;
//     scripts/generate-rules-extract.mjs --check holds the two together.
//   docs/api/ — generated from docstrings; signatures, not samples.
const DOCS = ['README.md', 'docs/TUTORIAL.md', 'CONTRIBUTING.md', 'CLAUDE.md'];

// What test.yml compiles, by step. Directories skip generated/, build/ and
// .napi-mojo/ — derived output, not source anyone quotes.
//   src/                 Build Mojo addon (lib.mojo roots src/addon and
//                        src/generated; the framework is reached by import),
//                        Compile framework coverage, and the docstring gate
//   examples/*-addon     Build examples
//   examples/tutorial    Tutorial addon end-to-end
//   examples/codegen     Build codegen example
//   examples/host        the host-mode e2e steps (`napi-mojo run` compiles)
//   tests/compile        Compile framework coverage
//   tests/codegen/lib    Compile codegen kitchen sink
//   spike/ffi_probe      FFI probe (build + run)
//   spike/keepalive_probe  Keep-alive barrier counterfactual (IR build)
const SKIP_DIRS = new Set(['generated', 'build', '.napi-mojo', 'node_modules']);
function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (p.endsWith('.mojo')) out.push(p);
  }
  return out;
}
function compiledFiles() {
  return [
    ...walk('src'),
    ...readdirSync('examples').filter((f) => f.endsWith('-addon.mojo')).map((f) => join('examples', f)),
    ...walk('examples/tutorial'),
    ...walk('examples/codegen'),
    ...walk('examples/host'),
    ...walk('tests/compile'),
    'tests/codegen/lib.mojo',
    'spike/ffi_probe.mojo',
    'spike/keepalive_probe.mojo',
  ];
}

/** Parse ```mojo blocks out of Markdown. Returns [{line, tag, body}]. */
export function parseBlocks(text) {
  const lines = text.split('\n');
  const blocks = [];
  for (let i = 0; i < lines.length; i++) {
    const open = /^```mojo(?:\s+(\S.*))?\s*$/.exec(lines[i]);
    if (!open) continue;
    const start = i + 1;
    let j = i + 1;
    while (j < lines.length && !/^```\s*$/.test(lines[j])) j++;
    blocks.push({ line: start, tag: (open[1] ?? '').trim(), body: lines.slice(i + 1, j).join('\n') });
    i = j;
  }
  return blocks;
}

/** Split a block body into stanzas, dropping each stanza's leading comment caption. */
export function stanzas(body) {
  return body
    .split(/\n\s*\n/)
    .map((s) => s.replace(/^(\s*#[^\n]*\n)+/, '').replace(/\s+$/, ''))
    .filter((s) => s.trim().length > 0);
}

/**
 * Check every doc against the sources. Pure: docs and sources are
 * [{path, text}]. Returns {checked, skipped, failures, badTags, emptyDocs}.
 */
export function check(docs, sources) {
  const result = { checked: 0, skipped: [], failures: [], badTags: [], emptyDocs: [] };
  for (const doc of docs) {
    const blocks = parseBlocks(doc.text);
    if (blocks.length === 0) result.emptyDocs.push(doc.path);
    for (const block of blocks) {
      if (block.tag === 'fragment') {
        result.skipped.push(`${doc.path}:${block.line}`);
        continue;
      }
      if (block.tag !== '') {
        result.badTags.push(`${doc.path}:${block.line} \`\`\`mojo ${block.tag}`);
        continue;
      }
      result.checked++;
      for (const stanza of stanzas(block.body)) {
        if (!sources.some((s) => s.text.includes(stanza))) {
          result.failures.push({ where: `${doc.path}:${block.line}`, stanza });
        }
      }
    }
  }
  return result;
}

function selfTest() {
  const src = [{ path: 'x.mojo', text: 'from a import b\n\n\ndef f(x: Int) -> Int:\n    return x + 1\n\n\ndef g() -> None:\n    pass\n' }];
  const doc = (body, tag = '') => [{ path: 'd.md', text: `text\n\n\`\`\`mojo${tag ? ' ' + tag : ''}\n${body}\n\`\`\`\n` }];
  const cases = [
    ['verbatim stanza passes', doc('def f(x: Int) -> Int:\n    return x + 1'), (r) => r.failures.length === 0 && r.checked === 1],
    ['one-character drift fails', doc('def f(x: Int) -> Int:\n    return x + 2'), (r) => r.failures.length === 1],
    ['indentation drift fails', doc('def f(x: Int) -> Int:\n  return x + 1'), (r) => r.failures.length === 1],
    ['caption comment is dropped', doc('# where this lives\ndef f(x: Int) -> Int:\n    return x + 1'), (r) => r.failures.length === 0],
    ['non-adjacent stanzas pass when split by a blank line', doc('from a import b\n\ndef g() -> None:\n    pass'), (r) => r.failures.length === 0],
    ['the same lines with no blank line fail (block-level would be too loose to notice, stanza-level is what passes above)', doc('from a import b\ndef g() -> None:\n    pass'), (r) => r.failures.length === 1],
    ['fragment tag exempts and is counted', doc('anything at all', 'fragment'), (r) => r.failures.length === 0 && r.skipped.length === 1 && r.checked === 0],
    ['unknown tag is an error', doc('def f(x: Int) -> Int:\n    return x + 1', 'sample'), (r) => r.badTags.length === 1],
    ['a doc with no mojo block is flagged', [{ path: 'e.md', text: 'no code here\n' }], (r) => r.emptyDocs.length === 1],
  ];
  let bad = 0;
  for (const [name, docs, ok] of cases) {
    const r = check(docs, src);
    const pass = ok(r);
    if (!pass) bad++;
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${name}`);
  }
  if (bad > 0) {
    console.error(`\ndoc-samples self-test: ${bad} case(s) failed — the matcher has drifted; fix it before trusting a green check.`);
    process.exit(1);
  }
  console.log(`\ndoc-samples self-test: ${cases.length} cases hold.`);
}

if (process.argv.includes('--self-test')) {
  selfTest();
} else {
  const docs = DOCS.map((path) => ({ path, text: readFileSync(path, 'utf8') }));
  const files = compiledFiles();
  const sources = files.map((path) => ({ path, text: readFileSync(path, 'utf8') }));
  const r = check(docs, sources);

  let bad = false;
  if (r.emptyDocs.length > 0) {
    bad = true;
    console.error(`Parser check failed: no \`\`\`mojo block found in ${r.emptyDocs.join(', ')}. Either the doc lost its samples or parseBlocks() no longer matches the fence — an empty parse would otherwise read as a clean pass.\n`);
  }
  if (r.badTags.length > 0) {
    bad = true;
    console.error(`Unknown fence tag(s) — the only tag this gate knows is \`fragment\`:\n  ${r.badTags.join('\n  ')}\n`);
  }
  if (r.failures.length > 0) {
    bad = true;
    console.error(`${r.failures.length} doc stanza(s) are not verbatim in any file CI compiles:\n`);
    for (const f of r.failures) {
      console.error(`--- ${f.where}\n${f.stanza}\n`);
    }
    console.error('Quote the real source (indentation included) from a file this script lists in COMPILED, or — only for a snippet that cannot compile anywhere — fence it as ```mojo fragment.\n');
  }
  if (bad) process.exit(1);

  console.log(`doc samples: ${r.checked} mojo block(s) across ${DOCS.length} docs are verbatim in CI-compiled Mojo (${files.length} files); ${r.skipped.length} fenced as fragment${r.skipped.length ? ': ' + r.skipped.join(', ') : ''}.`);
}
