#!/usr/bin/env node
/**
 * check-portable.mjs — does this artifact depend on the machine that built it?
 *
 * publish.yml already loads the bundled binary with DYLD_/LD_ variables
 * cleared, which proves it loads **there**. It cannot prove anything about a
 * consumer's machine: a load attempt on the build box succeeds by definition
 * whenever a stale absolute rpath still happens to resolve. This checks the
 * property a load attempt cannot — *every recorded search path is relative to
 * the artifact, and every dependency is either a system library or shipped
 * alongside* — by reading the load commands.
 *
 * This class of defect has already shipped from this repo once: a hardcoded
 * four-library list in bundle-runtime.sh missed libNVPTX.so, and
 * @napi-mojo/linux-x64 failed at require() for anyone without a Mojo install.
 * `npm test` could not see it, because it runs against the pre-bundle build
 * with the pixi environment still on the library search path.
 *
 * PARSED HERE, NOT SHELLED OUT to otool/readelf. Ported from the sibling
 * mojo-http's scripts/binfmt.py + ffi_portability_check.py, whose own history
 * is the argument: its shell-out version was wrong in the DANGEROUS
 * direction. `otool` exists only on macOS, so a Linux job could not inspect a
 * macOS artifact at all; and `llvm-objdump` does exist on macOS but prints
 * ELF dynamic entries in another format, so the regexes matched nothing, the
 * function returned empty lists, and a Linux artifact was reported portable.
 * A guard that answers "fine" when it cannot read the file is worse than no
 * guard. Reading the bytes means either platform can inspect either format.
 *
 * THREE STATES, because "portable" is not one bit of information:
 *
 *   broken          only loads on the machine that built it          exit 1
 *   satisfiable     loads once the named files are placed beside it  exit 0
 *   self-contained  loads with nothing else present                  exit 0
 *
 * The distinction is what makes it gateable: a build can be fixed to
 * `satisfiable` unilaterally, while `self-contained` means redistributing the
 * Mojo runtime. Pass --require-self-contained where that has been settled.
 *
 * Usage:
 *   node scripts/check-portable.mjs <artifact>
 *   node scripts/check-portable.mjs --require-self-contained build/index.node
 *   node scripts/check-portable.mjs --manifest build/bundled-libs.txt build/index.node
 *   node scripts/check-portable.mjs --self-test
 */

import { readFileSync, existsSync, statSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, basename, join, resolve, normalize } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

// What each format's loader expands relative to the ARTIFACT ITSELF. Not
// @executable_path: for an addon that is the directory of `node`, not of the
// .node file, so it travels with nothing we ship.
const SELF_RELATIVE = { macho: ['@loader_path'], elf: ['$ORIGIN', '${ORIGIN}'] };
const SYSTEM_PREFIXES = ['/usr/lib/', '/System/Library/', '/lib/', '/lib64/', '/usr/lib64/'];

// ELF names its dependencies by bare soname, so the absolute-prefix rule
// never matches one. Without this list a Linux artifact is "broken" for
// needing libc, which is not a finding.
const SYSTEM_SONAMES = [
  'libc.', 'libm.', 'libdl.', 'libpthread.', 'librt.', 'libutil.',
  'libgcc_s.', 'libstdc++.', 'ld-linux', 'libresolv.', 'libnsl.',
  'libcrypt.', 'libatomic.', 'libanl.', 'libthread_db.',
];

class InspectError extends Error {}

// --- Mach-O ----------------------------------------------------------------

const MACHO_LE = [0xfeedface, 0xfeedfacf]; // magic as read little-endian
const MACHO_BE = [0xcefaedfe, 0xcffaedfe];
const FAT = [0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca];

const LC_ID_DYLIB = 0x0d;
const LC_LOAD_DYLIB = 0x0c;
const LC_LOAD_WEAK_DYLIB = 0x80000018;
const LC_REEXPORT_DYLIB = 0x8000001f;
const LC_RPATH = 0x8000001c;
const LC_BUILD_VERSION = 0x32;
const LC_VERSION_MIN_MACOSX = 0x24;
const LC_LOAD_UPWARD_DYLIB = 0x80000023;
const LC_LAZY_LOAD_DYLIB = 0x20;
const DYLIB_LOADS = [
  LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB, LC_LOAD_UPWARD_DYLIB, LC_LAZY_LOAD_DYLIB,
];

function decodeVersion(packed) {
  const major = packed >>> 16;
  const minor = (packed >>> 8) & 0xff;
  const patch = packed & 0xff;
  return patch ? `${major}.${minor}.${patch}` : `${major}.${minor}`;
}

export function parseMachO(data) {
  const first = data.readUInt32LE(0);
  if (FAT.includes(first)) {
    throw new InspectError('fat Mach-O archive; inspect a single-architecture slice (lipo -thin)');
  }
  let le;
  if (MACHO_LE.includes(first)) le = true;
  else if (MACHO_BE.includes(first)) le = false;
  else throw new InspectError('not a Mach-O file');

  const u32 = (off) => (le ? data.readUInt32LE(off) : data.readUInt32BE(off));
  // MH_MAGIC_64 is 0xfeedfacf whichever way the file is written.
  const is64 = first === 0xfeedfacf || first === 0xcffaedfe;
  const ncmds = u32(16);
  let off = is64 ? 32 : 28;

  const rpaths = [];
  const deps = [];
  let installName = null;
  let minOS = null;

  // A load command's inline string is an offset from the command's own start.
  const lcStr = (cmdOff, cmdsize, strOff) => {
    if (!(strOff > 0 && strOff < cmdsize)) {
      throw new InspectError(`load command string offset ${strOff} outside the command`);
    }
    const start = cmdOff + strOff;
    const limit = cmdOff + cmdsize;
    let stop = data.indexOf(0, start);
    if (stop === -1 || stop > limit) stop = limit;
    return data.subarray(start, stop).toString('utf8');
  };

  for (let i = 0; i < ncmds; i++) {
    if (off + 8 > data.length) throw new InspectError('load commands run past end of file');
    const cmd = u32(off);
    const cmdsize = u32(off + 4);
    if (cmdsize < 8 || off + cmdsize > data.length) {
      throw new InspectError(`load command 0x${cmd.toString(16)} has implausible size ${cmdsize}`);
    }
    if (cmd === LC_RPATH) {
      rpaths.push(lcStr(off, cmdsize, u32(off + 8)));
    } else if (cmd === LC_ID_DYLIB) {
      installName = lcStr(off, cmdsize, u32(off + 8));
    } else if (DYLIB_LOADS.includes(cmd)) {
      deps.push(lcStr(off, cmdsize, u32(off + 8)));
    } else if (cmd === LC_BUILD_VERSION) {
      minOS = decodeVersion(u32(off + 12));
    } else if (cmd === LC_VERSION_MIN_MACOSX && minOS === null) {
      minOS = decodeVersion(u32(off + 8));
    }
    off += cmdsize;
  }
  return { search: rpaths, deps, ownName: installName, minOS };
}

// --- ELF -------------------------------------------------------------------

export function parseElf(data) {
  if (data.length < 64 || data.readUInt32BE(0) !== 0x7f454c46) {
    throw new InspectError('not an ELF file');
  }
  if (data[4] !== 2) throw new InspectError('not a 64-bit ELF');
  const le = data[5] === 1;
  const u16 = (o) => (le ? data.readUInt16LE(o) : data.readUInt16BE(o));
  const u64 = (o) => Number(le ? data.readBigUInt64LE(o) : data.readBigUInt64BE(o));
  const i64 = (o) => Number(le ? data.readBigInt64LE(o) : data.readBigInt64BE(o));
  const u32 = (o) => (le ? data.readUInt32LE(o) : data.readUInt32BE(o));

  const phoff = u64(0x20);
  const phentsize = u16(0x36);
  const phnum = u16(0x38);

  // PT_DYNAMIC (2) holds the entries; PT_LOAD (1) segments translate the
  // string table's virtual address into a file offset.
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
  if (dyn === null) throw new InspectError('no PT_DYNAMIC segment');

  const vaddrToOff = (v) => {
    for (const [pVaddr, pFilesz, pOffset] of loads) {
      if (pVaddr <= v && v < pVaddr + pFilesz) return pOffset + (v - pVaddr);
    }
    throw new InspectError(`address 0x${v.toString(16)} is in no PT_LOAD segment`);
  };

  const DT_NEEDED = 1, DT_STRTAB = 5, DT_SONAME = 14, DT_RPATH = 15, DT_RUNPATH = 29;
  const [dynOff, dynSize] = dyn;
  const entries = [];
  let strtabV = null;
  for (let off = dynOff; off + 16 <= dynOff + dynSize && off + 16 <= data.length; off += 16) {
    const tag = i64(off);
    const val = u64(off + 8);
    if (tag === 0) break;
    if (tag === DT_STRTAB) strtabV = val;
    entries.push([tag, val]);
  }
  if (strtabV === null) throw new InspectError('dynamic section has no DT_STRTAB');
  const strtab = vaddrToOff(strtabV);

  const sAt = (idx) => {
    const start = strtab + idx;
    const stop = data.indexOf(0, start);
    return data.subarray(start, stop === -1 ? data.length : stop).toString('utf8');
  };

  const search = [];
  const deps = [];
  let soname = null;
  for (const [tag, val] of entries) {
    if (tag === DT_NEEDED) deps.push(sAt(val));
    else if (tag === DT_SONAME) soname = sAt(val);
    else if (tag === DT_RPATH || tag === DT_RUNPATH) {
      for (const q of sAt(val).split(':')) if (q) search.push(q);
    }
  }
  return { search, deps, ownName: soname, minOS: null };
}

export function inspect(path) {
  const data = readFileSync(path);
  if (data.length < 4) throw new InspectError('file is too short to identify');
  const first = data.readUInt32LE(0);
  if (FAT.includes(first)) {
    throw new InspectError('fat Mach-O archive; inspect a single-architecture slice (lipo -thin)');
  }
  if (MACHO_LE.includes(first) || MACHO_BE.includes(first)) {
    return { format: 'macho', ...parseMachO(data) };
  }
  if (data.readUInt32BE(0) === 0x7f454c46) return { format: 'elf', ...parseElf(data) };
  throw new InspectError('neither Mach-O nor ELF');
}

// --- verdict ---------------------------------------------------------------

const startsWithAny = (s, prefixes) => prefixes.some((p) => s.startsWith(p));

export function verdict(path, info) {
  const { format, search, deps, ownName } = info;
  const selfRelative = SELF_RELATIVE[format];
  const isSelfRelative = (p) => startsWithAny(p, selfRelative);
  const selfRelativeSearch = search.filter(isSelfRelative);
  const foreignSearch = search.filter((p) => !isSelfRelative(p));
  const here = dirname(resolve(path));

  // '@loader_path/../lib' -> <artifact dir>/../lib. A self-relative path may
  // point at a sibling directory, and a layout that relies on that is
  // complete, not merely satisfiable.
  const expand = (p) => {
    const prefix = selfRelative.find((s) => p.startsWith(s));
    return normalize(join(here, p.slice(prefix.length).replace(/^\/+/, '')));
  };

  // Model where the loader LOOKS, then whether the file is there. Every
  // shortcut in this loop has already been a false pass: a dependency that
  // exists beside the artifact proves nothing if no path sends the loader to
  // it, and a self-relative dependency proves nothing if it is not there.
  const unresolved = [];
  const missingBeside = [];
  for (const d of deps) {
    if (startsWithAny(d, SYSTEM_PREFIXES)) continue;
    if (format === 'elf' && !d.includes('/') && startsWithAny(d, SYSTEM_SONAMES)) continue;

    // A direct self-relative path: the loader tries exactly there.
    if (isSelfRelative(d)) {
      if (!existsSync(expand(d))) missingBeside.push(d);
      continue;
    }

    // Looked up through the search paths: @rpath/ on Mach-O, a bare soname on
    // ELF. Only self-relative entries travel with the artifact; with none,
    // the dependency resolves on the build machine or not at all — even if a
    // copy happens to sit beside the artifact, because nothing says look there.
    const searched = format === 'macho' ? d.startsWith('@rpath/') : !d.includes('/');
    if (searched && selfRelativeSearch.length) {
      const name = format === 'macho' ? d.slice('@rpath/'.length) : d;
      if (!selfRelativeSearch.some((sp) => existsSync(join(expand(sp), name)))) {
        missingBeside.push(d);
      }
      continue;
    }

    // Everything else only resolves somewhere that is not the artifact: an
    // absolute non-system path, @executable_path (node's directory), or a
    // relative path the loader resolves against the working directory.
    unresolved.push(d);
  }

  // dlopen ignores the install name, so it cannot break loading — but it is
  // recorded into anything that LINKS against this library, which then
  // inherits the same defect. @executable_path is acceptable HERE: it is
  // resolved against whatever executable links the library, which is that
  // linker's decision to make.
  const badOwnName = Boolean(
    ownName &&
      !(startsWithAny(ownName, ['@loader_path', '@executable_path', '$ORIGIN']) ||
        ownName.startsWith('@rpath/') ||
        startsWithAny(ownName, SYSTEM_PREFIXES) ||
        !ownName.includes('/'))
  );

  const state = unresolved.length || badOwnName
    ? 'broken'
    : missingBeside.length
      ? 'satisfiable'
      : 'self-contained';
  return { state, unresolved, missingBeside, foreignSearch, selfRelativeSearch, badOwnName };
}

function whyUnresolved(format, d, foreignSearch) {
  if (d.startsWith('@executable_path')) {
    return "resolves against the host executable's directory (node's), not this artifact's";
  }
  if (d.startsWith('/')) return 'is an absolute path outside the system library directories';
  const searched = format === 'macho' ? d.startsWith('@rpath/') : !d.includes('/');
  if (searched) {
    return (
      `is looked up only through ${foreignSearch.length ? JSON.stringify(foreignSearch) : '(no search path)'} ` +
      '— nothing tells the loader to look beside this artifact'
    );
  }
  return "is a relative path, which the loader resolves against the process's working directory";
}

/**
 * The bundled libraries a manifest names, split into those present beside
 * the artifact and those that are not. A missing one is a finding, not a
 * skip: the manifest is the bundler's record of what must ship, and checking
 * only the files that happen to exist reports a consumer layout as complete
 * when it is not.
 */
export function manifestTargets(artifact, manifestText) {
  const targets = [];
  const missing = [];
  for (const line of manifestText.split('\n')) {
    const name = line.trim();
    if (!name) continue;
    const p = join(dirname(artifact), basename(name));
    (existsSync(p) && statSync(p).isFile() ? targets : missing).push(p);
  }
  return { targets, missing };
}

function report(path, requireSelfContained) {
  let info;
  try {
    info = inspect(path);
  } catch (e) {
    console.error(`check-portable: ${path}: ${e.message}`);
    return 2;
  }
  const v = verdict(path, info);

  console.log(`artifact      : ${path}`);
  console.log(
    `install name  : ${
      info.ownName === null
        ? info.format === 'macho'
          ? '(not a dylib — no LC_ID_DYLIB)'
          : '(no DT_SONAME)'
        : info.ownName
    }`
  );
  console.log(`search paths  : ${info.search.length ? JSON.stringify(info.search) : '(none)'}`);
  console.log(`dependencies  : ${info.deps.length ? JSON.stringify(info.deps) : '(none)'}`);
  if (info.minOS) console.log(`min OS        : ${info.minOS}`);

  if (v.state === 'broken') {
    console.log('');
    console.log('BROKEN — this artifact only works on the machine that built it:');
    for (const d of v.unresolved) {
      console.log(`  - dependency ${JSON.stringify(d)} ${whyUnresolved(info.format, d, v.foreignSearch)}`);
    }
    if (v.badOwnName) {
      console.log(
        `  - install name is a build-tree path: ${JSON.stringify(info.ownName)} — dlopen ignores` +
          ' it, but anything that LINKS against this library records it and then cannot find it'
      );
    }
    if (v.foreignSearch.length && !v.unresolved.length) {
      for (const p of v.foreignSearch) console.log(`  - build-machine search path recorded: ${JSON.stringify(p)}`);
    }
    console.log('');
    console.log('Anyone who installs this from npm without a Mojo toolchain cannot load it.');
    return 1;
  }

  if (v.state === 'satisfiable') {
    console.log('');
    console.log('SATISFIABLE — loads once these are placed where it looks:');
    for (const d of v.missingBeside) console.log(`  - ${d}`);
    if (v.selfRelativeSearch.length) {
      console.log(`  (search path is ${JSON.stringify(v.selfRelativeSearch)}, so the consumer can supply them)`);
    }
    if (requireSelfContained) {
      console.log('');
      console.log('--require-self-contained was given: this is not self-contained.');
      return 1;
    }
    return 0;
  }

  console.log('');
  if (v.foreignSearch.length) {
    // Nothing needs it, so it cannot cause a load failure here — but the
    // loader still searches it, in recorded order (on ELF, before any $ORIGIN
    // entry listed after it), so a library at that path on a consumer's
    // machine could shadow a bundled one. It also leaks the build directory.
    console.log('SELF-CONTAINED — every dependency resolves beside the artifact or from the system.');
    console.log(`  note: a build-machine search path is also recorded: ${JSON.stringify(v.foreignSearch)}`);
    return 0;
  }
  console.log(
    'SELF-CONTAINED — every search path is self-relative and every dependency is a system' +
      ' library or shipped alongside.'
  );
  return 0;
}

// --- self-test -------------------------------------------------------------
//
// Guards the guard. The parser is only meaningful if it still tells an
// executable from a dylib, and that difference is invisible to any test that
// only ever looks at one of them — it is exactly the bug mojo-http's version
// was extracted for, where otool -L's first line was assumed to be the file's
// own install name. Fixtures are SYNTHESISED rather than checked in so both
// formats are tested on both CI platforms; a macOS-only fixture would leave
// the Linux runner testing nothing.

function lcDylib(cmd, name) {
  const raw = Buffer.concat([Buffer.from(name, 'utf8'), Buffer.from([0])]);
  const pad = (-(24 + raw.length) % 8 + 8) % 8;
  const size = 24 + raw.length + pad;
  const head = Buffer.alloc(24);
  head.writeUInt32LE(cmd >>> 0, 0);
  head.writeUInt32LE(size, 4);
  head.writeUInt32LE(24, 8);
  return Buffer.concat([head, raw, Buffer.alloc(pad)]);
}

function lcRpath(path) {
  const raw = Buffer.concat([Buffer.from(path, 'utf8'), Buffer.from([0])]);
  const pad = (-(12 + raw.length) % 8 + 8) % 8;
  const size = 12 + raw.length + pad;
  const head = Buffer.alloc(12);
  head.writeUInt32LE(LC_RPATH >>> 0, 0);
  head.writeUInt32LE(size, 4);
  head.writeUInt32LE(12, 8);
  return Buffer.concat([head, raw, Buffer.alloc(pad)]);
}

function machO(filetype, commands) {
  const body = Buffer.concat(commands);
  const header = Buffer.alloc(32);
  header.writeUInt32LE(0xfeedfacf, 0); // MH_MAGIC_64
  header.writeInt32LE(0x0100000c, 4); // CPU_TYPE_ARM64
  header.writeInt32LE(0, 8);
  header.writeUInt32LE(filetype, 12);
  header.writeUInt32LE(commands.length, 16);
  header.writeUInt32LE(body.length, 20);
  header.writeUInt32LE(0, 24);
  header.writeUInt32LE(0, 28);
  return Buffer.concat([header, body]);
}

function selfTest() {
  const cases = [];
  const check = (name, fn) => {
    try { fn(); cases.push([name, null]); }
    catch (e) { cases.push([name, e.message]); }
  };
  const eq = (a, b, what) => {
    const [x, y] = [JSON.stringify(a), JSON.stringify(b)];
    if (x !== y) throw new Error(`${what}: expected ${y}, got ${x}`);
  };

  // MH_DYLIB (6): the LC_ID_DYLIB is the file's own name, not a dependency.
  check('dylib: install name is not a dependency', () => {
    const buf = machO(6, [
      lcDylib(LC_ID_DYLIB, '@rpath/libthing.dylib'),
      lcDylib(LC_LOAD_DYLIB, '@rpath/libKGENCompilerRTShared.dylib'),
      lcRpath('@loader_path'),
    ]);
    const info = parseMachO(buf);
    eq(info.ownName, '@rpath/libthing.dylib', 'install name');
    eq(info.deps, ['@rpath/libKGENCompilerRTShared.dylib'], 'deps');
    eq(info.search, ['@loader_path'], 'rpaths');
  });

  // MH_EXECUTE (2): no LC_ID_DYLIB at all. The bug this guards against was
  // discarding the first dependency as if it were the install name.
  check('executable: no install name, dependency kept', () => {
    const buf = machO(2, [
      lcDylib(LC_LOAD_DYLIB, '@rpath/libKGENCompilerRTShared.dylib'),
      lcRpath('@executable_path/../lib'),
    ]);
    const info = parseMachO(buf);
    eq(info.ownName, null, 'install name');
    eq(info.deps, ['@rpath/libKGENCompilerRTShared.dylib'], 'deps');
  });

  check('weak and reexport dylib loads count as dependencies', () => {
    const info = parseMachO(machO(6, [
      lcDylib(LC_LOAD_WEAK_DYLIB, '/usr/lib/libSystem.B.dylib'),
      lcDylib(LC_REEXPORT_DYLIB, '@rpath/libre.dylib'),
    ]));
    eq(info.deps, ['/usr/lib/libSystem.B.dylib', '@rpath/libre.dylib'], 'deps');
  });

  check('a build-tree rpath is BROKEN', () => {
    const info = { format: 'macho', ownName: '@rpath/libm.dylib', search: ['/Users/runner/work/x/.pixi/lib'], deps: ['@rpath/libKGEN.dylib'], minOS: null };
    eq(verdict('/tmp/nonexistent/libm.dylib', info).state, 'broken', 'state');
  });

  check('a build-tree install name is BROKEN even with a good rpath', () => {
    const info = { format: 'macho', ownName: 'build/libm.dylib', search: ['@loader_path'], deps: [], minOS: null };
    eq(verdict('/tmp/nonexistent/libm.dylib', info).state, 'broken', 'state');
  });

  check('self-relative search with a missing neighbour is SATISFIABLE', () => {
    const info = { format: 'macho', ownName: '@rpath/libm.dylib', search: ['@loader_path'], deps: ['@rpath/libKGEN.dylib'], minOS: null };
    eq(verdict('/tmp/nonexistent/libm.dylib', info).state, 'satisfiable', 'state');
  });

  check('system libraries are not dependencies to satisfy', () => {
    const macho = { format: 'macho', ownName: null, search: [], deps: ['/usr/lib/libSystem.B.dylib'], minOS: null };
    eq(verdict('/tmp/nonexistent/x', macho).state, 'self-contained', 'macho state');
    const elf = { format: 'elf', ownName: null, search: [], deps: ['libc.so.6', 'libstdc++.so.6'], minOS: null };
    eq(verdict('/tmp/nonexistent/x', elf).state, 'self-contained', 'elf state');
  });

  // The ELF fixture is this very Node binary: a real, large, dynamically
  // linked ELF on any Linux runner. Synthesising one is not worth it when a
  // genuine article is on PATH; on macOS this case is skipped, and the Mach-O
  // cases above carry the load instead.
  check('elf: parses a real binary (skipped off Linux)', () => {
    if (process.platform !== 'linux') return;
    const info = inspect(process.execPath);
    if (info.format !== 'elf') throw new Error(`expected elf, got ${info.format}`);
    if (!info.deps.length) throw new Error('expected DT_NEEDED entries');
    if (!info.deps.some((d) => d.startsWith('libc.'))) {
      throw new Error(`expected a libc dependency, got ${JSON.stringify(info.deps)}`);
    }
  });

  check('upward and lazy dylib loads count as dependencies', () => {
    const info = parseMachO(machO(6, [
      lcDylib(LC_LOAD_UPWARD_DYLIB, '@rpath/libup.dylib'),
      lcDylib(LC_LAZY_LOAD_DYLIB, '@rpath/liblazy.dylib'),
    ]));
    eq(info.deps, ['@rpath/libup.dylib', '@rpath/liblazy.dylib'], 'deps');
  });

  // The cases below need real neighbours on disk, because the verdict's whole
  // job is to model where the loader looks — and the defects they pin were all
  // "a library happened to sit beside the artifact, so a path the loader never
  // consults was reported as resolving". A fixture directory that is empty
  // hides exactly that; each case here puts the library IN it.
  const dir = mkdtempSync(join(tmpdir(), 'check-portable-'));
  const touch = (name) => { writeFileSync(join(dir, name), ''); return join(dir, name); };
  const artifact = join(dir, 'index.node');
  touch('index.node');
  touch('libKGEN.dylib');
  touch('libKGEN.so');
  const state = (info) => verdict(artifact, { minOS: null, ownName: null, ...info }).state;

  try {
    check('positive controls: self-relative search finds the neighbour', () => {
      eq(state({ format: 'macho', search: ['@loader_path'], deps: ['@rpath/libKGEN.dylib'] }), 'self-contained', 'macho @rpath');
      eq(state({ format: 'macho', search: [], deps: ['@loader_path/libKGEN.dylib'] }), 'self-contained', 'macho @loader_path dep');
      eq(state({ format: 'elf', search: ['$ORIGIN'], deps: ['libKGEN.so'] }), 'self-contained', 'elf $ORIGIN');
      eq(state({ format: 'elf', search: ['${ORIGIN}'], deps: ['libKGEN.so'] }), 'self-contained', 'elf ${ORIGIN}');
    });

    // bundle-runtime.sh rewrites every macOS dependency to this form, so an
    // unchecked one meant index.node copied alone reported SELF-CONTAINED.
    check('a direct @loader_path dependency that is absent is not self-contained', () => {
      eq(state({ format: 'macho', search: [], deps: ['@loader_path/libAbsent.dylib'] }), 'satisfiable', 'state');
      eq(state({ format: 'elf', search: [], deps: ['$ORIGIN/libAbsent.so'] }), 'satisfiable', 'elf state');
    });

    // Neither dyld nor ld.so looks beside the artifact unless a search path
    // says to. These all load on the build box and nowhere else.
    check('a neighbour the loader never consults does not count', () => {
      eq(state({ format: 'elf', search: ['/home/runner/work/x/.pixi/envs/default/lib'], deps: ['libKGEN.so'] }), 'broken', 'elf build-tree RUNPATH');
      eq(state({ format: 'elf', search: [], deps: ['libKGEN.so'] }), 'broken', 'elf no RUNPATH');
      eq(state({ format: 'macho', search: ['/Users/runner/work/x/.pixi/lib'], deps: ['@rpath/libKGEN.dylib'] }), 'broken', 'macho build-tree LC_RPATH');
      eq(state({ format: 'macho', search: [], deps: ['@rpath/libKGEN.dylib'] }), 'broken', 'macho no LC_RPATH');
      eq(state({ format: 'macho', search: [], deps: ['libKGEN.dylib'] }), 'broken', 'macho bare relative (cwd)');
    });

    // For a .node file @executable_path is node's own directory.
    check('@executable_path is the host executable, not the artifact', () => {
      eq(state({ format: 'macho', search: ['@executable_path'], deps: ['@rpath/libKGEN.dylib'] }), 'broken', 'rpath');
      eq(state({ format: 'macho', search: [], deps: ['@executable_path/libKGEN.dylib'] }), 'broken', 'dep');
    });

    check('a manifest entry that is not beside the artifact is reported', () => {
      const { targets, missing } = manifestTargets(artifact, 'libKGEN.so\nlibAbsent.so\n\n');
      eq(targets, [join(dir, 'libKGEN.so')], 'targets');
      eq(missing, [join(dir, 'libAbsent.so')], 'missing');
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  check('a fat archive is an inspect error, not a pass', () => {
    const fat = Buffer.alloc(32);
    fat.writeUInt32BE(0xcafebabe, 0);
    let threw = false;
    try { parseMachO(fat); } catch { threw = true; }
    if (!threw) throw new Error('expected InspectError for a fat archive');
  });

  const failed = cases.filter(([, err]) => err);
  for (const [name, err] of cases) console.log(`${err ? 'FAIL' : ' ok '}  ${name}${err ? ` — ${err}` : ''}`);
  console.log(`\ncheck-portable --self-test: ${cases.length - failed.length}/${cases.length} passed`);
  return failed.length ? 1 : 0;
}

// --- main ------------------------------------------------------------------

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--self-test')) process.exit(selfTest());

  const requireSelfContained = argv.includes('--require-self-contained');
  const manifestIdx = argv.indexOf('--manifest');
  const manifest = manifestIdx !== -1 ? argv[manifestIdx + 1] : null;
  // manifestIdx is -1 when the flag is absent, so guard the "skip the flag's
  // value" index explicitly — `i !== manifestIdx + 1` would otherwise drop
  // argv[0], which is the artifact in the common one-argument form.
  const valueIdx = manifestIdx === -1 ? -1 : manifestIdx + 1;
  const positional = argv.filter((a, i) => !a.startsWith('--') && i !== valueIdx);

  if (positional.length !== 1) {
    console.error(
      'usage: check-portable.mjs [--require-self-contained] [--manifest <file>] <artifact>\n' +
      '       check-portable.mjs --self-test'
    );
    process.exit(2);
  }

  const artifact = positional[0];
  if (!existsSync(artifact)) {
    console.error(`check-portable: ${artifact} does not exist`);
    process.exit(2);
  }

  const targets = [artifact];
  let worst = 0;
  if (manifest) {
    if (!existsSync(manifest)) {
      console.error(`check-portable: manifest ${manifest} does not exist`);
      process.exit(2);
    }
    // Every bundled library is checked too: one of them carrying a build-tree
    // rpath breaks the consumer exactly as surely as the addon doing so, and
    // the addon's own load commands say nothing about it.
    const listed = manifestTargets(artifact, readFileSync(manifest, 'utf8'));
    targets.push(...listed.targets);
    for (const p of listed.missing) {
      console.log(`MISSING — ${manifest} lists ${JSON.stringify(basename(p))}, which is not beside the artifact at ${p}`);
      console.log('');
      worst = 1;
    }
  }

  for (const t of targets) {
    const rc = report(t, requireSelfContained);
    worst = Math.max(worst, rc);
    console.log('');
  }
  if (worst === 0) console.log(`check-portable: ${targets.length} artifact(s) OK`);
  process.exit(worst);
}

// Only when run as a script, so the exported parsers and verdict can be
// imported without the import calling process.exit.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
