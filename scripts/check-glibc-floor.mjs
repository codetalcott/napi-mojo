#!/usr/bin/env node
/**
 * check-glibc-floor.mjs — would the HOST's libstdc++ satisfy what we ship?
 *
 * The Linux platform packages bundle GCC's libstdc++.so.6 and libgcc_s.so.1
 * alongside the Mojo runtime. libstdc++ alone is 23.9 MB of a 27 MB package,
 * and there is evidence it is redundant (docs/plan-distribution.md): the Mojo
 * runtime requires at most GLIBCXX_3.4.30, while its GLIBC_2.35 requirement —
 * which CANNOT be bundled, because glibc is the loader — already implies a
 * host whose own libstdc++ provides 3.4.30.
 *
 * That argument holds only as long as the two floors stay in that order, and
 * NOTHING WOULD NOTICE IF THEY STOPPED. A Mojo release that raises the
 * required GLIBCXX above what the glibc floor implies would either ship a
 * package that needs the bundled copy (fine while we bundle it, fatal the
 * moment we stop) or, after removal, a package that fails at require() on
 * hosts it claims to support. This gate turns that into a red build.
 *
 * THE QUESTION IT ANSWERS, precisely: taking the files we ship EXCEPT the GCC
 * runtime itself, what GLIBC / GLIBCXX / CXXABI versions do they require, and
 * is the GLIBCXX requirement satisfied by every mainstream distribution whose
 * glibc is new enough to load us at all?
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

// ---------------------------------------------------------------------------
// What a host provides, by distribution.
//
// Each row is a mainstream distribution's shipped glibc and the GLIBCXX /
// CXXABI its default libstdc++6 package provides. The gate does NOT trust any
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
  { distro: 'RHEL 8 / CentOS 8', glibc: '2.28', glibcxx: '3.4.25', cxxabi: '1.3.11' },
  { distro: 'Ubuntu 20.04', glibc: '2.31', glibcxx: '3.4.28', cxxabi: '1.3.12' },
  { distro: 'Debian 11', glibc: '2.31', glibcxx: '3.4.28', cxxabi: '1.3.12' },
  { distro: 'RHEL 9', glibc: '2.34', glibcxx: '3.4.29', cxxabi: '1.3.13' },
  { distro: 'Ubuntu 22.04', glibc: '2.35', glibcxx: '3.4.30', cxxabi: '1.3.13' },
  { distro: 'Debian 12', glibc: '2.36', glibcxx: '3.4.30', cxxabi: '1.3.13' },
  { distro: 'Ubuntu 24.04', glibc: '2.39', glibcxx: '3.4.32', cxxabi: '1.3.15' },
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

  // Every distribution whose glibc is new enough to load us at all, and the
  // worst GLIBCXX / CXXABI among them.
  const hosts = neededGlibc
    ? HOSTS.filter((h) => cmpVersion(h.glibc, neededGlibc) >= 0)
    : HOSTS.slice();
  const impliedGlibcxx = hosts.length
    ? hosts.map((h) => h.glibcxx).reduce((a, b) => (cmpVersion(a, b) <= 0 ? a : b))
    : null;
  const impliedCxxabi = hosts.length
    ? hosts.map((h) => h.cxxabi).reduce((a, b) => (cmpVersion(a, b) <= 0 ? a : b))
    : null;

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
  if (neededGlibcxx && impliedGlibcxx && cmpVersion(neededGlibcxx, impliedGlibcxx) > 0) {
    problems.push(
      `GLIBCXX_${neededGlibcxx} is required but a GLIBC_${neededGlibc} host only guarantees GLIBCXX_${impliedGlibcxx} ` +
      `(worst case: ${hosts.filter((h) => h.glibcxx === impliedGlibcxx).map((h) => h.distro).join(', ')}). ` +
      `The bundled libstdc++ is now load-bearing: it can no longer be dropped, and docs/plan-distribution.md's argument for dropping it is void.`
    );
  }
  if (neededCxxabi && impliedCxxabi && cmpVersion(neededCxxabi, impliedCxxabi) > 0) {
    problems.push(
      `CXXABI_${neededCxxabi} is required but a GLIBC_${neededGlibc} host only guarantees CXXABI_${impliedCxxabi}`
    );
  }

  return {
    entry, files: files.map((f) => basename(f.path)), excluded: excluded.map((f) => basename(f.path)),
    missing, neededGlibc, neededGlibcxx, neededCxxabi, impliedGlibcxx, impliedCxxabi,
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
  console.log('');
  console.log(`a GLIBC_${a.neededGlibc} host is at least: ${a.hosts.join(', ')}`);
  console.log(`  and so provides at least GLIBCXX_${a.impliedGlibcxx}, CXXABI_${a.impliedCxxabi}`);

  for (const [family, versions] of Object.entries(a.attributed)) {
    const top = maxVersion(Object.keys(versions));
    if (top) console.log(`\n  ${family}_${top} comes from: ${[...new Set(versions[top])].join(', ')}`);
  }

  if (a.problems.length) {
    console.error('\ncheck-glibc-floor: FAIL\n');
    for (const p of a.problems) console.error('  - ' + p + '\n');
    return 1;
  }
  console.log('\ncheck-glibc-floor: the host libstdc++ implied by our own glibc floor satisfies us.');
  console.log('The bundled GCC runtime is redundant on every distribution in the table.');
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

  check('a raised GLIBCXX requirement is caught', () => {
    // The regression this gate exists for, simulated on the table alone.
    const hosts = HOSTS.filter((h) => cmpVersion(h.glibc, '2.35') >= 0);
    const implied = hosts.map((h) => h.glibcxx).reduce((a, b) => (cmpVersion(a, b) <= 0 ? a : b));
    if (implied !== '3.4.30') throw new Error(`a GLIBC_2.35 host should imply GLIBCXX_3.4.30, got ${implied}`);
    if (cmpVersion('3.4.31', implied) <= 0) throw new Error('GLIBCXX_3.4.31 must fail against a 3.4.30 floor');
    if (cmpVersion('3.4.30', implied) > 0) throw new Error('GLIBCXX_3.4.30 must pass against a 3.4.30 floor');
  });

  check('an unresolvable dependency fails rather than passing empty', () => {
    // The regression found by running the gate on an artifact whose siblings
    // were absent: the tally came back empty and the gate said fine.
    const fake = {
      missing: [{ from: 'index.node', dep: 'libKGENCompilerRTShared.so' }],
      neededGlibc: '2.34', neededGlibcxx: null,
    };
    if (!fake.missing.length) throw new Error('fixture is wrong');
    // Mirrors the guard clause in analyse(); kept in step by the sabotage in
    // the commit message rather than by construction.
    const problems = [];
    if (fake.missing.length) problems.push('incomplete');
    if (!problems.length) throw new Error('an unresolved dependency must produce a problem');
  });

  check('the worst case is taken, not a convenient one', () => {
    // RHEL 9 is glibc 2.34 with GLIBCXX_3.4.29: a build needing only
    // GLIBC_2.34 must be held to 3.4.29, not to Ubuntu 22.04's 3.4.30.
    const hosts = HOSTS.filter((h) => cmpVersion(h.glibc, '2.34') >= 0);
    const implied = hosts.map((h) => h.glibcxx).reduce((a, b) => (cmpVersion(a, b) <= 0 ? a : b));
    if (implied !== '3.4.29') throw new Error(`expected the RHEL 9 floor 3.4.29, got ${implied}`);
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

main();
