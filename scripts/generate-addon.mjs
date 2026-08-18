#!/usr/bin/env node
/**
 * generate-addon.mjs — Generate Mojo callback trampolines from a declaration file
 *
 * Reads src/exports.toml and generates:
 *   1. Callback functions (fn xxx_fn(env, info) -> NapiValue) with
 *      arg extraction, type validation, error handling
 *   2. Registration code using ModuleBuilder + fn_ptr
 *
 * Usage: node scripts/generate-addon.mjs
 * Output: src/generated/callbacks.mojo (import from lib.mojo)
 *
 * The declaration file format is TOML with [functions.name] sections.
 * Complex functions (async, promises, classes) should stay hand-written.
 */

import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
// Shared TOML-subset parser (also used by generate-dts.js — one format, one
// parser; the two copies this replaced had already diverged).
import { parseTOML } from './toml-lite.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DECL_PATH = process.env.NAPI_MOJO_TOML || join(__dirname, '..', 'src', 'exports.toml');
const OUT_DIR = process.env.NAPI_MOJO_OUT || join(__dirname, '..', 'src', 'generated');
const OUT_PATH = join(OUT_DIR, 'callbacks.mojo');
const STRUCTS_PATH = join(OUT_DIR, 'structs.mojo');

// A declaration problem must fail the run, not warn-and-emit-wrong-Mojo.
// Every silent fallback this generator used to have produced code that either
// didn't compile (async uint32 returns), compiled but lied (async string args
// stored into Float64 fields while the .d.ts claimed Promise<string>), or
// crashed the generator later with a raw stack trace (unknown struct field).
function fail(msg) {
  console.error(`[generate-addon] ERROR: ${msg}`);
  process.exit(1);
}

// TOML section keys become Mojo identifiers verbatim ([functions.my-fn]
// would emit `def my-fn_fn`), and js_name is spliced into Mojo string
// literals ("..." would terminate the literal early). Validate both.
function validateIdentifier(name, where) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
    fail(`${where}: "${name}" is not a valid Mojo identifier (use [a-zA-Z_][a-zA-Z0-9_]*)`);
  }
}

function validateJsName(jsName, where) {
  if (/["\\\n]/.test(jsName)) {
    fail(`${where}: js_name "${jsName}" contains a quote, backslash, or newline — it is spliced into Mojo string literals verbatim`);
  }
}

// --- Type mapping: declaration type -> arg extraction code ---
// Uses _b (cached NapiBindings pointer) for all N-API calls
//
// A trailing '?' on a type name (e.g. "number?") marks it as nullable —
// the type check is skipped and the raw NapiValue is passed to the body.
const TYPE_MAP = {
  number: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsNumber.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsNumber.create(_b, env, ${expr}).value`,
  },
  string: {
    napi_type: 'NAPI_TYPE_STRING',
    type_name: 'string',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsString.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsString.create(_b, env, ${expr}).value`,
  },
  boolean: {
    napi_type: 'NAPI_TYPE_BOOLEAN',
    type_name: 'boolean',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsBoolean.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsBoolean.create(_b, env, ${expr}).value`,
  },
  // bool: alias for boolean
  bool: {
    napi_type: 'NAPI_TYPE_BOOLEAN',
    type_name: 'boolean',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsBoolean.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsBoolean.create(_b, env, ${expr}).value`,
  },
  int32: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsInt32.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsInt32.create(_b, env, ${expr}).value`,
  },
  uint32: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsUInt32.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsUInt32.create(_b, env, ${expr}).value`,
  },
  int64: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsInt64.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsInt64.create(_b, env, ${expr}).value`,
  },
  // object: pass raw NapiValue, validate type is object
  object: {
    napi_type: 'NAPI_TYPE_OBJECT',
    passthrough: true,
    type_name: 'object',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
  // array: validate with js_is_array (typeof returns 'object' for arrays)
  array: {
    napi_type: '__IS_ARRAY__', // special sentinel — emits js_is_array check
    passthrough: true,
    type_name: 'array',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
  // number[]: typed array of Float64 — uses from_js_array_f64 / to_js_array_f64
  'number[]': {
    napi_type: '__IS_ARRAY__',
    type_name: 'array',
    extract: (varName, argExpr) =>
      `        var ${varName} = from_js_array_f64(_b, env, ${argExpr})`,
    create: (expr) => `to_js_array_f64(_b, env, ${expr})`,
  },
  // string[]: typed array of String — uses from_js_array_str / to_js_array_str
  'string[]': {
    napi_type: '__IS_ARRAY__',
    type_name: 'array',
    extract: (varName, argExpr) =>
      `        var ${varName} = from_js_array_str(_b, env, ${argExpr})`,
    create: (expr) => `to_js_array_str(_b, env, ${expr})`,
  },
  any: {
    napi_type: null, // no type check
    passthrough: true,
    type_name: 'any',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
};

// --- Struct field type info: TOML type → Mojo type + from_js/to_js expressions ---
const STRUCT_FIELD_MAP = {
  string:  { mojoType: 'String',  fromJs: (b, e, v) => `JsString.from_napi_value(${b}, ${e}, ${v})`,  toJs: (b, e, v) => `JsString.create(${b}, ${e}, ${v}).value` },
  number:  { mojoType: 'Float64', fromJs: (b, e, v) => `JsNumber.from_napi_value(${b}, ${e}, ${v})`,  toJs: (b, e, v) => `JsNumber.create(${b}, ${e}, ${v}).value` },
  boolean: { mojoType: 'Bool',    fromJs: (b, e, v) => `JsBoolean.from_napi_value(${b}, ${e}, ${v})`, toJs: (b, e, v) => `JsBoolean.create(${b}, ${e}, ${v}).value` },
  bool:    { mojoType: 'Bool',    fromJs: (b, e, v) => `JsBoolean.from_napi_value(${b}, ${e}, ${v})`, toJs: (b, e, v) => `JsBoolean.create(${b}, ${e}, ${v}).value` },
  int32:   { mojoType: 'Int32',   fromJs: (b, e, v) => `JsInt32.from_napi_value(${b}, ${e}, ${v})`,   toJs: (b, e, v) => `JsInt32.create(${b}, ${e}, ${v}).value` },
  uint32:  { mojoType: 'UInt32',  fromJs: (b, e, v) => `JsUInt32.from_napi_value(${b}, ${e}, ${v})`,  toJs: (b, e, v) => `JsUInt32.create(${b}, ${e}, ${v}).value` },
  int64:   { mojoType: 'Int64',   fromJs: (b, e, v) => `JsInt64.from_napi_value(${b}, ${e}, ${v})`,   toJs: (b, e, v) => `JsInt64.create(${b}, ${e}, ${v}).value` },
};

// --- Register struct types into TYPE_MAP dynamically ---
function registerStructTypes(structs) {
  for (const [name, sDecl] of Object.entries(structs)) {
    const pascalName = snakeToPascal(name);
    TYPE_MAP[name] = {
      napi_type: 'NAPI_TYPE_OBJECT',
      type_name: sDecl.js_name || pascalName,
      extract: (varName, argExpr) =>
        `        var ${varName} = ${name}_from_js(_b, env, ${argExpr})`,
      create: (expr) => `${name}_to_js(_b, env, ${expr})`,
    };
  }
}

// --- Resolve type, handling nullable suffix ('?') ---
// Returns { typeInfo, nullable } where nullable=true skips the type check.
// Unknown tokens are a hard error: the old warn-and-fall-back-to-any produced
// a raw NapiValue that flowed into a mojo_fn expecting a typed value, failing
// far from the cause (or, for mismatched signatures, not compiling at all).
function resolveType(rawType) {
  const nullable = rawType.endsWith('?');
  const baseType = nullable ? rawType.slice(0, -1) : rawType;
  if (!TYPE_MAP[baseType]) {
    fail(`unknown type token "${baseType}" — valid tokens: ${Object.keys(TYPE_MAP).join(', ')} (plus declared struct names). Check your exports.toml.`);
  }
  return { typeInfo: TYPE_MAP[baseType], nullable };
}

// --- Get the arg expression variable for position i in a totalArgs-arg function ---
function getArgExpr(i, totalArgs) {
  if (totalArgs === 1) return 'arg0';
  if (totalArgs <= 4) return `args[${i}]`;
  return `_a${i}`;
}

// --- Emit type check lines for a single argument ---
// Returns an array of lines. For 'array' type uses js_is_array; for others
// uses js_typeof. Skips all checks when nullable=true.
function emitTypeCheck(lines, jsName, rawType, argExpr, argDesc) {
  const { typeInfo, nullable } = resolveType(rawType);
  // '?' in argument position only suppresses the type CHECK — it does not make
  // the extraction null-safe. For a converting token the extract still calls
  // Js*.from_napi_value / <struct>_from_js on the value, which raises on null,
  // while toml-dts.js faithfully advertises `| null`. That combination is a
  // lie the caller can only discover at runtime, so it is rejected here.
  // Pass-through tokens (any/object/array) hand the raw napi_value straight to
  // the Mojo fn, so for those `| null` is the truth and '?' stays supported.
  if (nullable && !typeInfo.passthrough) {
    const base = rawType.slice(0, -1);
    fail(
      `${jsName}: nullable argument type "${rawType}"${argDesc ? ` (${argDesc})` : ''} is not supported — ` +
      `'?' skips the type check but the generated extract still converts the value as ${base}, ` +
      `so passing the null the .d.ts advertises would raise. Declare it as "${base}" and reject null ` +
      `in your Mojo function, or use "any?" if the argument really may be null. ` +
      `('?' on a RETURN type is unaffected — that maps Optional[T] to null.)`);
  }
  if (nullable || !typeInfo.napi_type) return;
  if (typeInfo.napi_type === '__IS_ARRAY__') {
    lines.push(`        if not js_is_array(_b, env, ${argExpr}):`);
    lines.push(`            throw_js_type_error_dynamic(_b, env, "${jsName}: expected array${argDesc ? ' for ' + argDesc : ''}")`);
    lines.push(`            return NapiValue(unsafe_from_address=Int(0))`);
  } else {
    const tVar = `_t_${argExpr.replace(/[^a-z0-9]/gi, '_')}`;
    lines.push(`        var ${tVar} = js_typeof(_b, env, ${argExpr})`);
    lines.push(`        if ${tVar} != ${typeInfo.napi_type}:`);
    lines.push(`            throw_js_type_error_dynamic(_b, env, "${jsName}: expected ${typeInfo.type_name}${argDesc ? ' for ' + argDesc : ''}, got " + js_type_name(${tVar}))`);
    lines.push(`            return NapiValue(unsafe_from_address=Int(0))`);
  }
}

// --- Code generation ---
function generateCallback(name, decl) {
  const jsName = decl.js_name || name;
  const args = decl.args || [];
  const returns = decl.returns || 'any';
  const body = decl.body;
  const mojoFn = decl.mojo_fn;  // optional: call a named pure Mojo function
  const fnName = `${name}_fn`;

  validateIdentifier(name, `[functions.${name}]`);
  validateJsName(jsName, `[functions.${name}]`);
  if (!body && !mojoFn) {
    fail(`[functions.${name}] has neither "body" nor "mojo_fn" — the generated callback would fall through its try block with no return value`);
  }
  if (body && mojoFn) {
    console.warn(`[generate-addon] Warning: [functions.${name}] declares both "body" and "mojo_fn" — mojo_fn wins, body is ignored.`);
  }

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);

  if (args.length === 0) {
    // No args — just run body
  } else if (args.length === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'arg0', null);
  } else if (args.length === 2) {
    lines.push(`        var args = CbArgs.get_two(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'args[0]', 'arg 1');
    emitTypeCheck(lines, jsName, args[1], 'args[1]', 'arg 2');
  } else if (args.length === 3) {
    lines.push(`        var args = CbArgs.get_three(_b, env, info)`);
    for (let i = 0; i < 3; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  } else if (args.length === 4) {
    lines.push(`        var args = CbArgs.get_four(_b, env, info)`);
    for (let i = 0; i < 4; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  } else {
    // N >= 5: heap-allocate argv, copy to locals, free immediately before body
    const n = args.length;
    lines.push(`        var _argv = unsafe_alloc[NapiValue](${n})`);
    // get_argv returns the actual argc (discarded — argv is napi-padded with
    // undefined) and needs the explicit origin widening on the alloc'd buffer.
    lines.push(`        _ = CbArgs.get_argv(_b, env, info, ${n}, _argv.as_unsafe_any_origin())`);
    for (let i = 0; i < n; i++) lines.push(`        var _a${i} = _argv[unsafe_offset=${i}]`);
    lines.push(`        _argv.unsafe_free()`);
    for (let i = 0; i < n; i++) emitTypeCheck(lines, jsName, args[i], `_a${i}`, `arg ${i+1}`);
  }

  if (mojoFn) {
    // Auto-trampoline: extract Mojo-typed args, call mojoFn, wrap result.
    // mojo_fn takes precedence over body if both are present.
    for (let i = 0; i < args.length; i++) {
      const { typeInfo } = resolveType(args[i]);
      lines.push(typeInfo.extract(`mojo_arg${i}`, getArgExpr(i, args.length)));
    }
    const callArgs = args.map((_, i) => `mojo_arg${i}`).join(', ');
    lines.push(`        var mojo_result = ${mojoFn}(${callArgs})`);
    const returnsNullable = returns.endsWith('?');
    const { typeInfo: retTypeInfo } = resolveType(returns);
    if (returnsNullable) {
      // Optional[T] → null check + unwrap
      lines.push(`        if not mojo_result:`);
      lines.push(`            return JsNull.create(_b, env).value`);
      lines.push(`        return ${retTypeInfo.create('mojo_result.value()')}`);
    } else {
      lines.push(`        return ${retTypeInfo.create('mojo_result')}`);
    }
  } else if (body) {
    // Insert body (indented to 8 spaces)
    const bodyLines = body.split('\n');
    for (const bl of bodyLines) {
      lines.push(`        ${bl}`);
    }
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${jsName} failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// --- Async function generation ---

// Mojo types for async data struct fields.
// IMPORTANT: only numeric (non-destructor) types are permitted here.
// Async data structs cross the JS→worker-thread boundary — Mojo types with
// destructors (String, List, objects) cannot be safely moved across threads.
// This is an intentional strict subset of TYPE_MAP.
// createExpr uses the cached-bindings overloads: the complete callback has no
// `info` to fetch bindings from, but the ENTRY callback does — so the
// generated data struct carries the bindings address across the async hop
// (written on the main thread before queueing, read on the main thread in
// complete; the worker-thread execute never touches it). Mojo has no module
// globals (see spike/global_probe.mojo's verdict), so the payload the
// context already carries is the only zero-dlsym channel.
const ASYNC_TYPE_MAP = {
  number: { mojoType: 'Float64', zeroVal: '0.0', createExpr: (e) => `JsNumber.create(_b, env, ${e})` },
  int32:  { mojoType: 'Int32',   zeroVal: '0',   createExpr: (e) => `JsInt32.create(_b, env, ${e})` },
  uint32: { mojoType: 'UInt32',  zeroVal: '0',   createExpr: (e) => `JsUInt32.create(_b, env, ${e})` },
  int64:  { mojoType: 'Int64',   zeroVal: '0',   createExpr: (e) => `JsInt64.create(_b, env, ${e})` },
};

function snakeToPascal(s) {
  return s.split('_').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join('');
}

// Generates: data struct + execute callback + complete callback + entry-point callback
function generateAsyncFunction(name, decl) {
  const jsName = decl.js_name || name;
  const args = decl.args || [];
  const returnsToken = (decl.returns || 'number').replace(/\?$/, '');
  const executeBody = decl.execute_body || '';
  const structName = `${snakeToPascal(name)}Data`;

  validateIdentifier(name, `[functions.${name}] (async)`);
  validateJsName(jsName, `[functions.${name}] (async)`);
  // Hard errors, not fallbacks. The old fallback-to-number path emitted arg
  // extraction from TYPE_MAP (e.g. JsString.from_napi_value) assigned into a
  // Float64 struct field — code that cannot compile — while generate-dts.js
  // typed it Promise<string>. An unsupported type must stop the run.
  if (!ASYNC_TYPE_MAP[returnsToken]) {
    fail(`async function "${name}": return type "${returnsToken}" is not supported for async (worker-thread data structs allow only: ${Object.keys(ASYNC_TYPE_MAP).join(', ')})`);
  }
  if (args.length > 4) {
    fail(`async function "${name}": ${args.length} args declared, but async generation supports at most 4`);
  }
  const retType = ASYNC_TYPE_MAP[returnsToken];
  const argMojoTypes = args.map((a, idx) => {
    const tok = a.replace(/\?$/, '');
    if (!ASYNC_TYPE_MAP[tok]) {
      fail(`async function "${name}": arg[${idx}] type "${tok}" is not supported for async (worker-thread data structs allow only: ${Object.keys(ASYNC_TYPE_MAP).join(', ')})`);
    }
    return ASYNC_TYPE_MAP[tok];
  });

  const out = [];

  // 1. Data struct (Movable — no destructors, safe to pass across threads)
  out.push(`struct ${structName}(Movable):`);
  // NapiDeferred/NapiAsyncWork hide AnyOrigin, which dev2026062206 rejects in
  // struct fields. Decorator is the changelog-sanctioned stopgap — see the
  // AnyOrigin rule in CLAUDE.md.
  out.push(`    @__allow_legacy_any_origin_fields`);
  out.push(`    var deferred: NapiDeferred`);
  out.push(`    @__allow_legacy_any_origin_fields`);
  out.push(`    var work: NapiAsyncWork`);
  out.push(`    # Cached NapiBindings address, written by the entry callback on the`);
  out.push(`    # main thread; read only by the complete callback (also main thread).`);
  out.push(`    var bindings_addr: Int`);
  for (let i = 0; i < args.length; i++) {
    out.push(`    var input${i}: ${argMojoTypes[i].mojoType}`);
  }
  out.push(`    var result: ${retType.mojoType}`);
  out.push('');
  const initParams = argMojoTypes.map((t, i) => `input${i}: ${t.mojoType}`).join(', ');
  out.push(`    def __init__(out self${initParams ? ', ' + initParams : ''}):`);
  out.push(`        self.deferred = NapiDeferred(unsafe_from_address=Int(0))`);
  out.push(`        self.work = NapiAsyncWork(unsafe_from_address=Int(0))`);
  out.push(`        self.bindings_addr = 0`);
  for (let i = 0; i < args.length; i++) {
    out.push(`        self.input${i} = input${i}`);
  }
  out.push(`        self.result = ${retType.zeroVal}`);
  out.push('');
  out.push(`    def __moveinit__(out self, deinit take: Self):`);
  out.push(`        self.deferred = take.deferred`);
  out.push(`        self.work = take.work`);
  out.push(`        self.bindings_addr = take.bindings_addr`);
  for (let i = 0; i < args.length; i++) {
    out.push(`        self.input${i} = take.input${i}`);
  }
  out.push(`        self.result = take.result`);

  // 2. Execute callback (worker thread — no N-API calls allowed)
  out.push('');
  out.push(`def ${name}_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):`);
  out.push(`    var ptr = data.unsafe_bitcast[${structName}]()`);
  // Preserve relative indentation, exactly like the sync `body` path does.
  // The old per-line .trim() flattened every line to one level, silently
  // destroying any if/for nesting inside execute_body.
  for (const el of executeBody.split('\n')) {
    out.push(el.trim() ? `    ${el}` : '');
  }

  // 3. Complete callback (main thread — resolve/reject, then free heap).
  // Reconstructs the cached bindings from the struct field, so the whole
  // settle path runs on cached function pointers — no per-call dlsym.
  out.push('');
  out.push(`def ${name}_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):`);
  out.push(`    var ptr = data.unsafe_bitcast[${structName}]()`);
  out.push(`    try:`);
  out.push(`        var _b = Bindings(unsafe_from_address=ptr[].bindings_addr)`);
  out.push(`        if status == NAPI_OK:`);
  out.push(`            var rv = ${retType.createExpr('ptr[].result')}`);
  out.push(`            AsyncWork.resolve(_b, env, ptr[].deferred, ptr[].work, rv.value)`);
  out.push(`        else:`);
  out.push(`            AsyncWork.reject_with_error(_b, env, ptr[].deferred, ptr[].work, "${jsName} failed")`);
  out.push(`    except:`);
  out.push(`        pass`);
  out.push(`    ptr.unsafe_deinit_pointee()`);
  out.push(`    ptr.unsafe_free()`);

  // 4. Entry-point callback (standard N-API: type-check, alloc, queue, return promise)
  out.push('');
  out.push(`def ${name}_fn(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  out.push(`    try:`);
  out.push(`        var _b = CbArgs.get_bindings(env, info)`);
  if (args.length === 1) {
    out.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
    emitTypeCheck(out, jsName, args[0], 'arg0', null);
    out.push((TYPE_MAP[args[0].replace(/\?$/, '')] || TYPE_MAP.number).extract('input0', 'arg0'));
  } else if (args.length === 2) {
    out.push(`        var args = CbArgs.get_two(_b, env, info)`);
    emitTypeCheck(out, jsName, args[0], 'args[0]', 'arg 1');
    emitTypeCheck(out, jsName, args[1], 'args[1]', 'arg 2');
    out.push((TYPE_MAP[args[0].replace(/\?$/, '')] || TYPE_MAP.number).extract('input0', 'args[0]'));
    out.push((TYPE_MAP[args[1].replace(/\?$/, '')] || TYPE_MAP.number).extract('input1', 'args[1]'));
  } else if (args.length === 3) {
    out.push(`        var args = CbArgs.get_three(_b, env, info)`);
    for (let i = 0; i < 3; i++) emitTypeCheck(out, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
    for (let i = 0; i < 3; i++) out.push((TYPE_MAP[args[i].replace(/\?$/, '')] || TYPE_MAP.number).extract(`input${i}`, `args[${i}]`));
  } else if (args.length === 4) {
    out.push(`        var args = CbArgs.get_four(_b, env, info)`);
    for (let i = 0; i < 4; i++) emitTypeCheck(out, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
    for (let i = 0; i < 4; i++) out.push((TYPE_MAP[args[i].replace(/\?$/, '')] || TYPE_MAP.number).extract(`input${i}`, `args[${i}]`));
  }
  const inputArgs = argMojoTypes.map((_, i) => `input${i}`).join(', ');
  out.push(`        var data_ptr = unsafe_alloc[${structName}](1)`);
  out.push(`        data_ptr.unsafe_write(${structName}(${inputArgs}))`);
  out.push(`        data_ptr[].bindings_addr = Int(_b)`);
  out.push(`        var exec_ref = ${name}_execute`);
  out.push(`        var comp_ref = ${name}_complete`);
  // .as_unsafe_any_origin() is required as of dev2026072306: the implicit
  // UnsafePointer -> MutAnyOrigin conversion at C-FFI signatures was removed.
  out.push(`        var aw = AsyncWork.queue(_b, env, "${jsName}", data_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(), fn_ptr(exec_ref), fn_ptr(comp_ref))`);
  out.push(`        data_ptr[].deferred = aw.deferred`);
  out.push(`        data_ptr[].work = aw.work`);
  out.push(`        return aw.value`);
  out.push(`    except:`);
  out.push(`        throw_js_error(env, "${jsName} failed")`);
  out.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return out.join('\n');
}

function generateRegistration(declarations) {
  const lines = [];
  const entries = Object.entries(declarations);

  // Var declarations (ASAP safety)
  for (const [name] of entries) {
    lines.push(`    var ${name}_gen_ref = ${name}_fn`);
  }

  lines.push('');

  // Registration calls
  for (const [name, decl] of entries) {
    const jsName = decl.js_name || name;
    lines.push(`    m.method("${jsName}", fn_ptr(${name}_gen_ref))`);
  }

  return lines.join('\n');
}

// --- Class generation ---

// Generate the constructor callback for a class
function generateClassConstructor(className, decl) {
  const jsName = decl.js_name || className;
  const ctorArgs = decl.constructor_args || [];
  const ctorBody = decl.constructor_body || 'pass';
  const fnName = `${className}_ctor_fn`;

  validateIdentifier(className, `[classes.${className}]`);
  validateJsName(jsName, `[classes.${className}]`);
  if (ctorArgs.length > 4) {
    // The arity chain below ends at 4 with no else — more args would emit a
    // body referencing `args` that was never declared.
    fail(`class "${className}": ${ctorArgs.length} constructor args declared, but class generation supports at most 4`);
  }

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);

  if (ctorArgs.length === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
    emitTypeCheck(lines, jsName, ctorArgs[0], 'arg0', null);
  } else if (ctorArgs.length === 2) {
    lines.push(`        var args = CbArgs.get_two(_b, env, info)`);
    emitTypeCheck(lines, jsName, ctorArgs[0], 'args[0]', 'arg 1');
    emitTypeCheck(lines, jsName, ctorArgs[1], 'args[1]', 'arg 2');
  } else if (ctorArgs.length === 3) {
    lines.push(`        var args = CbArgs.get_three(_b, env, info)`);
    for (let i = 0; i < 3; i++) emitTypeCheck(lines, jsName, ctorArgs[i], `args[${i}]`, `arg ${i+1}`);
  } else if (ctorArgs.length === 4) {
    lines.push(`        var args = CbArgs.get_four(_b, env, info)`);
    for (let i = 0; i < 4; i++) emitTypeCheck(lines, jsName, ctorArgs[i], `args[${i}]`, `arg ${i+1}`);
  }

  const bodyLines = ctorBody.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`        return this_val`);
  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${jsName} constructor failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Generate an instance method callback (has access to this_val)
function generateClassMethod(className, methodName, decl) {
  const jsName = decl.js_name || methodName;
  const fnName = `${className}_${methodName}_fn`;
  const args = decl.args || [];
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  validateIdentifier(methodName, `[classes.${className}.instance_methods.${methodName}]`);
  validateJsName(jsName, `[classes.${className}.instance_methods.${methodName}]`);
  if (args.length > 4) {
    fail(`class method "${className}.${methodName}": ${args.length} args declared, but class generation supports at most 4`);
  }

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);

  if (args.length === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'arg0', null);
  } else if (args.length === 2) {
    lines.push(`        var args = CbArgs.get_two(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'args[0]', 'arg 1');
    emitTypeCheck(lines, jsName, args[1], 'args[1]', 'arg 2');
  } else if (args.length === 3) {
    lines.push(`        var args = CbArgs.get_three(_b, env, info)`);
    for (let i = 0; i < 3; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  } else if (args.length === 4) {
    lines.push(`        var args = CbArgs.get_four(_b, env, info)`);
    for (let i = 0; i < 4; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  }

  const bodyLines = body.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${jsName} failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Convert camelCase to snake_case for Mojo identifiers
function camelToSnake(s) {
  return s.replace(/([A-Z])/g, m => '_' + m.toLowerCase());
}

// Generate a static method callback (no this_val)
function generateClassStaticMethod(className, methodName, decl) {
  const jsName = decl.js_name || methodName;
  const fnName = `${className}_static_${camelToSnake(methodName)}_fn`;
  const args = decl.args || [];
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  validateJsName(jsName, `[classes.${className}.static_methods.${methodName}]`);
  if (args.length > 4) {
    fail(`static method "${className}.${methodName}": ${args.length} args declared, but class generation supports at most 4`);
  }

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);

  if (args.length === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'arg0', null);
  } else if (args.length === 2) {
    lines.push(`        var args = CbArgs.get_two(_b, env, info)`);
    emitTypeCheck(lines, jsName, args[0], 'args[0]', 'arg 1');
    emitTypeCheck(lines, jsName, args[1], 'args[1]', 'arg 2');
  } else if (args.length === 3) {
    lines.push(`        var args = CbArgs.get_three(_b, env, info)`);
    for (let i = 0; i < 3; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  } else if (args.length === 4) {
    lines.push(`        var args = CbArgs.get_four(_b, env, info)`);
    for (let i = 0; i < 4; i++) emitTypeCheck(lines, jsName, args[i], `args[${i}]`, `arg ${i+1}`);
  }

  const bodyLines = body.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${jsName} failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Generate a setter callback (has access to this_val + val)
function generateClassSetter(className, propName, decl) {
  const fnName = `${className}_set_${propName}_fn`;
  const body = decl.body || 'return val';

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);
  lines.push(`        var val = CbArgs.get_one(_b, env, info)`);

  const bodyLines = body.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${propName} setter failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Generate a getter callback (has access to this_val, no args)
function generateClassGetter(className, getterName, decl) {
  const fnName = `${className}_get_${getterName}_fn`;
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);

  const bodyLines = body.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${getterName} getter failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Generate class registration code (ClassBuilder setup)
function generateClassRegistration(classes) {
  const lines = [];
  const classEntries = Object.entries(classes);

  // Var declarations for all class callbacks (ASAP safety)
  for (const [cName, cDecl] of classEntries) {
    lines.push(`    var ${cName}_ctor_gen_ref = ${cName}_ctor_fn`);
    for (const mName of Object.keys(cDecl.instance_methods || {})) {
      lines.push(`    var ${cName}_${mName}_gen_ref = ${cName}_${mName}_fn`);
    }
    for (const gName of Object.keys(cDecl.getters || {})) {
      lines.push(`    var ${cName}_get_${gName}_gen_ref = ${cName}_get_${gName}_fn`);
    }
    for (const sName of Object.keys(cDecl.setters || {})) {
      lines.push(`    var ${cName}_set_${sName}_gen_ref = ${cName}_set_${sName}_fn`);
    }
    for (const smName of Object.keys(cDecl.static_methods || {})) {
      lines.push(`    var ${cName}_static_${camelToSnake(smName)}_gen_ref = ${cName}_static_${camelToSnake(smName)}_fn`);
    }
  }

  lines.push('');

  // ClassBuilder setup
  for (const [cName, cDecl] of classEntries) {
    const jsName = cDecl.js_name || cName;
    lines.push(`    var ${cName}_builder = m.class_def("${jsName}", fn_ptr(${cName}_ctor_gen_ref))`);
    for (const mName of Object.keys(cDecl.instance_methods || {})) {
      const jsMethodName = (cDecl.instance_methods[mName] || {}).js_name || mName;
      lines.push(`    ${cName}_builder.instance_method("${jsMethodName}", fn_ptr(${cName}_${mName}_gen_ref))`);
    }
    const setterNames = new Set(Object.keys(cDecl.setters || {}));
    for (const gName of Object.keys(cDecl.getters || {})) {
      const jsGetterName = (cDecl.getters[gName] || {}).js_name || gName;
      if (setterNames.has(gName)) {
        lines.push(`    ${cName}_builder.getter_setter("${jsGetterName}", fn_ptr(${cName}_get_${gName}_gen_ref), fn_ptr(${cName}_set_${gName}_gen_ref))`);
      } else {
        lines.push(`    ${cName}_builder.getter("${jsGetterName}", fn_ptr(${cName}_get_${gName}_gen_ref))`);
      }
    }
    for (const smName of Object.keys(cDecl.static_methods || {})) {
      const jsSmName = (cDecl.static_methods[smName] || {}).js_name || smName;
      lines.push(`    ${cName}_builder.static_method("${jsSmName}", fn_ptr(${cName}_static_${camelToSnake(smName)}_gen_ref))`);
    }
  }

  return lines.join('\n');
}

// --- Struct code generation ---
// Generates a Mojo struct + from_js/to_js converter functions for each [structs.*] section.
function generateStruct(name, sDecl) {
  const fields = sDecl.fields || {};
  const fieldEntries = Object.entries(fields);
  const pascalName = snakeToPascal(name);
  const structName = `${pascalName}Data`;
  const out = [];

  validateIdentifier(name, `[structs.${name}]`);

  // A struct with no fields emits `def __init__(out self, ):` plus a
  // __moveinit__ and a copy ctor with EMPTY bodies — three hard syntax errors
  // the generator used to happily write out. The usual cause is a missing or
  // misspelled [structs.<name>.fields] table, which otherwise fails much later
  // and much less legibly, at `mojo build`.
  if (fieldEntries.length === 0) {
    fail(`struct "${name}" declares no fields — add a [structs.${name}.fields] table (or drop the struct and use the "object" token for an untyped object).`);
  }

  // --- Struct definition ---
  out.push(`struct ${structName}(Movable, Copyable):`);
  for (const [fName, fType] of fieldEntries) {
    validateIdentifier(fName, `[structs.${name}] field "${fName}"`);
    // The old warn-and-continue here was a lie: the loops below dereference
    // STRUCT_FIELD_MAP[...] unguarded, so an unknown field type crashed the
    // generator with a raw TypeError three functions later.
    if (fType.endsWith('?')) {
      fail(`struct "${name}" field "${fName}": optional struct fields ("${fType}") are not supported — the generated from_js reads every field unconditionally and the .d.ts would emit it as required anyway`);
    }
    const info = STRUCT_FIELD_MAP[fType];
    if (!info) {
      fail(`struct "${name}" field "${fName}": unknown field type "${fType}" (valid: ${Object.keys(STRUCT_FIELD_MAP).join(', ')})`);
    }
    out.push(`    var ${fName}: ${info.mojoType}`);
  }
  out.push('');

  // __init__
  const initParams = fieldEntries.map(([fName, fType]) => {
    const info = STRUCT_FIELD_MAP[fType.replace(/\?$/, '')];
    return `${fName}: ${info.mojoType}`;
  }).join(', ');
  out.push(`    def __init__(out self, ${initParams}):`);
  for (const [fName] of fieldEntries) {
    out.push(`        self.${fName} = ${fName}`);
  }
  out.push('');

  // __moveinit__
  out.push('    def __moveinit__(out self, deinit take: Self):');
  for (const [fName, fType] of fieldEntries) {
    const info = STRUCT_FIELD_MAP[fType.replace(/\?$/, '')];
    // String needs transfer, primitive types don't
    if (info.mojoType === 'String') {
      out.push(`        self.${fName} = take.${fName}^`);
    } else {
      out.push(`        self.${fName} = take.${fName}`);
    }
  }
  out.push('');

  // copy constructor
  out.push('    def __init__(out self, *, copy: Self):');
  for (const [fName] of fieldEntries) {
    out.push(`        self.${fName} = copy.${fName}`);
  }
  out.push('');

  // --- from_js converter ---
  // Field locals carry a `_f_` prefix. Emitting them under the bare field name
  // meant a field called `obj` redeclared this function's own `var obj` and
  // then read the next field's property off a Float64; `val`, `b` and `env`
  // shadowed the parameters the same way. The prefix is injective, so no field
  // name can collide with the converter's own identifiers or with each other.
  out.push(`def ${name}_from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> ${structName}:`);
  out.push('    var obj = JsObject(val)');
  for (const [fName, fType] of fieldEntries) {
    const baseType = fType.replace(/\?$/, '');
    const info = STRUCT_FIELD_MAP[baseType];
    out.push(`    var _f_${fName} = ${info.fromJs('b', 'env', `obj.get_named_property(b, env, "${fName}")`)}`);
  }
  const ctorArgs = fieldEntries.map(([fName]) => `_f_${fName}`).join(', ');
  out.push(`    return ${structName}(${ctorArgs})`);
  out.push('');

  // --- to_js converter ---
  out.push(`def ${name}_to_js(b: Bindings, env: NapiEnv, data: ${structName}) raises -> NapiValue:`);
  out.push('    var obj = JsObject.create(b, env)');
  for (const [fName, fType] of fieldEntries) {
    const baseType = fType.replace(/\?$/, '');
    const info = STRUCT_FIELD_MAP[baseType];
    out.push(`    obj.set_property(b, env, "${fName}", ${info.toJs('b', 'env', `data.${fName}`)})`);
  }
  out.push('    return obj.value');

  return out.join('\n');
}

// --- Main ---
function main() {
  let declText;
  try {
    declText = readFileSync(DECL_PATH, 'utf8');
  } catch {
    console.log(`No declaration file found at ${DECL_PATH}`);
    console.log('Create src/exports.toml with function declarations to generate callbacks.');
    console.log('');
    console.log('Example:');
    console.log('[functions.add]');
    console.log('js_name = "add"');
    console.log('args = ["number", "number"]');
    console.log('returns = "number"');
    console.log('body = """');
    console.log('var a = JsNumber.from_napi_value(env, args[0])');
    console.log('var b = JsNumber.from_napi_value(env, args[1])');
    console.log('return JsNumber.create(env, a + b).value');
    console.log('"""');
    process.exit(0);
  }

  const decl = parseTOML(declText);
  const functions = decl.functions || {};
  const classes = decl.classes || {};
  const structs = decl.structs || {};
  const funcEntries = Object.entries(functions);
  const classEntries = Object.entries(classes);
  const structEntries = Object.entries(structs);

  // Register struct types as valid TYPE_MAP entries before resolveType is called
  registerStructTypes(structs);

  if (funcEntries.length === 0 && classEntries.length === 0 && structEntries.length === 0) {
    console.log('No functions, classes, or structs declared in exports.toml');
    process.exit(0);
  }

  const hasClasses = classEntries.length > 0;
  const asyncEntries = funcEntries.filter(([, d]) => d.async === 'true' || d.async === true);
  const syncEntries = funcEntries.filter(([, d]) => !(d.async === 'true' || d.async === true));
  const hasAsync = asyncEntries.length > 0;
  const hasNPlusArgs = funcEntries.some(([, d]) => (d.args || []).length >= 5) ||
    classEntries.some(([, d]) => (d.constructor_args || []).length >= 5 ||
      Object.values(d.instance_methods || {}).some(m => (m.args || []).length >= 5) ||
      Object.values(d.static_methods || {}).some(m => (m.args || []).length >= 5));

  // Detect whether any function OR class member uses number[] / string[]
  // types. This scan must cover the same declaration surface as the emitters
  // do — it used to scan functions only, so a class method with
  // args = ["number[]"] emitted from_js_array_f64(...) with no import.
  const classMemberDecls = classEntries.flatMap(([, d]) => [
    { args: d.constructor_args || [] },
    ...Object.values(d.instance_methods || {}),
    ...Object.values(d.static_methods || {}),
    ...Object.values(d.getters || {}),
    ...Object.values(d.setters || {}),
  ]);
  const allTypeTokens = [...funcEntries.map(([, d]) => d), ...classMemberDecls].flatMap((d) =>
    [...(d.args || []), d.returns || ''].map(t => String(t).replace(/\?$/, ''))
  );
  const needsF64Array = allTypeTokens.includes('number[]');
  const needsStrArray = allTypeTokens.includes('string[]');
  const needsConvertImport = needsF64Array || needsStrArray;
  const needsNullReturn = funcEntries.some(([, d]) => (d.returns || '').endsWith('?'));

  // Generate output
  const output = [];
  output.push('## src/generated/callbacks.mojo — AUTO-GENERATED by scripts/generate-addon.mjs');
  output.push('## Do not edit manually. Regenerate with: node scripts/generate-addon.mjs');
  output.push('');
  output.push('from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER, NAPI_TYPE_BOOLEAN, NAPI_TYPE_OBJECT');
  if (hasAsync) {
    output.push('from napi.types import NapiDeferred, NapiAsyncWork, NapiStatus, NAPI_OK');
  }
  output.push('from napi.bindings import Bindings');
  output.push('from napi.framework.js_string import JsString');
  output.push('from napi.framework.js_number import JsNumber');
  output.push('from napi.framework.js_boolean import JsBoolean');
  output.push('from napi.framework.js_int32 import JsInt32');
  output.push('from napi.framework.js_uint32 import JsUInt32');
  output.push('from napi.framework.js_int64 import JsInt64');
  output.push('from napi.framework.js_undefined import JsUndefined');
  output.push('from napi.framework.args import CbArgs');
  output.push('from napi.framework.js_value import js_typeof, js_type_name, js_is_array');
  output.push('from napi.error import throw_js_error, throw_js_type_error_dynamic');
  if (hasClasses) {
    output.push('from napi.framework.register import fn_ptr, ModuleBuilder, ClassBuilder');
  } else {
    output.push('from napi.framework.register import fn_ptr, ModuleBuilder');
  }
  output.push('from napi.framework.js_object import JsObject');
  output.push('from napi.framework.js_array import JsArray');
  if (hasAsync || hasNPlusArgs) {
    output.push('from std.memory.alloc import unsafe_alloc');
  }
  if (hasAsync) {
    output.push('from napi.framework.async_work import AsyncWork, AsyncWorkResult');
  }
  if (needsNullReturn) {
    output.push('from napi.framework.js_null import JsNull');
  }
  // Auto-import convert helpers when number[] / string[] types are used
  if (needsConvertImport) {
    const importNames = [];
    if (needsF64Array) importNames.push('from_js_array_f64', 'to_js_array_f64');
    if (needsStrArray) importNames.push('from_js_array_str', 'to_js_array_str');
    output.push(`from napi.framework.convert import ${importNames.join(', ')}`);
  }
  // Extra imports for mojo_fn declarations (user-defined pure Mojo functions)
  const extraImports = decl.extra_imports || [];
  for (const imp of (Array.isArray(extraImports) ? extraImports : [extraImports])) {
    output.push(imp);
  }
  // Import struct types and converters from generated.structs
  if (structEntries.length > 0) {
    const structImports = [];
    for (const [sName] of structEntries) {
      const pascalName = snakeToPascal(sName);
      structImports.push(`${pascalName}Data`);
      structImports.push(`${sName}_from_js`);
      structImports.push(`${sName}_to_js`);
    }
    output.push(`from generated.structs import ${structImports.join(', ')}`);
  }
  output.push('');

  // Generate sync function callbacks
  for (const [name, funcDecl] of syncEntries) {
    output.push(`# ${funcDecl.js_name || name}`);
    output.push(generateCallback(name, funcDecl));
    output.push('');
  }

  // Generate async function callbacks (data struct + 3 callbacks each)
  for (const [name, funcDecl] of asyncEntries) {
    output.push(`# ${funcDecl.js_name || name} (async)`);
    output.push(generateAsyncFunction(name, funcDecl));
    output.push('');
  }

  // Generate class callbacks
  for (const [cName, cDecl] of classEntries) {
    const jsName = cDecl.js_name || cName;
    output.push(`# ${jsName} class — constructor`);
    output.push(generateClassConstructor(cName, cDecl));
    output.push('');
    for (const [mName, mDecl] of Object.entries(cDecl.instance_methods || {})) {
      output.push(`# ${jsName}.${mName} (instance method)`);
      output.push(generateClassMethod(cName, mName, mDecl));
      output.push('');
    }
    for (const [gName, gDecl] of Object.entries(cDecl.getters || {})) {
      output.push(`# ${jsName}.${gName} (getter)`);
      output.push(generateClassGetter(cName, gName, gDecl));
      output.push('');
    }
    for (const [sName, sDecl] of Object.entries(cDecl.setters || {})) {
      output.push(`# ${jsName}.${sName} (setter)`);
      output.push(generateClassSetter(cName, sName, sDecl));
      output.push('');
    }
    for (const [smName, smDecl] of Object.entries(cDecl.static_methods || {})) {
      output.push(`# ${jsName}.${smName} (static method)`);
      output.push(generateClassStaticMethod(cName, smName, smDecl));
      output.push('');
    }
  }

  // Generate registration helper
  output.push('');
  output.push('## register_generated — register all generated functions and classes');
  output.push('##');
  output.push('## Call from register_module after creating the ModuleBuilder:');
  output.push('##   register_generated(m)');
  output.push('def register_generated(mut m: ModuleBuilder) raises:');
  // All functions (sync + async) register via m.method
  output.push(generateRegistration(functions));
  if (hasClasses) {
    output.push(generateClassRegistration(classes));
  }

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT_PATH, output.join('\n') + '\n');

  // ALWAYS write structs.mojo, even with zero structs declared. Writing it
  // conditionally left a stale checked-in structs.mojo surviving a clean
  // `git diff` after the last [structs.*] section was removed — the drift
  // gate can only catch what the generator actually rewrites.
  const structOutput = [];
  structOutput.push('## src/generated/structs.mojo — AUTO-GENERATED by scripts/generate-addon.mjs');
  structOutput.push('## Do not edit manually. Regenerate with: node scripts/generate-addon.mjs');
  structOutput.push('');
  if (structEntries.length > 0) {
    structOutput.push('from napi.types import NapiEnv, NapiValue');
    structOutput.push('from napi.bindings import Bindings');
    structOutput.push('from napi.framework.js_string import JsString');
    structOutput.push('from napi.framework.js_number import JsNumber');
    structOutput.push('from napi.framework.js_boolean import JsBoolean');
    structOutput.push('from napi.framework.js_int32 import JsInt32');
    structOutput.push('from napi.framework.js_uint32 import JsUInt32');
    structOutput.push('from napi.framework.js_int64 import JsInt64');
    structOutput.push('from napi.framework.js_object import JsObject');
    structOutput.push('');
    for (const [sName, sDecl] of structEntries) {
      const pascalName = snakeToPascal(sName);
      structOutput.push(`# ${sDecl.js_name || pascalName} struct`);
      structOutput.push(generateStruct(sName, sDecl));
      structOutput.push('');
    }
  } else {
    structOutput.push('# No [structs.*] sections declared in exports.toml.');
    structOutput.push('');
  }
  writeFileSync(STRUCTS_PATH, structOutput.join('\n') + '\n');
  console.log(`Generated ${STRUCTS_PATH} (${structEntries.length} structs)`);

  console.log(`Generated ${OUT_PATH} (${funcEntries.length} functions, ${classEntries.length} classes)`);
}

main();
