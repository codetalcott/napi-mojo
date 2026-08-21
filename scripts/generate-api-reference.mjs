#!/usr/bin/env node
//
// Renders the framework API reference from `mojo doc` JSON.
//
// This is step 4 of docs/plan-api-reference.md, and it deliberately did not
// exist until step 3 had content behind it: the plan's own finding was that a
// reference rendered over bare signatures is *worse* than none, because it
// looks complete and says nothing. So this script REFUSES to emit a module
// whose symbols are undocumented beyond a threshold, rather than padding the
// reference with empty headings.
//
// Usage:
//   node scripts/generate-api-reference.mjs                 # write docs/api/
//   node scripts/generate-api-reference.mjs --check         # fail if stale
//   node scripts/generate-api-reference.mjs --mojo "<cmd>"  # driver override
//
// `mojo doc` invocation constraints, both verified on the 1.0.0 pin and both
// worth knowing before losing an hour:
//   -I src   — without it the package imports do not resolve. It does NOT make
//              the target a package member, which is why KNOWN_UNDOCUMENTABLE
//              exists in doc-targets.mjs.
//   a file   — a directory argument produces no output whatsoever.

import { execFile } from 'node:child_process';
import {
  readFileSync, writeFileSync, mkdirSync, mkdtempSync, existsSync, readdirSync, rmSync,
} from 'node:fs';
import { tmpdir, cpus } from 'node:os';
import { join, basename } from 'node:path';
import { KNOWN_UNDOCUMENTABLE, docTargets, resolveMojo } from './doc-targets.mjs';

const OUT_DIR = 'docs/api';
const argv = process.argv.slice(2);
const checkOnly = argv.includes('--check');
const mojoCmd = resolveMojo(argv);

// A module is emitted only if most of its public symbols carry a docstring.
// Below this it is listed in the index as "not yet documented" and linked to
// its source instead — honest about the gap rather than rendering headings
// with nothing under them.
const MIN_DOCUMENTED = 0.75;

const scratch = mkdtempSync(join(tmpdir(), 'napi-mojo-apiref-'));

function runDoc(file) {
  const [bin, ...rest] = mojoCmd.split(/\s+/);
  const out = join(scratch, `${file.replaceAll('/', '_')}.json`);
  return new Promise((resolve) => {
    execFile(
      bin,
      [...rest, 'doc', '-I', 'src', file, '-o', out],
      { maxBuffer: 64 * 1024 * 1024 },
      (err) => resolve({ file, out, ok: !err && existsSync(out) }),
    );
  });
}

async function pool(items, worker, width) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(width, items.length) }, async () => {
      for (;;) {
        const i = next++;
        if (i >= items.length) return;
        results[i] = await worker(items[i]);
      }
    }),
  );
  return results;
}

// --- markdown helpers --------------------------------------------------------

const esc = (s) => String(s ?? '').replace(/\|/g, '\\|');

// `mojo doc` reports the EXPANDED type, so every handle comes out as
// `Pointer[NoneType, MutUntrackedOrigin]` — technically accurate and useless to
// read. Map back to the aliases the source actually uses.
//
// Deliberately conservative. `NapiBindings` is unambiguous. The opaque handle
// aliases are all the SAME underlying type, so nothing in the JSON can
// distinguish NapiEnv from NapiValue; we fall back to the parameter name, which
// is `env` for the environment everywhere in this codebase by convention. A
// misnamed parameter would render the wrong alias, which is why the signature
// line above each table always shows what the compiler actually saw.
const OPAQUE = 'Pointer[NoneType, MutUntrackedOrigin]';
function readableType(type, argName) {
  const t = String(type ?? '');
  if (t === 'Pointer[NapiBindings, MutUntrackedOrigin]') return 'Bindings';
  if (t === OPAQUE) return argName === 'env' ? 'NapiEnv' : 'NapiValue';
  return t;
}
const text = (s) => String(s ?? '').trim();

function anchor(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

/** Count documented vs. total public symbols, mirroring the coverage gate. */
function tally(decl) {
  let total = 0, documented = 0;
  const bump = (d) => { total++; if (text(d)) documented++; };
  for (const s of decl.structs ?? []) {
    bump(s.summary || s.description);
    for (const f of s.fields ?? []) bump(f.summary || f.description);
    for (const fn of s.functions ?? []) {
      for (const o of fn.overloads ?? []) bump(o.summary || o.description);
    }
  }
  for (const fn of decl.functions ?? []) {
    for (const o of fn.overloads ?? []) bump(o.summary || o.description);
  }
  return { total, documented };
}

function renderOverload(o, lines) {
  const sig = text(o.signature);
  if (sig) lines.push('```mojo', sig, '```', '');
  const summary = text(o.summary);
  const desc = text(o.description);
  if (summary) lines.push(summary, '');
  if (desc) lines.push(desc, '');

  const args = (o.args ?? []).filter((a) => text(a.description));
  if (args.length) {
    lines.push('| argument | type | description |', '|---|---|---|');
    for (const a of args) {
      lines.push(`| \`${esc(a.name)}\` | \`${esc(readableType(a.type, a.name))}\` | ${esc(text(a.description).replace(/\n/g, ' '))} |`);
    }
    lines.push('');
  }
  const ret = text(o.returns?.doc);
  if (ret) lines.push(`**Returns** — ${ret.replace(/\n/g, ' ')}`, '');
  const raises = text(o.raisesDoc);
  if (raises) lines.push(`**Raises** — ${raises.replace(/\n/g, ' ')}`, '');
}

function renderModule(decl, srcPath) {
  const lines = [];
  const modName = decl.name;
  lines.push(`# \`${modName}\``, '');
  lines.push(`Source: [\`${srcPath}\`](../../${srcPath})`, '');
  const summary = text(decl.summary);
  const desc = text(decl.description);
  if (summary) lines.push(summary, '');
  if (desc) lines.push(desc, '');

  for (const s of decl.structs ?? []) {
    lines.push('---', '', `## \`${s.name}\``, '');
    const ss = text(s.summary), sd = text(s.description);
    if (ss) lines.push(ss, '');
    if (sd) lines.push(sd, '');

    const fields = (s.fields ?? []).filter((f) => text(f.summary || f.description));
    if (fields.length) {
      lines.push('### Fields', '', '| field | type | description |', '|---|---|---|');
      for (const f of fields) {
        const d = text(f.summary || f.description).replace(/\n/g, ' ');
        lines.push(`| \`${esc(f.name)}\` | \`${esc(readableType(f.type, f.name))}\` | ${esc(d)} |`);
      }
      lines.push('');
    }

    for (const fn of s.functions ?? []) {
      const overloads = (fn.overloads ?? []).filter((o) => text(o.summary || o.description));
      if (!overloads.length) continue;
      lines.push(`### \`${fn.name}\``, '');
      overloads.forEach((o, i) => {
        if (overloads.length > 1) lines.push(`*Overload ${i + 1} of ${overloads.length}.*`, '');
        renderOverload(o, lines);
      });
    }
  }

  const free = (decl.functions ?? []).filter((fn) =>
    (fn.overloads ?? []).some((o) => text(o.summary || o.description)));
  if (free.length) {
    lines.push('---', '', '## Functions', '');
    for (const fn of free) {
      lines.push(`### \`${fn.name}\``, '');
      const overloads = fn.overloads.filter((o) => text(o.summary || o.description));
      overloads.forEach((o, i) => {
        if (overloads.length > 1) lines.push(`*Overload ${i + 1} of ${overloads.length}.*`, '');
        renderOverload(o, lines);
      });
    }
  }

  return lines.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
}

// --- main --------------------------------------------------------------------

const targets = docTargets().filter((f) => !(f in KNOWN_UNDOCUMENTABLE));
console.log(`api reference: running mojo doc over ${targets.length} module(s)…`);

const runs = await pool(targets, runDoc, Math.max(1, Math.min(8, cpus().length - 1)));

const emitted = [];
const skipped = [];
const failed = [];
const files = new Map();

for (const { file, out, ok } of runs) {
  if (!ok) { failed.push(file); continue; }
  const decl = JSON.parse(readFileSync(out, 'utf8')).decl;
  const { total, documented } = tally(decl);
  // A package __init__ shim has no public symbols of its own; a page for it
  // would be a heading and nothing else.
  if (total === 0) continue;
  const ratio = documented / total;
  if (ratio < MIN_DOCUMENTED) {
    skipped.push({ file, documented, total });
    continue;
  }
  files.set(`${decl.name}.md`, renderModule(decl, file));
  emitted.push({ file, name: decl.name, documented, total });
}

// Index
const idx = [];
idx.push('# Framework API reference', '');
idx.push('Generated from Mojo docstrings by `npm run generate:api-reference`.',
         'Do not edit these files by hand — edit the docstrings in `src/napi/`.', '');
idx.push('New to napi-mojo? Start with the [tutorial](../TUTORIAL.md); this is the',
         'reference for the framework surface your addon calls into. The demo',
         "addon's own exports are listed separately in [EXPORTS.md](../EXPORTS.md).", '');
idx.push('## Modules', '', '| module | symbols documented |', '|---|---|');
for (const e of emitted.sort((a, b) => a.name.localeCompare(b.name))) {
  idx.push(`| [\`${e.name}\`](${e.name}.md) | ${e.documented} / ${e.total} |`);
}
idx.push('');
if (skipped.length) {
  idx.push('## Not yet documented', '',
    'These modules are below the documentation threshold, so a rendered page',
    'would be mostly bare signatures. Read the source until they clear it —',
    'each carries a module header comment with usage examples.', '',
    '| module | symbols documented |', '|---|---|');
  for (const s of skipped.sort((a, b) => a.file.localeCompare(b.file))) {
    idx.push(`| [\`${basename(s.file)}\`](../../${s.file}) | ${s.documented} / ${s.total} |`);
  }
  idx.push('');
}
if (Object.keys(KNOWN_UNDOCUMENTABLE).length) {
  idx.push('## Not renderable', '',
    '`mojo doc` compiles its target as a main module, where an explicit',
    '`__moveinit__` fails to compile. These are excluded until that is fixed;',
    '`scripts/check-docstring-coverage.mjs` fails if one starts working.', '');
  for (const [f, why] of Object.entries(KNOWN_UNDOCUMENTABLE)) {
    idx.push(`- [\`${basename(f)}\`](../../${f}) — ${why}`);
  }
  idx.push('');
}
files.set('README.md', idx.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n');

if (checkOnly) {
  const drift = [];
  for (const [name, body] of files) {
    const p = join(OUT_DIR, name);
    if (!existsSync(p) || readFileSync(p, 'utf8') !== body) drift.push(name);
  }
  const extra = existsSync(OUT_DIR)
    ? readdirSync(OUT_DIR).filter((f) => f.endsWith('.md') && !files.has(f))
    : [];
  rmSync(scratch, { recursive: true, force: true });
  if (drift.length || extra.length) {
    console.error('api reference is stale. Run: npm run generate:api-reference');
    for (const d of drift) console.error(`  - out of date: ${d}`);
    for (const e of extra) console.error(`  - orphaned:    ${e}`);
    process.exit(1);
  }
  console.log(`api reference: up to date (${emitted.length} module(s))`);
  process.exit(0);
}

mkdirSync(OUT_DIR, { recursive: true });
for (const f of existsSync(OUT_DIR) ? readdirSync(OUT_DIR) : []) {
  if (f.endsWith('.md') && !files.has(f)) rmSync(join(OUT_DIR, f));
}
for (const [name, body] of files) writeFileSync(join(OUT_DIR, name), body);
rmSync(scratch, { recursive: true, force: true });

console.log(`api reference: wrote ${files.size} file(s) to ${OUT_DIR}/`);
console.log(`  rendered: ${emitted.length} module(s)`);
if (skipped.length) console.log(`  below threshold (listed, not rendered): ${skipped.length}`);
if (failed.length) {
  console.error(`  mojo doc FAILED on ${failed.length} module(s):`);
  for (const f of failed) console.error(`    - ${f}`);
  process.exit(1);
}
