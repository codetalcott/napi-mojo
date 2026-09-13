#!/usr/bin/env node
/**
 * check-glibc-floor.mjs — would the HOST's GCC runtime satisfy what we ship?
 *
 * The Linux platform packages do NOT bundle GCC's libstdc++.so.6 or
 * libgcc_s.so.1 (HOST_PROVIDED in bundle-runtime.sh); they rely on the host's.
 * That is sound because the Mojo runtime requires at most GLIBCXX_3.4.30,
 * while its GLIBC_2.35 requirement — which CANNOT be bundled, because glibc is
 * the loader — already implies a host whose own GCC runtime provides it
 * (docs/plan-distribution.md).
 *
 * That argument holds only as long as the floors stay in that order, and
 * NOTHING WOULD NOTICE IF THEY STOPPED. A Mojo release that raises the
 * required GLIBCXX (or libgcc_s's GCC_ version) above what the glibc floor
 * implies would ship a package that fails at require() on hosts it claims to
 * support. This gate turns that into a red build.
 *
 * THE QUESTION IT ANSWERS, precisely: taking the files we ship EXCEPT the GCC
 * runtime itself, what GLIBC / GLIBCXX / CXXABI / GCC versions do they
 * require, and are the GCC-runtime ones satisfied by every mainstream
 * distribution whose glibc is new enough to load us at all?
 *
 * It reads ELF version requirements (.gnu.version_r) directly rather than
 * shelling out, for the reason check-portable.mjs records at length: readelf
 * and objdump are not available and not identical everywhere, and a parser
 * that cannot read the file reports the artifact as fine.
 *
 * Linux only. On macOS there is no glibc and no libstdc++ — Mojo links the
 * system libc++ — so the script reports that and exits 0 rather than
 * pretending to have checked something.
 *
 * Usage:
 *   node scripts/check-glibc-floor.mjs build/index.node
 *   node scripts/check-glibc-floor.mjs --json build/index.node
 *   node scripts/check-glibc-floor.mjs --self-test
 */

import { readFileSync, existsSync, statSync } from 'node:fs';
import { dirname, basename, join, resolve, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// What a host provides, by distribution.
//
// Each row is a mainstream distribution's shipped glibc, the GLIBCXX / CXXABI
// its default libstdc++6 package provides, and the GCC major its libgcc_s
// comes from. A GCC_x.y.z symbol version is introduced by GCC x, so a libgcc_s
// from GCC N provides every GCC_ version whose major is <= N. The gate does NOT trust any
// single row: given a required glibc it takes every row that could host us
// (glibc >= required) and uses the LOWEST GLIBCXX among them, so the answer is
// the worst case a user might actually be on rather than a convenient one.
//
// Rows are a floor, not a census. A hand-built container with new glibc and an
// old libstdc++ is constructible and is not represented here — which is why
// removing the bundled copy also wants the old-distribution consume job in
// publish.yml, not this gate alone.
// ---------------------------------------------------------------------------
const HOSTS = [
  { distro: 'RHEL 8 / CentOS 8', glibc: '2.28', glibcxx: '3.4.25', cxxabi: '1.3.11', gcc: '8' },
  { distro: 'Ubuntu 20.04', glibc: '2.31', glibcxx: '3.4.28', cxxabi: '1.3.12', gcc: '10' },
  { distro: 'Debian 11', glibc: '2.31', glibcxx: '3.4.28', cxxabi: '1.3.12', gcc: '10' },
  { distro: 'RHEL 9', glibc: '2.34', glibcxx: '3.4.29', cxxabi: '1.3.13', gcc: '11' },
  { distro: 'Ubuntu 22.04', glibc: '2.35', glibcxx: '3.4.30', cxxabi: '1.3.13', gcc: '12' },
  { distro: 'Debian 12', glibc: '2.36', glibcxx: '3.4.30', cxxabi: '1.3.13', gcc: '12' },
  { distro: 'Ubuntu 24.04', glibc: '2.39', glibcxx: '3.4.33', cxxabi: '1.3.15', gcc: '14' },
];

// Host-provided families checked against the table, and the HOSTS column each
// is compared with. GLIBC is not here: it is the floor that selects the rows.
const HOST_FAMILIES = [
  { family: 'GLIBCXX', column: 'glibcxx', lib: 'libstdc++' },
  { family: 'CXXABI', column: 'cxxabi', lib: 'libstdc++' },
  { family: 'GCC', column: 'gcc', lib: 'libgcc_s' },
];

// The GCC runtime is what this gate is asking about, so its own requirements
// are excluded from the "what do we need from the host" tally: including them
// would let the thing under question answer for itself.
const GCC_RUNTIME = [/^libstdc\+\+\.so/, /^libgcc_s\.so/];

const SYSTEM_SONAMES = [
  'libc.', 'libm.', 'libdl.', 'libpthread.', 'librt.', 'libutil.',
  'libgcc_s.', 'libstdc++.', 'ld-linux', 'libresolv.', 'libnsl.',
  'libcrypt.', 'libatomic.', 'libanl.', 'libthread_db.',
];
const SELF_RELATIVE = ['$ORIGIN', '@loader_path', '@executable_path'];

class InspectError extends Error {}

const parseVersion = (s) => s.split('.').map((n) => parseInt(n, 10) || 0);
const cmpVersion = (a, b) => {
  const [x, y] = [parseVersion(a), parseVersion(b)];
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0);
  }
  return 0;
};
const maxVersion = (versions) =>
  versions.length ? versions.reduce((a, b) => (cmpVersion(a, b) >= 0 ? a : b)) : null;

// ---------------------------------------------------------------------------
// ELF: dynamic entries, and the version requirements in .gnu.version_r.
// ---------------------------------------------------------------------------

const DT_NEEDED = 1, DT_STRTAB = 5, DT_SONAME = 14, DT_RPATH = 15, DT_RUNPATH = 29;
const DT_VERNEED = 0x6ffffffe, DT_VERNEEDNUM = 0x6fffffff;

export function readElf(path) {
  const data = readFileSync(path);
  if (data.length < 64 || data.readUInt32BE(0) !== 0x7f454c46) {
    throw new InspectError(`${basename(path)}: not an ELF file`);
  }
  if (data[4] !== 2) throw new InspectError(`${basename(path)}: not a 64-bit ELF`);
  const le = data[5] === 1;
  const u16 = (o) => (le ? data.readUInt16LE(o) : data.readUInt16BE(o));
  const u32 = (o) => (le ? data.readUInt32LE(o) : data.readUInt32BE(o));
  const u64 = (o) => Number(le ? data.readBigUInt64LE(o) : data.readBigUInt64BE(o));
  const i64 = (o) => Number(le ? data.readBigInt64LE(o) : data.readBigInt64BE(o));

  const phoff = u64(0x20);
  const phentsize = u16(0x36);
  const phnum = u16(0x38);

  let dyn = null;
  const loads = [];
  for (let i = 0; i < phnum; i++) {
    const base = phoff + i * phentsize;
    if (base + 56 > data.length) throw new InspectError('program headers run past end of file');
    const pType = u32(base);
    const pOffset = u64(base + 8);
    const pVaddr = u64(base + 16);
    const pFilesz = u64(base + 32);
    if (pType === 2) dyn = [pOffset, pFilesz];
    else if (pType === 1) loads.push([pVaddr, pFilesz, pOffset]);
  }
  if (dyn === null) throw new InspectError(`${basename(path)}: no PT_DYNAMIC segment`);

  const vaddrToOff = (v) => {
    for (const [pVaddr, pFilesz, pOffset] of loads) {
      if (pVaddr <= v && v < pVaddr + pFilesz) return pOffset + (v - pVaddr);
    }
    throw new InspectError(`address 0x${v.toString(16)} is in no PT_LOAD segment`);
  };

  const [dynOff, dynSize] = dyn;
  const entries = [];
  let strtabV = null, verneedV = null, verneedNum = 0;
  for (let off = dynOff; off + 16 <= dynOff + dynSize && off + 16 <= data.length; off += 16) {
    const tag = i64(off);
    const val = u64(off + 8);
    if (tag === 0) break;
    if (tag === DT_STRTAB) strtabV = val;
    else if (tag === DT_VERNEED) verneedV = val;
    else if (tag === DT_VERNEEDNUM) verneedNum = val;
    entries.push([tag, val]);
  }
  if (strtabV === null) throw new InspectError(`${basename(path)}: no DT_STRTAB`);
  const strtab = vaddrToOff(strtabV);
  const sAt = (idx) => {
    const start = strtab + idx;
    const stop = data.indexOf(0, start);
    return data.subarray(start, stop === -1 ? data.length : stop).toString('utf8');
  };

  const search = [];
  const needed = [];
  let soname = null;
  for (const [tag, val] of entries) {
    if (tag === DT_NEEDED) needed.push(sAt(val));
    else if (tag === DT_SONAME) soname = sAt(val);
    else if (tag === DT_RPATH || tag === DT_RUNPATH) {
      for (const q of sAt(val).split(':')) if (q) search.push(q);
    }
  }

  // .gnu.version_r — one Verneed per dependency that supplies versioned
  // symbols, each with vn_cnt Vernaux entries naming the versions required.
  //
  //   Elf64_Verneed { Half version, cnt; Word file, aux, next; }   16 bytes
  //   Elf64_Vernaux { Word hash; Half flags, other; Word name, next; } 16 bytes
  //
  // `aux` and `next` are byte offsets from the START OF THEIR OWN RECORD, not
  // from the section — getting that wrong yields a plausible-looking empty
  // result rather than an error, so the self-test pins a known file.
  const versionNeeds = {};
  if (verneedV !== null && verneedNum > 0) {
    let vn = vaddrToOff(verneedV);
    for (let i = 0; i < verneedNum; i++) {
      if (vn + 16 > data.length) throw new InspectError('verneed runs past end of file');
      const vnCnt = u16(vn + 2);
      const vnFile = u32(vn + 4);
      const vnAux = u32(vn + 8);
      const vnNext = u32(vn + 12);
      const file = sAt(vnFile);
      const list = (versionNeeds[file] ??= []);
      let aux = vn + vnAux;
      for (let j = 0; j < vnCnt; j++) {
        if (aux + 16 > data.length) throw new InspectError('vernaux runs past end of file');
        list.push(sAt(u32(aux + 8)));
        const auxNext = u32(aux + 12);
        if (!auxNext) break;
        aux += auxNext;
      }
      if (!vnNext) break;
      vn += vnNext;
    }
  }
  return { path, soname, search, needed, versionNeeds };
}

/** Split "GLIBCXX_3.4.30" into its family and version. */
function splitVersion(tag) {
  const m = /^([A-Z_a-z+]+)_(\d[\d.]*)$/.exec(tag);
  return m ? { family: m[1], version: m[2] } : null;
}

// ---------------------------------------------------------------------------
// The closure: everything we ship, reached from the entry through its own
// recorded search paths. Works before bundling (RUNPATH points at the pixi
// environment) and after (RUNPATH is $ORIGIN), which is what lets this run in
// test.yml on every PR rather than only at release.
// ---------------------------------------------------------------------------
export function closure(entry) {
  const seen = new Map();
  const missing = [];
  const queue = [resolve(entry)];

  while (queue.length) {
    const p = queue.shift();
    if (seen.has(p)) continue;
    const elf = readElf(p);
    seen.set(p, elf);

    const here = dirname(p);
    for (const dep of elf.needed) {
      if (SYSTEM_SONAMES.some((s) => dep.startsWith(s))) continue;
      let found = null;
      for (const sp of elf.search.length ? elf.search : ['$ORIGIN']) {
        const prefix = SELF_RELATIVE.find((s) => sp.startsWith(s));
        const dir = prefix
          ? normalize(join(here, sp.slice(prefix.length).replace(/^\/+/, '')))
          : sp;
        const candidate = join(dir, dep);
        if (existsSync(candidate) && statSync(candidate).isFile()) { found = candidate; break; }
      }
      if (found) queue.push(resolve(found));
      else missing.push({ from: basename(p), dep });
    }
  }
  return { files: [...seen.values()], missing };
}

// ---------------------------------------------------------------------------

export function analyse(entry) {
  const { files, missing } = closure(entry);
  return { entry, ...evaluate(files, missing) };
}

/**
 * The verdict, from an already-walked closure. Separate from analyse() so the
 * self-test drives THIS code with synthetic files — the failure paths are the
 * ones a healthy artifact never exercises, so a test that re-derives them
 * inline stays green while the real comparison is broken.
 */
export function evaluate(files, missing, hostTable = HOSTS) {
  const shipped = files.filter((f) => !GCC_RUNTIME.some((re) => re.test(basename(f.path))));
  const excluded = files.filter((f) => GCC_RUNTIME.some((re) => re.test(basename(f.path))));

  const required = {};      // family -> [versions]
  const attributed = {};    // family -> { version -> [files] }
  for (const f of shipped) {
    for (const versions of Object.values(f.versionNeeds)) {
      for (const tag of versions) {
        const parsed = splitVersion(tag);
        if (!parsed) continue;
        (required[parsed.family] ??= []).push(parsed.version);
        ((attributed[parsed.family] ??= {})[parsed.version] ??= []).push(basename(f.path));
      }
    }
  }

  const maxOf = (family) => maxVersion(required[family] ?? []);
  const neededGlibc = maxOf('GLIBC');
  const neededGlibcxx = maxOf('GLIBCXX');
  const neededCxxabi = maxOf('CXXABI');
  const neededGcc = maxOf('GCC');

  // Every distribution whose glibc is new enough to load us at all, and the
  // worst of each host-provided version among them.
  const hosts = neededGlibc
    ? hostTable.filter((h) => cmpVersion(h.glibc, neededGlibc) >= 0)
    : hostTable.slice();
  const worst = (column) => hosts.length
    ? hosts.map((h) => h[column]).reduce((a, b) => (cmpVersion(a, b) <= 0 ? a : b))
    : null;
  const impliedGlibcxx = worst('glibcxx');
  const impliedCxxabi = worst('cxxabi');
  const impliedGcc = worst('gcc');

  const problems = [];
  // An unresolved dependency is a FAILURE, not a note. The libraries we ship
  // are where the requirements live — libKGENCompilerRTShared.so is the one
  // carrying GLIBCXX_3.4.30 — so a walk that cannot open them reports
  // "requires nothing" and greenlights on an empty tally. Found by running
  // this against index.node with no siblings present, where it happily
  // printed "GLIBCXX: (none)" and passed.
  if (missing.length) {
    problems.push(
      `could not resolve ${missing.map((m) => `${m.dep} (needed by ${m.from})`).join(', ')} — ` +
      `the tally below is incomplete and must not be read as a clean bill. ` +
      `Run this where the artifact's own search paths resolve: the build tree before bundling, ` +
      `or the staged directory after.`
    );
  }
  if (!neededGlibc) {
    problems.push('no GLIBC requirement found — the parse probably read nothing; treat as a parser failure, not a clean bill');
  }
  if (!hosts.length) {
    problems.push(`GLIBC_${neededGlibc} is newer than every distribution in the table — the table is stale, or this build targets nothing shippable`);
  }
  const needed = { GLIBCXX: neededGlibcxx, CXXABI: neededCxxabi, GCC: neededGcc };
  const implied = { GLIBCXX: impliedGlibcxx, CXXABI: impliedCxxabi, GCC: impliedGcc };
  for (const { family, column, lib } of HOST_FAMILIES) {
    const [need, have] = [needed[family], implied[family]];
    if (!need || !have || cmpVersion(need, have) <= 0) continue;
    const shownHave = family === 'GCC' ? `GCC_${have}.x (libgcc_s from GCC ${have})` : `${family}_${have}`;
    problems.push(
      `${family}_${need} is required but a GLIBC_${neededGlibc} host only guarantees ${shownHave} ` +
      `(worst case: ${hosts.filter((h) => h[column] === have).map((h) => h.distro).join(', ')}). ` +
      `The host ${lib} no longer satisfies the Mojo runtime: bundle-runtime.sh's HOST_PROVIDED ` +
      `premise is void — see docs/plan-distribution.md before shipping.`
    );
  }

  return {
    files: files.map((f) => basename(f.path)), excluded: excluded.map((f) => basename(f.path)),
    missing, neededGlibc, neededGlibcxx, neededCxxabi, neededGcc, impliedGlibcxx, impliedCxxabi, impliedGcc,
    hosts: hosts.map((h) => h.distro), attributed, problems,
  };
}

function report(a) {
  console.log(`entry            : ${a.entry}`);
  console.log(`closure          : ${a.files.join(', ')}`);
  if (a.excluded.length) {
    console.log(`excluded         : ${a.excluded.join(', ')} (the GCC runtime cannot answer for itself)`);
  }
  if (a.missing.length) {
    console.log(`unresolved       : ${a.missing.map((m) => `${m.dep} (from ${m.from})`).join(', ')}`);
  }
  console.log('');
  console.log(`requires GLIBC   : ${a.neededGlibc ?? '(none)'}   <- cannot be bundled; this is the real floor`);
  console.log(`requires GLIBCXX : ${a.neededGlibcxx ?? '(none)'}`);
  console.log(`requires CXXABI  : ${a.neededCxxabi ?? '(none)'}`);
  console.log(`requires GCC     : ${a.neededGcc ?? '(none)'}   <- libgcc_s`);
  console.log('');
  console.log(`a GLIBC_${a.neededGlibc} host is at least: ${a.hosts.join(', ')}`);
  console.log(
    `  and so provides at least GLIBCXX_${a.impliedGlibcxx}, CXXABI_${a.impliedCxxabi}, ` +
    `and libgcc_s from GCC ${a.impliedGcc}`
  );

  for (const [family, versions] of Object.entries(a.attributed)) {
    const top = maxVersion(Object.keys(versions));
    if (top) console.log(`\n  ${family}_${top} comes from: ${[...new Set(versions[top])].join(', ')}`);
  }

  if (a.problems.length) {
    console.error('\ncheck-glibc-floor: FAIL\n');
    for (const p of a.problems) console.error('  - ' + p + '\n');
    return 1;
  }
  console.log('\ncheck-glibc-floor: the host GCC runtime implied by our own glibc floor satisfies us');
  console.log('on every distribution in the table, so leaving libstdc++ and libgcc_s to the host is sound.');
  return 0;
}

// ---------------------------------------------------------------------------
// Self-test. The verneed walk is the part that fails SILENTLY when wrong —
// a mis-stepped offset yields an empty result, which reads as "requires
// nothing", which reads as "fine". So it is pinned against a real binary
// whose answer is independently knowable: this Node, which must require a
// versioned GLIBC symbol because it is dynamically linked against glibc.
// ---------------------------------------------------------------------------
function selfTest() {
  const cases = [];
  const check = (name, fn) => {
    try { fn(); cases.push([name, null]); } catch (e) { cases.push([name, e.message]); }
  };

  check('version comparison orders correctly', () => {
    if (cmpVersion('3.4.30', '3.4.9') <= 0) throw new Error('3.4.30 must exceed 3.4.9 — string compare would not');
    if (cmpVersion('2.35', '2.4') <= 0) throw new Error('2.35 must exceed 2.4');
    if (cmpVersion('3.4.30', '3.4.30') !== 0) throw new Error('equal versions must compare equal');
  });

  check('splitVersion parses the three families', () => {
    for (const [tag, family, version] of [
      ['GLIBC_2.35', 'GLIBC', '2.35'],
      ['GLIBCXX_3.4.30', 'GLIBCXX', '3.4.30'],
      ['CXXABI_1.3.11', 'CXXABI', '1.3.11'],
    ]) {
      const got = splitVersion(tag);
      if (!got || got.family !== family || got.version !== version) {
        throw new Error(`${tag} parsed as ${JSON.stringify(got)}`);
      }
    }
  });

  check('verneed walk finds a real GLIBC requirement (skipped off Linux)', () => {
    if (process.platform !== 'linux') return;
    const elf = readElf(process.execPath);
    const all = Object.values(elf.versionNeeds).flat();
    if (!all.length) throw new Error('parsed no version requirements from node itself — the verneed walk is broken');
    if (!all.some((t) => t.startsWith('GLIBC_'))) {
      throw new Error(`node requires no GLIBC_ version? got ${JSON.stringify(all.slice(0, 8))}`);
    }
  });

  // The cases below drive evaluate() — the code the real run uses — with a
  // synthetic closure. Their failure paths are the ones today's healthy
  // artifact never reaches, so only a synthetic input can prove they fire.
  const lib = (name, needs) => ({ path: `/fixture/${name}`, versionNeeds: needs });
  const today = () => [
    lib('index.node', { 'libc.so.6': ['GLIBC_2.34'] }),
    lib('libKGENCompilerRTShared.so', {
      'libc.so.6': ['GLIBC_2.35'],
      'libstdc++.so.6': ['GLIBCXX_3.4.30', 'CXXABI_1.3.13'],
      'libgcc_s.so.1': ['GCC_3.3'],
    }),
  ];
  const problemsOf = (files, missing = []) => evaluate(files, missing).problems;

  check('the shape of the current artifact passes', () => {
    const p = problemsOf(today());
    if (p.length) throw new Error(`expected no problems, got ${JSON.stringify(p)}`);
  });

  check('a raised GLIBCXX requirement is caught', () => {
    const files = today();
    files[1].versionNeeds['libstdc++.so.6'].push('GLIBCXX_3.4.31');
    if (!problemsOf(files).some((p) => p.startsWith('GLIBCXX_3.4.31'))) {
      throw new Error('GLIBCXX_3.4.31 against a GLIBC_2.35 (3.4.30) floor must be a problem');
    }
  });

  check('a raised libgcc_s GCC_ requirement is caught', () => {
    const files = today();
    files[1].versionNeeds['libgcc_s.so.1'].push('GCC_13.0.0');
    if (!problemsOf(files).some((p) => p.startsWith('GCC_13.0.0'))) {
      throw new Error('GCC_13.0.0 against a GLIBC_2.35 floor (GCC 12 hosts) must be a problem');
    }
    const ok = today();
    ok[1].versionNeeds['libgcc_s.so.1'].push('GCC_12.0.0');
    if (problemsOf(ok).length) throw new Error('GCC_12.0.0 must pass against GCC 12 hosts');
  });

  check('an unresolvable dependency fails rather than passing empty', () => {
    // The regression found by running the gate on an artifact whose siblings
    // were absent: the tally came back empty and the gate said fine.
    const p = problemsOf(today().slice(0, 1), [{ from: 'index.node', dep: 'libKGENCompilerRTShared.so' }]);
    if (!p.some((x) => x.startsWith('could not resolve'))) {
      throw new Error('an unresolved dependency must produce a problem');
    }
  });

  check('an empty tally is a parser failure, not a clean bill', () => {
    if (!problemsOf([lib('index.node', {})]).some((x) => x.startsWith('no GLIBC requirement'))) {
      throw new Error('no GLIBC requirement at all must be a problem');
    }
  });

  check('the worst case is taken, not a convenient one', () => {
    // RHEL 9 is glibc 2.34 with GLIBCXX_3.4.29: a build needing only
    // GLIBC_2.34 must be held to 3.4.29, not to Ubuntu 22.04's 3.4.30.
    const files = [lib('index.node', { 'libc.so.6': ['GLIBC_2.34'], 'libstdc++.so.6': ['GLIBCXX_3.4.30'] })];
    const a = evaluate(files, []);
    if (a.impliedGlibcxx !== '3.4.29') throw new Error(`expected the RHEL 9 floor 3.4.29, got ${a.impliedGlibcxx}`);
    if (!a.problems.some((p) => p.startsWith('GLIBCXX_3.4.30'))) throw new Error('3.4.30 must fail on RHEL 9');
  });

  check('host table rows are internally consistent', () => {
    // CXXABI and GLIBCXX move together per GCC release; a row mixing two
    // releases is a transcription error (Ubuntu 24.04 once had GCC 13's
    // GLIBCXX beside GCC 14's CXXABI).
    const byGcc = { 8: ['3.4.25', '1.3.11'], 10: ['3.4.28', '1.3.12'], 11: ['3.4.29', '1.3.13'],
      12: ['3.4.30', '1.3.13'], 13: ['3.4.32', '1.3.14'], 14: ['3.4.33', '1.3.15'] };
    for (const h of HOSTS) {
      const want = byGcc[h.gcc];
      if (!want) throw new Error(`${h.distro}: no reference for GCC ${h.gcc}`);
      if (h.glibcxx !== want[0] || h.cxxabi !== want[1]) {
        throw new Error(`${h.distro}: GCC ${h.gcc} ships GLIBCXX_${want[0]} / CXXABI_${want[1]}, row has ${h.glibcxx} / ${h.cxxabi}`);
      }
    }
  });

  const failed = cases.filter(([, e]) => e);
  for (const [name, err] of cases) console.log(`${err ? 'FAIL' : ' ok '}  ${name}${err ? ` — ${err}` : ''}`);
  console.log(`\ncheck-glibc-floor --self-test: ${cases.length - failed.length}/${cases.length} passed`);
  return failed.length ? 1 : 0;
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--self-test')) process.exit(selfTest());

  if (process.platform !== 'linux') {
    console.log('check-glibc-floor: not Linux — there is no glibc or libstdc++ floor to check here.');
    console.log('(Mojo links the system libc++ on macOS, and no GCC runtime is bundled there.)');
    process.exit(0);
  }

  const json = argv.includes('--json');
  const positional = argv.filter((a) => !a.startsWith('--'));
  if (positional.length !== 1) {
    console.error('usage: check-glibc-floor.mjs [--json] <artifact>\n       check-glibc-floor.mjs --self-test');
    process.exit(2);
  }
  if (!existsSync(positional[0])) {
    console.error(`check-glibc-floor: ${positional[0]} does not exist`);
    process.exit(2);
  }

  let a;
  try {
    a = analyse(positional[0]);
  } catch (e) {
    console.error(`check-glibc-floor: ${e.message}`);
    process.exit(2);
  }
  if (json) {
    console.log(JSON.stringify(a, null, 2));
    process.exit(a.problems.length ? 1 : 0);
  }
  process.exit(report(a));
}

// Only when run as a script, so analyse()/evaluate() can be imported.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
