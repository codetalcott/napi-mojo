#!/usr/bin/env node
// scripts/derive-population-b.mjs — re-derive population B from source.
//
// Population B is the set of sites that pass a pointer-to-a-LOCAL into an
// N-API call through an `AnyOrigin` FFI signature. Those sites are correct
// today only because `AnyOrigin` silently extends the local's lifetime; the
// migration in docs/handoff-argv-origin-migration.md removes that dependency.
//
// docs/handoff-argv-origin-migration.md says, correctly, not to trust a number
// written in a document — including its own. This script is why: it derives
// the population and the at-risk subset fresh, so the answer is re-runnable
// rather than transcribed.
//
// WHY A SCRIPT AND NOT A GREP. Most sites are line-wrapped:
//
//     var recv_ptr: OpaquePointer[MutAnyOrigin] = Pointer(
//         to=recv
//     ).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
//
// so a same-line grep finds roughly 60% of them. This joins logical
// statements by bracket depth before matching.
//
// THE TWO FALSE-POSITIVE CLASSES it filters out, both from the handoff doc:
//
//   - Function-pointer reinterprets — `Pointer(to=x).unsafe_bitcast[F]()[]`.
//     The trailing `[]` dereferences immediately, before any call, so no
//     lifetime spans the FFI boundary. raw.mojo's slot casts are all this.
//   - Non-NoneType bitcasts generally: only `.unsafe_bitcast[NoneType]()`
//     forms the `void*` an N-API signature takes.
//
// Usage:
//   node scripts/derive-population-b.mjs           # summary + at-risk detail
//   node scripts/derive-population-b.mjs --all     # every site, classified
//   node scripts/derive-population-b.mjs --json
//   node scripts/derive-population-b.mjs --check   # exit 1 if any at-risk

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const ROOT = new URL('..', import.meta.url).pathname
const SCAN_DIRS = ['src', 'spike', 'examples']

const args = process.argv.slice(2)
const SHOW_ALL = args.includes('--all')
const AS_JSON = args.includes('--json')
// --check exits non-zero when any at-risk site exists, so this can be wired
// into CI the way check-keepalive-barrier.mjs and check-compile-coverage.mjs
// are. It is NOT a required check today: the post-use classification is a
// heuristic (does the identifier appear again in the def?), so it can only
// ever be a smoke alarm. `--emit llvm` and Guard Malloc remain the authorities.
const CHECK = args.includes('--check')

function mojoFiles(dir) {
  const out = []
  const walk = (d) => {
    let entries
    try {
      entries = readdirSync(d)
    } catch {
      return
    }
    for (const e of entries) {
      const p = join(d, e)
      if (statSync(p).isDirectory()) walk(p)
      else if (e.endsWith('.mojo')) out.push(p)
    }
  }
  walk(join(ROOT, dir))
  return out
}

// Blank out everything that is not code, PRESERVING line numbering: triple-
// quoted docstrings, single-quoted strings, and `#` comments. Skipping this
// desyncs the bracket counter — a docstring's `Args:` parens alone are enough
// to merge a dozen statements and misattribute every line number after them.
function stripNonCode(src) {
  const lines = src.split('\n')
  const out = []
  let inDoc = false
  for (let raw of lines) {
    let line = raw
    if (inDoc) {
      const close = line.indexOf('"""')
      if (close === -1) {
        out.push('')
        continue
      }
      line = ' '.repeat(close + 3) + line.slice(close + 3)
      inDoc = false
    }
    // Opening docstring on this line (possibly closing on the same line).
    for (;;) {
      const open = line.indexOf('"""')
      if (open === -1) break
      const close = line.indexOf('"""', open + 3)
      if (close === -1) {
        line = line.slice(0, open)
        inDoc = true
        break
      }
      line = line.slice(0, open) + ' '.repeat(close + 3 - open) + line.slice(close + 3)
    }
    // Single-line string literals, then trailing comments.
    line = line.replace(/"(?:[^"\\]|\\.)*"/g, (s) => ' '.repeat(s.length))
    line = line.replace(/'(?:[^'\\]|\\.)*'/g, (s) => ' '.repeat(s.length))
    const hash = line.indexOf('#')
    if (hash !== -1) line = line.slice(0, hash)
    out.push(line)
  }
  return out
}

// Join physical lines into logical statements by bracket depth. Returns
// [{ text, startLine, endLine, indent }]. `codeLines` must already be
// stripped of strings and comments; `rawLines` supplies the reported text.
function logicalStatements(codeLines, rawLines) {
  const stmts = []
  let buf = null
  let depth = 0

  for (let i = 0; i < codeLines.length; i++) {
    const code = codeLines[i]
    if (buf === null) {
      if (code.trim() === '') continue
      buf = {
        text: rawLines[i].trim(),
        startLine: i + 1,
        endLine: i + 1,
        indent: rawLines[i].match(/^\s*/)[0].length,
      }
    } else {
      buf.text += ' ' + rawLines[i].trim()
      buf.endLine = i + 1
    }
    for (const ch of code) {
      if (ch === '(' || ch === '[' || ch === '{') depth++
      else if (ch === ')' || ch === ']' || ch === '}') depth--
    }
    if (depth <= 0) {
      depth = 0
      stmts.push(buf)
      buf = null
    }
  }
  if (buf !== null) stmts.push(buf)
  return stmts
}

// Map each line number to its enclosing `def` (nearest preceding def at a
// strictly smaller indent).
//
// `bodyStart` is computed by balancing the signature's parens rather than
// assumed to be the next line. A wrapped signature puts its closing
// `) raises -> X:` back at the DEF'S OWN indent:
//
//     def get_this(                      <- indent 4
//         b: Bindings, env: NapiEnv,     <- indent 8
//     ) raises -> NapiValue:             <- indent 4  !!
//
// so a body scan that starts at the line after `def` and stops at the first
// line with indent <= the def's own indent terminates immediately, reports an
// empty body, and misclassifies every site inside it as unpinned.
function defIndex(lines) {
  const defs = []
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\s*)def\s+(\w+)/)
    if (!m) continue
    let depth = 0
    let j = i
    for (; j < lines.length; j++) {
      for (const ch of lines[j]) {
        if (ch === '(' || ch === '[' || ch === '{') depth++
        else if (ch === ')' || ch === ']' || ch === '}') depth--
      }
      if (depth <= 0 && lines[j].trimEnd().endsWith(':')) break
    }
    defs.push({ line: i + 1, indent: m[1].length, name: m[2], bodyStart: j + 1 })
  }
  return (lineNo, indent) => {
    let best = null
    for (const d of defs) {
      if (d.line <= lineNo && d.indent < indent) best = d
    }
    return best
  }
}

// End of the def body, scanning from `bodyStart` for the first non-blank line
// at or outside the def's own indent.
function defBodyEnd(lines, bodyStart, indent) {
  for (let i = bodyStart; i < lines.length; i++) {
    const l = lines[i]
    if (l.trim() === '') continue
    if (l.match(/^\s*/)[0].length <= indent) return i
  }
  return lines.length
}


// The declared type of `target` within def `d`, looked up in the def's own
// SIGNATURE first and then its body. Returns { type, isParam } or null.
//
// This is deliberately scoped to one def. An earlier version scanned a +/-60
// line window instead, which let an unrelated neighbouring def's
// `name: StringLiteral` parameter mask `JsFunction.create_named`'s real
// `name: String` — excluding a genuine, already-pinned site as .rodata.
function declaredTypeOf(lines, d, target) {
  const esc = target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

  const sig = lines.slice(d.line - 1, d.bodyStart).join(' ')
  const mp = sig.match(
    new RegExp(`(?:^|[(,\\s])(mut\\s+|out\\s+|deinit\\s+|owned\\s+)?${esc}\\s*:\\s*([\\w.]+)`)
  )
  if (mp) return { type: mp[2], isParam: true, borrowed: !mp[1] }

  const bodyEnd = defBodyEnd(lines, d.bodyStart, d.indent)
  const body = lines.slice(d.bodyStart, bodyEnd).join('\n')
  const ma = body.match(new RegExp(`\\bvar\\s+${esc}\\s*:\\s*([\\w.]+)`))
  if (ma) return { type: ma[1], isParam: false, borrowed: false }
  const mc = body.match(new RegExp(`\\bvar\\s+${esc}\\s*=\\s*([\\w.]+)\\s*\\(`))
  if (mc) return { type: mc[1], isParam: false, borrowed: false }
  return null
}

const STATIC_STR = new Set(['StringLiteral', 'StaticString'])

// Types that are trivially register-passable. A BORROWED parameter of one of
// these is copied into the callee's frame, so `Pointer(to=param)` addresses
// the callee's own slot and that slot needs pinning like any other local.
//
// A borrowed parameter of any OTHER type is memory-passed: the pointer is to
// the CALLER's storage and the caller's borrow already spans the nested FFI
// call. docs/handoff-argv-origin-migration.md calls this the class that
// "reads dangerous but is not", and names its one instance —
// `define_property`'s `desc: NapiPropertyDescriptor`.
const REGISTER_PASSABLE = new Set([
  'NapiValue', 'NapiEnv', 'NapiRef', 'NapiDeferred', 'NapiAsyncWork',
  'NapiHandleScope', 'NapiEscapableHandleScope', 'NapiThreadsafeFunction',
  'NapiAsyncContext', 'NapiCallbackScope', 'NapiStatus', 'Bindings',
  'UInt', 'Int', 'Bool', 'Int8', 'Int16', 'Int32', 'Int64',
  'UInt8', 'UInt16', 'UInt32', 'UInt64', 'Float32', 'Float64',
])

// The declared type of `target` if it is a borrowed parameter of the def
// whose signature spans [defLine, bodyStart), else null.
function borrowedParamType(lines, defLine, bodyStart, target) {
  const esc = target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const sig = lines.slice(defLine - 1, bodyStart).join(' ')
  const m = sig.match(new RegExp(`(?:^|[(,\\s])(mut\\s+|out\\s+|deinit\\s+|owned\\s+)?${esc}\\s*:\\s*([\\w.]+)`))
  if (!m) return null
  if (m[1]) return null // mut/out/owned — not a plain borrow
  return m[2]
}

const findings = []

for (const dir of SCAN_DIRS) {
  for (const file of mojoFiles(dir)) {
    const src = readFileSync(file, 'utf8')
    const rawLines = src.split('\n')
    // All structural analysis runs on the stripped view so that a docstring
    // or a comment mentioning a variable cannot masquerade as code.
    const codeLines = stripNonCode(src)
    const rel = relative(ROOT, file)
    const enclosingDef = defIndex(codeLines)
    const fileTouchesFFI = /\braw_\w+\s*\(|\b_sym\s*\[|\bcheck_status\s*\(|\bfrom napi\b|\bimport napi\b/.test(
      codeLines.join('\n')
    )

    for (const stmt of logicalStatements(codeLines, rawLines)) {
      // Two formation shapes reach an AnyOrigin FFI parameter from a local:
      //
      //   ADDRESS-OF      Pointer(to=local)...          — output slots, argv,
      //                                                   in/out argc
      //   BUFFER-POINTER  local.unsafe_ptr()...         — a String's or
      //                                                   List's heap buffer,
      //                                                   whose OWNER is the
      //                                                   local being tracked
      //
      // Only the first was in this script's original matcher, which is why it
      // saw 11 of the tree's pin_across_ffi calls: js_function.mojo pins a
      // `name: String` whose buffer pointer is the second shape.
      // Regex, not `includes('Pointer(to=')`: joining a wrapped statement
      // inserts a space, so the overwhelmingly common
      //
      //     ... = Pointer(
      //         to=recv
      //     ).unsafe_bitcast[NoneType]()...
      //
      // joins to `Pointer( to=recv )` and a literal-substring test misses it —
      // silently reducing this script to the same-line grep it exists to
      // replace. JsFunction.call1/call2, the two sites at the top of the
      // handoff doc's regression table, were both invisible to that version.
      const hasAddrOf = /Pointer\(\s*to=/.test(stmt.text)
      const hasBufPtr = /\.unsafe_ptr\(\)/.test(stmt.text)
      if (!hasAddrOf && !hasBufPtr) continue
      if (!/\.unsafe_bitcast\[|\.as_unsafe_any_origin\(\)|\.unsafe_ptr\(\)/.test(stmt.text)) continue

      // FALSE POSITIVE 1: function-pointer reinterpret / immediate deref.
      // `Pointer(to=x).unsafe_bitcast[T]()[]` consumes the pointer inside the
      // statement, so nothing outlives it. raw.mojo's 142 slot casts are all
      // this shape.
      //
      // The test is a plain substring scan for `()[]` after the bitcast, NOT
      // a bracket-delimited regex: every one of those type parameters is a
      // function type containing nested brackets —
      //
      //   .unsafe_bitcast[def(OpaquePointer[MutAnyOrigin], ...) thin abi("C")
      //                   -> NapiStatus]()[]
      //
      // so a `[^\]]+` class stops at the first inner `]` and the filter
      // silently fails open, admitting all 142 as population B.
      const bc = stmt.text.indexOf('.unsafe_bitcast[')
      if (bc !== -1 && /\(\)\s*\[\s*\]/.test(stmt.text.slice(bc))) {
        findings.push({ file: rel, line: stmt.startLine, target: null, kind: 'fn-ptr-reinterpret' })
        continue
      }

      // A bare string-literal receiver — `"length".unsafe_ptr()` — is .rodata
      // like any other StringLiteral, but has no identifier to look up, so it
      // must be caught before extraction rather than by declaredTypeOf.
      if (/"[^"]*"\s*\.unsafe_ptr\(\)/.test(stmt.text) && !/Pointer\(\s*to=/.test(stmt.text)) {
        findings.push({ file: rel, line: stmt.startLine, target: null, kind: 'static-string' })
        continue
      }

      let target = null
      let shape = null
      const mAddr = stmt.text.match(/Pointer\(\s*to=([^)]*?)\s*\)/)
      const mBuf = stmt.text.match(/(?:^|[^\w.])([\w.]+)\.unsafe_ptr\(\)/)
      if (mAddr) {
        target = mAddr[1].trim()
        shape = 'address-of'
      } else if (mBuf) {
        target = mBuf[1].trim()
        shape = 'buffer-pointer'
      }
      if (!target) {
        findings.push({ file: rel, line: stmt.startLine, target: null, kind: 'unparsed' })
        continue
      }
      // `args[0]` -> `args`; `self.value` stays whole.
      target = target.replace(/\[[^\]]*\]$/, '')


      // FALSE POSITIVE 2: a struct FIELD, not a local. The pointer is into
      // storage the receiver owns; the receiver's own lifetime governs it.
      // `b[].slot` is the cached NapiBindings allocation, which is never
      // freed for the life of the env.
      if (target.startsWith('self.') || /^\w+\[\]\./.test(target)) {
        findings.push({ file: rel, line: stmt.startLine, target, kind: 'field-not-local' })
        continue
      }

      const d = enclosingDef(stmt.startLine, stmt.indent)

      const decl = d ? declaredTypeOf(codeLines, d, target) : null

      // FALSE POSITIVE 2: a StringLiteral / StaticString. Its bytes live in
      // .rodata for the life of the process, so there is no lifetime to end.
      // These are the `name.unsafe_ptr()` arguments in define_class,
      // JsSymbol.create_for, ...
      if (decl && STATIC_STR.has(decl.type)) {
        findings.push({ file: rel, line: stmt.startLine, target, kind: 'static-string' })
        continue
      }

      // FALSE POSITIVE 3: the file crosses no FFI boundary at all.
      // `src/addon/user_fns.mojo` is pure Mojo by construction — its header
      // says so and the generator relies on it — so a Span formed over a
      // List's buffer there matches the buffer-pointer shape while `AnyOrigin`
      // never enters the picture.
      //
      // This is a FILE-level test on purpose. A def-level one excluded
      // `src/addon/function_ops.mojo`, which reaches N-API indirectly through
      // `registry[].new_instance(...)` and whose `arg0` is genuinely pinned.
      if (!fileTouchesFFI) {
        findings.push({ file: rel, line: stmt.startLine, target, kind: 'no-ffi-in-scope' })
        continue
      }

      // FALSE POSITIVE 4: a borrowed, memory-passed parameter (see
      // REGISTER_PASSABLE above). Address-of only: taking `.unsafe_ptr()` on a
      // borrowed String is about the String's HEAP BUFFER, whose owner can
      // still be destroyed at its last tracked use.
      if (decl && decl.isParam && decl.borrowed && shape === 'address-of' && !REGISTER_PASSABLE.has(decl.type)) {
        findings.push({
          file: rel, line: stmt.startLine, target,
          kind: 'borrowed-struct-param', type: decl.type, def: d.name,
        })
        continue
      }

      let disposition = 'unknown-scope'
      if (d) {
        const bodyEnd = defBodyEnd(codeLines, d.bodyStart, d.indent)
        const after = codeLines.slice(stmt.endLine, bodyEnd).join('\n')
        const word = new RegExp(`\\b${target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`)
        if (new RegExp(`pin_across_ffi\\(\\s*${target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(after)) {
          disposition = 'pinned'
        } else if (word.test(after)) {
          disposition = 'post-use'
        } else {
          disposition = 'AT-RISK'
        }
      }

      findings.push({
        file: rel,
        line: stmt.startLine,
        target,
        kind: 'population-b',
        shape,
        disposition,
        def: d ? d.name : null,
      })
    }
  }
}

const popB = findings.filter((f) => f.kind === 'population-b')
const byDisposition = (d) => popB.filter((f) => f.disposition === d)
const atRisk = byDisposition('AT-RISK')

if (AS_JSON) {
  console.log(
    JSON.stringify(
      {
        populationB: popB.length,
        pinned: byDisposition('pinned').length,
        postUse: byDisposition('post-use').length,
        atRisk: atRisk.length,
        excluded: {
          fnPtrReinterpret: findings.filter((f) => f.kind === 'fn-ptr-reinterpret').length,
          fieldNotLocal: findings.filter((f) => f.kind === 'field-not-local').length,
          unparsed: findings.filter((f) => f.kind === 'unparsed').length,
        },
        sites: SHOW_ALL ? popB : atRisk,
        other: SHOW_ALL ? findings.filter((f) => f.kind !== 'population-b' && f.kind !== 'fn-ptr-reinterpret') : undefined,
      },
      null,
      2
    )
  )
  process.exit(0)
}

console.log('Population B — pointer-to-local through an AnyOrigin FFI signature\n')
console.log(`  population B sites      ${popB.length}`)
console.log(`    pinned                ${byDisposition('pinned').length}   (explicit pin_across_ffi)`)
console.log(`    post-use              ${byDisposition('post-use').length}   (tracked use after the call)`)
console.log(`    AT-RISK               ${atRisk.length}`)
console.log('\n  excluded as false positives')
console.log(`    fn-ptr reinterpret    ${findings.filter((f) => f.kind === 'fn-ptr-reinterpret').length}`)
console.log(`    struct field          ${findings.filter((f) => f.kind === 'field-not-local').length}`)
console.log(`    borrowed struct param ${findings.filter((f) => f.kind === 'borrowed-struct-param').length}`)
console.log(`    static string         ${findings.filter((f) => f.kind === 'static-string').length}`)
console.log(`    no FFI in scope       ${findings.filter((f) => f.kind === 'no-ffi-in-scope').length}`)
console.log(`    unparsed              ${findings.filter((f) => f.kind === 'unparsed').length}`)

const byFile = {}
for (const f of popB) byFile[f.file] = (byFile[f.file] || 0) + 1
console.log('\n  population B by file')
for (const [f, n] of Object.entries(byFile).sort((a, b) => b[1] - a[1])) {
  console.log(`    ${String(n).padStart(4)}  ${f}`)
}

const show = SHOW_ALL ? popB : atRisk
if (show.length) {
  console.log(`\n  ${SHOW_ALL ? 'all population-B sites' : 'AT-RISK sites'}`)
  for (const f of show) {
    console.log(`    ${f.file}:${f.line}  ${f.def}()  ${f.target}  [${f.disposition}]`)
  }
} else {
  console.log('\n  no at-risk sites')
}

if (CHECK && atRisk.length) {
  console.error(`\nFAIL: ${atRisk.length} at-risk population-B site(s) — see docs/handoff-argv-origin-migration.md`)
  process.exit(1)
}
