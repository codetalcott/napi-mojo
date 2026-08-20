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
    mojoType: 'Float64',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsNumber.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsNumber.create(_b, env, ${expr}).value`,
  },
  string: {
    napi_type: 'NAPI_TYPE_STRING',
    mojoType: 'String',
    type_name: 'string',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsString.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsString.create(_b, env, ${expr}).value`,
  },
  boolean: {
    napi_type: 'NAPI_TYPE_BOOLEAN',
    mojoType: 'Bool',
    type_name: 'boolean',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsBoolean.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsBoolean.create(_b, env, ${expr}).value`,
  },
  // bool: alias for boolean
  bool: {
    napi_type: 'NAPI_TYPE_BOOLEAN',
    mojoType: 'Bool',
    type_name: 'boolean',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsBoolean.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsBoolean.create(_b, env, ${expr}).value`,
  },
  int32: {
    napi_type: 'NAPI_TYPE_NUMBER',
    mojoType: 'Int32',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsInt32.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsInt32.create(_b, env, ${expr}).value`,
  },
  uint32: {
    napi_type: 'NAPI_TYPE_NUMBER',
    mojoType: 'UInt32',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsUInt32.from_napi_value(_b, env, ${argExpr})`,
    create: (expr) => `JsUInt32.create(_b, env, ${expr}).value`,
  },
  int64: {
    napi_type: 'NAPI_TYPE_NUMBER',
    mojoType: 'Int64',
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
  // float64array: a ZERO-COPY view into the JS Float64Array's backing store.
  // The Mojo fn receives a Span aliasing V8 memory — no copy in either
  // direction — so it must not retain the Span beyond the call: the typed
  // array is only guaranteed alive for the duration of the callback.
  // As a return type the Mojo fn hands back a MojoFloat64Array, whose buffer
  // JS adopts (its GC finalizer frees it), so that direction is copy-free too.
  float64array: {
    napi_type: '__IS_FLOAT64ARRAY__',
    type_name: 'Float64Array',
    extract: (varName, argExpr) =>
      `        var _ta_${varName} = JsTypedArray(${argExpr})\n` +
      `        var ${varName} = Span[Float64](unsafe_ptr=_ta_${varName}.data_ptr_float64(_b, env), length=Int(_ta_${varName}.length(_b, env)))`,
    create: (expr) => `${expr}.to_js(_b, env)`,
  },
  // buffer: a zero-copy Span[Byte] view over a Node Buffer, argument-only.
  // There is no Mojo-owned Buffer counterpart to MojoFloat64Array, so
  // `returns = "buffer"` is rejected rather than quietly copying.
  buffer: {
    napi_type: '__IS_BUFFER__',
    type_name: 'Buffer',
    returnUnsupported:
      'there is no Mojo-owned Buffer type to hand back without copying — ' +
      'return "float64array" for numeric output, or build the Buffer in a ' +
      'hand-written callback with JsBuffer',
    extract: (varName, argExpr) =>
      `        var _buf_${varName} = JsBuffer(${argExpr})\n` +
      `        var ${varName} = Span[Byte](unsafe_ptr=_buf_${varName}.data_ptr(_b, env), length=Int(_buf_${varName}.length(_b, env)))`,
    create: (expr) => expr,
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
    const jsName = sDecl.js_name || pascalName;
    TYPE_MAP[name] = {
      napi_type: 'NAPI_TYPE_OBJECT',
      type_name: jsName,
      mojoType: `${pascalName}Data`,
      extract: (varName, argExpr) =>
        `        var ${varName} = ${name}_from_js(_b, env, ${argExpr})`,
      create: (expr) => `${name}_to_js(_b, env, ${expr})`,
    };
    // `<struct>[]` — arrays of structs, via the parametric converters in
    // convert.mojo. Those are generic over ToJsValue/FromJsValue, which the
    // generated struct now implements, so this costs one TYPE_MAP entry
    // rather than a bespoke emitter per struct.
    TYPE_MAP[`${name}[]`] = {
      napi_type: '__IS_ARRAY__',
      type_name: `${jsName}[]`,
      isStructArray: true,
      extract: (varName, argExpr) =>
        `        var ${varName} = from_js_array[${pascalName}Data](_b, env, ${argExpr})`,
      create: (expr) => `to_js_array[${pascalName}Data](_b, env, ${expr})`,
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

// --- Emit the extraction for one argument ---
// For a plain token this is just the TYPE_MAP extract. For a nullable
// converting token (`number?`, a struct) it emits an Optional[T] that is None
// for JS null/undefined and carries a converted value otherwise — with the
// typed check nested INSIDE the null test, so a wrong type still gets the
// descriptive TypeError while null legitimately passes through.
//
// Until this existed the .d.ts said `number | null` while the extract called
// from_napi_value unconditionally, so the advertised null raised at runtime;
// that mismatch was rejected outright rather than shipped, and this is the
// support that replaces the rejection.
function emitArgExtract(lines, jsName, rawType, varName, argExpr, argDesc) {
  const { typeInfo, nullable } = resolveType(rawType);
  if (!nullable || typeInfo.passthrough) {
    lines.push(typeInfo.extract(varName, argExpr));
    return;
  }
  const where = argDesc ? ` for ${argDesc}` : '';
  const t = `_n_${varName}`;
  lines.push(`        var ${varName}: Optional[${typeInfo.mojoType}] = None`);
  lines.push(`        var ${t} = js_typeof(_b, env, ${argExpr})`);
  lines.push(`        if ${t} != NAPI_TYPE_NULL and ${t} != NAPI_TYPE_UNDEFINED:`);
  if (typeInfo.napi_type === '__IS_ARRAY__') {
    lines.push(`            if not js_is_array(_b, env, ${argExpr}):`);
  } else {
    lines.push(`            if ${t} != ${typeInfo.napi_type}:`);
  }
  lines.push(`                throw_js_type_error_dynamic(_b, env, "${jsName}: expected ${typeInfo.type_name} or null${where}, got " + js_type_name(${t}))`);
  lines.push(`                return NapiValue(unsafe_from_address=Int(0))`);
  // The base extract emits at 8 spaces; it lives one level deeper here.
  lines.push(typeInfo.extract(`_v_${varName}`, argExpr).replace(/^ {8}/gm, '            '));
  // Transfer, not copy: a struct or String is not ImplicitlyCopyable, and
  // the temp is dead after this line for every token.
  lines.push(`            ${varName} = _v_${varName}^`);
}

// --- Emit the argument-fetch + type-check preamble ---
// Every emitter (sync, async, class ctor, instance method, static method) used
// to carry its own copy of this chain — five copies that had to be edited in
// lockstep for any new token or arity, and which had already drifted: the
// >=5-arg heap-argv branch exists only in the sync shape, and its `_argv` was
// missing an origin widening for long enough to ship, because nothing
// instantiated it.
//
// `allowVarargs` is the only real difference between the copies. The async and
// class emitters cap at 4 and fail() with their own message before reaching
// here, because their data structs and callback shapes are fixed at that arity.
//
// Arg expressions are deliberately NOT returned: call sites ask
// getArgExpr(i, n), which stays the single definition of the naming rule
// (arg0 at arity 1, args[i] at 2-4, _ai at >=5).
function emitArgPreamble(lines, jsName, args, { allowVarargs = false } = {}) {
  const n = args.length;
  if (n === 0) return;

  if (n === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(_b, env, info)`);
  } else if (n <= 4) {
    const fetch = { 2: 'get_two', 3: 'get_three', 4: 'get_four' }[n];
    lines.push(`        var args = CbArgs.${fetch}(_b, env, info)`);
  } else {
    if (!allowVarargs) {
      fail(`${jsName}: ${n} args declared, but this callback shape supports at most 4`);
    }
    // N >= 5: heap-allocate argv, copy to locals, free immediately before body
    lines.push(`        var _argv = unsafe_alloc[NapiValue](${n})`);
    // get_argv returns the actual argc (discarded — argv is napi-padded with
    // undefined) and needs the explicit origin widening on the alloc'd buffer.
    lines.push(`        _ = CbArgs.get_argv(_b, env, info, ${n}, _argv.as_unsafe_any_origin())`);
    for (let i = 0; i < n; i++) lines.push(`        var _a${i} = _argv[unsafe_offset=${i}]`);
    lines.push(`        _argv.unsafe_free()`);
  }

  // At arity 1 the message reads "expected string, got X" with no position:
  // there is only one argument it could mean. Preserved exactly.
  for (let i = 0; i < n; i++) {
    emitTypeCheck(lines, jsName, args[i], getArgExpr(i, n), n === 1 ? null : `arg ${i + 1}`);
  }
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
  if (nullable && !typeInfo.passthrough && !typeInfo.mojoType) {
    const base = rawType.slice(0, -1);
    fail(
      `${jsName}: nullable argument type "${rawType}"${argDesc ? ` (${argDesc})` : ''} is not supported — ` +
      `"${base}" has no meaningful Optional form (an absent array is an empty one; an absent ` +
      `zero-copy view has no buffer). Nullable arguments work for number, string, boolean, ` +
      `int32, uint32, int64 and declared structs, and any?/object?/array? pass the raw value through.`);
  }
  if (nullable || !typeInfo.napi_type) return;  // nullable: emitArgExtract owns the check
  if (typeInfo.napi_type === '__IS_FLOAT64ARRAY__' || typeInfo.napi_type === '__IS_BUFFER__') {
    // Both read as 'object' to napi_typeof, so each gets a dedicated
    // predicate. data_ptr_float64 additionally raises on the wrong
    // TypedArray subtype (an Int32Array reaching a float64array arg).
    const pred = typeInfo.napi_type === '__IS_BUFFER__'
      ? `JsBuffer.is_buffer(_b, env, ${argExpr})`
      : `JsTypedArray.is_typedarray(_b, env, ${argExpr})`;
    lines.push(`        if not ${pred}:`);
    lines.push(`            throw_js_type_error_dynamic(_b, env, "${jsName}: expected ${typeInfo.type_name}${argDesc ? ' for ' + argDesc : ''}")`);
    lines.push(`            return NapiValue(unsafe_from_address=Int(0))`);
  } else if (typeInfo.napi_type === '__IS_ARRAY__') {
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

  emitArgPreamble(lines, jsName, args, { allowVarargs: true });

  if (mojoFn) {
    // Auto-trampoline: extract Mojo-typed args, call mojoFn, wrap result.
    // mojo_fn takes precedence over body if both are present.
    for (let i = 0; i < args.length; i++) {
      emitArgExtract(lines, jsName, args[i], `mojo_arg${i}`, getArgExpr(i, args.length), args.length === 1 ? null : `arg ${i + 1}`);
    }
    const callArgs = args.map((_, i) => `mojo_arg${i}`).join(', ');
    lines.push(`        var mojo_result = ${mojoFn}(${callArgs})`);
    const returnsNullable = returns.endsWith('?');
    const { typeInfo: retTypeInfo } = resolveType(returns);
    if (retTypeInfo.returnUnsupported) {
      fail(`[functions.${name}] returns "${returns}": ${retTypeInfo.returnUnsupported}`);
    }
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
// `transfer` marks a field that is not ImplicitlyCopyable, so __moveinit__
// must move it rather than copy it.
//
// On `string`: the long-standing rule was that this struct may hold only
// scalars "because the execute callback runs on a worker thread". The two
// constraints that are actually load-bearing on that thread are documented
// elsewhere and are different — no N-API calls, and no dlopen/dlsym (the
// loader lock, which asyncProgress had to be fixed for). Allocating a Mojo
// String is neither: it is malloc underneath, the struct is owned
// exclusively by the async work while it runs, and the completion callback
// (main thread) is ordered after execute by libuv, which is the handoff edge.
// What that reasoning does NOT establish is race-freedom under concurrent
// load; see the note in the PR that introduced it.
const ASYNC_TYPE_MAP = {
  number: { mojoType: 'Float64', zeroVal: '0.0', createExpr: (e) => `JsNumber.create(_b, env, ${e})` },
  int32:  { mojoType: 'Int32',   zeroVal: '0',   createExpr: (e) => `JsInt32.create(_b, env, ${e})` },
  uint32: { mojoType: 'UInt32',  zeroVal: '0',   createExpr: (e) => `JsUInt32.create(_b, env, ${e})` },
  int64:  { mojoType: 'Int64',   zeroVal: '0',   createExpr: (e) => `JsInt64.create(_b, env, ${e})` },
  string: { mojoType: 'String',  zeroVal: 'String()', transfer: true, createExpr: (e) => `JsString.create(_b, env, ${e})` },
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
  const retType = ASYNC_TYPE_MAP[returnsToken];
  const argMojoTypes = args.map((a, idx) => {
    const tok = a.replace(/\?$/, '');
    if (!ASYNC_TYPE_MAP[tok]) {
      fail(`async function "${name}": arg[${idx}] type "${tok}" is not supported for async (worker-thread data structs allow only: ${Object.keys(ASYNC_TYPE_MAP).join(', ')})`);
    }
    return ASYNC_TYPE_MAP[tok];
  });

  const out = [];

  // 1. Data struct (Movable). A `string` field brings a destructor with it;
  // that destructor runs in the complete callback on the MAIN thread, where
  // the struct is deinitialized, not on the worker.
  out.push(`struct ${structName}(Movable):`);
  // NapiDeferred/NapiAsyncWork used to hide AnyOrigin here, which
  // dev2026062206 rejects in struct fields, and the generator emitted
  // @__allow_legacy_any_origin_fields as the stopgap. Both aliases are
  // MutUntrackedOrigin now, so the fields are legal as written and the
  // decorator is gone — see docs/plan-origin-migration.md.
  out.push(`    var deferred: NapiDeferred`);
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
    out.push(`        self.input${i} = take.input${i}${argMojoTypes[i].transfer ? '^' : ''}`);
  }
  out.push(`        self.result = take.result${retType.transfer ? '^' : ''}`);

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
  emitArgPreamble(out, jsName, args, { allowVarargs: true });
  for (let i = 0; i < args.length; i++) {
    const info = TYPE_MAP[args[i].replace(/\?$/, '')] || TYPE_MAP.number;
    out.push(info.extract(`input${i}`, getArgExpr(i, args.length)));
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

// --- Native class state (`state = "<struct>"`) ---
// Without this, a generated class has nowhere to keep Mojo data: the demo's
// ExamplePoint stashes its fields as JS properties on `this`, which costs a
// napi call per access and cannot hold anything that is not a JS value.
//
// With it, the class wraps a heap-allocated instance of a declared struct and
// every member reaches it through the type-tagged unwrap. The tag is what
// makes borrowing a method onto a foreign instance a TypeError instead of
// memory corruption (see the class type-tagging note in CLAUDE.md), so it is
// generated, not optional.
//
// The tag halves are derived from the class name by FNV-1a rather than picked
// randomly, because the generator must produce identical output on every run —
// the drift gate compares bytes.
function classTag(className) {
  const fnv = (seed, s) => {
    let h = BigInt(seed);
    const prime = 1099511628211n;
    const mask = (1n << 64n) - 1n;
    for (const ch of `${s}`) {
      h = (h ^ BigInt(ch.codePointAt(0))) & mask;
      h = (h * prime) & mask;
    }
    return h;
  };
  const lower = fnv('14695981039346656037', `napi-mojo:${className}:lower`);
  const upper = fnv('14695981039346656037', `napi-mojo:${className}:upper`);
  const hex = (v) => `0x${v.toString(16).toUpperCase().padStart(16, '0')}`;
  return { lower: hex(lower), upper: hex(upper) };
}

// Resolve a class's `state` declaration to the generated struct type, failing
// with a legible message rather than emitting a reference to a type that does
// not exist.
function resolveClassState(className, decl, structs) {
  const stateName = decl.state;
  if (!stateName) return null;
  if (!structs || !structs[stateName]) {
    fail(`class "${className}": state = "${stateName}" does not match any [structs.*] declaration`);
  }
  return {
    name: stateName,
    mojoType: `${snakeToPascal(stateName)}Data`,
    tag: classTag(className),
  };
}

// Generate the constructor callback for a class
function generateClassConstructor(className, decl, structs) {
  const jsName = decl.js_name || className;
  const ctorArgs = decl.constructor_args || [];
  const ctorMojoFn = decl.constructor_mojo_fn;
  const state = resolveClassState(className, decl, structs);
  if (ctorMojoFn && !state) {
    fail(`class "${className}": constructor_mojo_fn requires state = "<struct>" — the returned value needs somewhere to live`);
  }
  if (state && !ctorMojoFn) {
    fail(`class "${className}": state = "${state.name}" requires constructor_mojo_fn to build it`);
  }
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

  emitArgPreamble(lines, jsName, ctorArgs);

  if (state) {
    // Build the state with the user's pure fn, heap-allocate it, and hand
    // ownership to JS via wrap_native. On a wrap failure ownership comes back
    // to us, so the data is freed here rather than leaked or double-freed.
    for (let i = 0; i < ctorArgs.length; i++) {
      emitArgExtract(lines, jsName, ctorArgs[i], `mojo_arg${i}`, getArgExpr(i, ctorArgs.length), ctorArgs.length === 1 ? null : `arg ${i + 1}`);
    }
    const callArgs = ctorArgs.map((_, i) => `mojo_arg${i}`).join(', ');
    lines.push(`        var _state = ${ctorMojoFn}(${callArgs})`);
    lines.push(`        var _data_ptr = unsafe_alloc[${state.mojoType}](1)`);
    lines.push(`        _data_ptr.unsafe_write(_state^)`);
    lines.push(`        var _fin_ref = ${className}_finalize`);
    lines.push(`        try:`);
    lines.push(`            wrap_native(`);
    lines.push(`                _b,`);
    lines.push(`                env,`);
    lines.push(`                this_val,`);
    lines.push(`                _data_ptr.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),`);
    lines.push(`                fn_ptr(_fin_ref),`);
    lines.push(`                NapiTypeTag(${state.tag.lower}, ${state.tag.upper}),`);
    lines.push(`            )`);
    lines.push(`        except e:`);
    lines.push(`            _data_ptr.unsafe_deinit_pointee()`);
    lines.push(`            _data_ptr.unsafe_free()`);
    lines.push(`            raise e^`);
    lines.push(`        return this_val`);
    lines.push(`    except:`);
    lines.push(`        throw_js_error(env, "${jsName} constructor failed")`);
    lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);
    return lines.join('\n');
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

// The GC finalizer for a stateful class: JS owns the allocation after
// wrap_native, so this is the only place it is freed.
function generateClassFinalizer(className, state) {
  return [
    `def ${className}_finalize(`,
    `    env: NapiEnv,`,
    `    data: OpaquePointer[MutAnyOrigin],`,
    `    hint: OpaquePointer[MutAnyOrigin],`,
    `):`,
    `    var ptr = data.unsafe_bitcast[${state.mojoType}]()`,
    `    ptr.unsafe_deinit_pointee()`,
    `    ptr.unsafe_free()`,
  ].join('\n');
}

// Generate an instance method callback (has access to this_val)
function generateClassMethod(className, methodName, decl, structs, classDecl) {
  const jsName = decl.js_name || methodName;
  const fnName = `${className}_${methodName}_fn`;
  const args = decl.args || [];
  const mojoFn = decl.mojo_fn;
  const state = resolveClassState(className, classDecl || {}, structs);
  if (mojoFn && !state) {
    fail(`class method "${className}.${methodName}": mojo_fn requires the class to declare state = "<struct>" — there is nothing for the function to receive`);
  }
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

  emitArgPreamble(lines, jsName, args);

  if (mojoFn) {
    // The type-tagged unwrap is what makes borrowing this method onto a
    // foreign wrapped instance a TypeError rather than a reinterpret.
    lines.push(`        var _state = unwrap_native_from_this[${state.mojoType}](`);
    lines.push(`            _b, env, this_val, NapiTypeTag(${state.tag.lower}, ${state.tag.upper})`);
    lines.push(`        )`);
    for (let i = 0; i < args.length; i++) {
      emitArgExtract(lines, jsName, args[i], `mojo_arg${i}`, getArgExpr(i, args.length), args.length === 1 ? null : `arg ${i + 1}`);
    }
    const callArgs = ['_state[]', ...args.map((_, i) => `mojo_arg${i}`)].join(', ');
    const returns = decl.returns || 'any';
    const returnsNullable = returns.endsWith('?');
    const { typeInfo: retTypeInfo } = resolveType(returns);
    if (retTypeInfo.returnUnsupported) {
      fail(`class method "${className}.${methodName}" returns "${returns}": ${retTypeInfo.returnUnsupported}`);
    }
    lines.push(`        var mojo_result = ${mojoFn}(${callArgs})`);
    if (returnsNullable) {
      lines.push(`        if not mojo_result:`);
      lines.push(`            return JsNull.create(_b, env).value`);
      lines.push(`        return ${retTypeInfo.create('mojo_result.value()')}`);
    } else {
      lines.push(`        return ${retTypeInfo.create('mojo_result')}`);
    }
  } else {
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

// Convert camelCase to snake_case for Mojo identifiers
function camelToSnake(s) {
  return s.replace(/([A-Z])/g, m => '_' + m.toLowerCase());
}

// Generate a static method callback (no this_val)
function generateClassStaticMethod(className, methodName, decl) {
  const mojoFn = decl.mojo_fn;
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

  emitArgPreamble(lines, jsName, args);

  if (mojoFn) {
    // No unwrap and no state: a static method has no instance, so its mojo_fn
    // is an ordinary pure function over the declared args — the same shape as
    // a top-level [functions.*] mojo_fn. That is why this needs no state
    // declaration on the class, unlike instance methods, getters and setters.
    for (let i = 0; i < args.length; i++) {
      emitArgExtract(lines, jsName, args[i], `mojo_arg${i}`, getArgExpr(i, args.length), args.length === 1 ? null : `arg ${i + 1}`);
    }
    const returns = decl.returns || 'any';
    const returnsNullable = returns.endsWith('?');
    const { typeInfo: retTypeInfo } = resolveType(returns);
    if (retTypeInfo.returnUnsupported) {
      fail(`class static method "${className}.${methodName}" returns "${returns}": ${retTypeInfo.returnUnsupported}`);
    }
    lines.push(`        var mojo_result = ${mojoFn}(${args.map((_, i) => `mojo_arg${i}`).join(', ')})`);
    if (returnsNullable) {
      lines.push(`        if not mojo_result:`);
      lines.push(`            return JsNull.create(_b, env).value`);
      lines.push(`        return ${retTypeInfo.create('mojo_result.value()')}`);
    } else {
      lines.push(`        return ${retTypeInfo.create('mojo_result')}`);
    }
  } else {
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

// Generate a setter callback (has access to this_val + val)
function generateClassSetter(className, propName, decl, structs, classDecl) {
  const mojoFn = decl.mojo_fn;
  const state = resolveClassState(className, classDecl || {}, structs);
  if (mojoFn && !state) {
    fail(`class setter "${className}.${propName}": mojo_fn requires the class to declare state = "<struct>" — a setter that cannot reach the instance has nothing to set`);
  }
  const fnName = `${className}_set_${propName}_fn`;
  const body = decl.body || 'return val';

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);
  lines.push(`        var val = CbArgs.get_one(_b, env, info)`);

  if (mojoFn) {
    // Type-tagged, exactly as instance methods: a setter borrowed onto a
    // foreign wrapped instance must be a TypeError, not a reinterpret.
    lines.push(`        var _state = unwrap_native_from_this[${state.mojoType}](`);
    lines.push(`            _b, env, this_val, NapiTypeTag(${state.tag.lower}, ${state.tag.upper})`);
    lines.push(`        )`);
    // The incoming value is not an argv entry — it arrives via get_one — so the
    // arity chain in emitArgPreamble does not apply, but the CHECK does: a
    // setter fed the wrong type should say "expected number, got string", not
    // fall through to the except: block and report "total setter failed".
    // emitTypeCheck is the same one every argument goes through.
    emitTypeCheck(lines, `${propName} setter`, decl.type || 'any', 'val', null);
    emitArgExtract(lines, `${propName} setter`, decl.type || 'any', 'mojo_val', 'val', null);
    // The pure function mutates state through `mut` and returns nothing.
    lines.push(`        ${mojoFn}(_state[], mojo_val)`);
    // JS discards a setter's return value; hand back the value we already hold
    // rather than spending an N-API call on undefined.
    lines.push(`        return val`);
  } else {
    const bodyLines = body.split('\n');
    for (const bl of bodyLines) {
      lines.push(`        ${bl}`);
    }
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${propName} setter failed")`);
  lines.push(`        return NapiValue(unsafe_from_address=Int(0))`);

  return lines.join('\n');
}

// Generate a getter callback (has access to this_val, no args)
function generateClassGetter(className, getterName, decl, structs, classDecl) {
  const fnName = `${className}_get_${getterName}_fn`;
  const mojoFn = decl.mojo_fn;
  const state = resolveClassState(className, classDecl || {}, structs);
  if (mojoFn && !state) {
    fail(`class getter "${className}.${getterName}": mojo_fn requires the class to declare state = "<struct>"`);
  }
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  const lines = [];
  lines.push(`def ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);

  if (mojoFn) {
    lines.push(`        var _state = unwrap_native_from_this[${state.mojoType}](`);
    lines.push(`            _b, env, this_val, NapiTypeTag(${state.tag.lower}, ${state.tag.upper})`);
    lines.push(`        )`);
    const { typeInfo: retTypeInfo } = resolveType(decl.returns || 'any');
    lines.push(`        var mojo_result = ${mojoFn}(_state[])`);
    lines.push(`        return ${retTypeInfo.create('mojo_result')}`);
  } else {
    const bodyLines = body.split('\n');
    for (const bl of bodyLines) {
      lines.push(`        ${bl}`);
    }
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
  out.push(`struct ${structName}(Movable, Copyable, ToJsValue, FromJsValue):`);
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

  // --- Conversion trait conformance ---
  // Delegates to the free functions below. Implementing the traits is what
  // makes <struct>[] work: to_js_array/from_js_array are generic over them,
  // so arrays of structs need no per-struct emitter.
  out.push(`    def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:`);
  out.push(`        return ${name}_to_js(b, env, self)`);
  out.push('');
  out.push(`    @staticmethod`);
  out.push(`    def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:`);
  out.push(`        return ${name}_from_js(b, env, val)`);
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
  // Raw (unstripped) argument tokens: a nullable converting arg emits a
  // null/undefined comparison, which needs those two constants imported.
  const rawArgTokens = [...funcEntries.map(([, d]) => d), ...classMemberDecls]
    .flatMap((d) => [...(d.args || []), ...(d.constructor_args || [])].map(String));
  const needsNullableArg = rawArgTokens.some((t) => {
    if (!t.endsWith('?')) return false;
    const info = TYPE_MAP[t.slice(0, -1)];
    return Boolean(info && info.mojoType);
  });
  const needsClassState = Object.values(classes).some((c) => c && c.state);
  const needsStructArray = allTypeTokens.some((t) => (TYPE_MAP[t] || {}).isStructArray);
  const needsF64TypedArray = allTypeTokens.includes('float64array');
  const needsBuffer = allTypeTokens.includes('buffer');

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
  if (needsNullableArg) {
    output.push('from napi.types import NAPI_TYPE_NULL, NAPI_TYPE_UNDEFINED');
  }
  if (needsF64TypedArray) {
    output.push('from napi.framework.js_typedarray import JsTypedArray');
    output.push('from napi.framework.js_mojo_array import MojoFloat64Array');
  }
  if (needsBuffer) {
    output.push('from napi.framework.js_buffer import JsBuffer');
  }
  // Auto-import convert helpers when number[] / string[] types are used
  if (needsConvertImport) {
    const importNames = [];
    if (needsF64Array) importNames.push('from_js_array_f64', 'to_js_array_f64');
    if (needsStrArray) importNames.push('from_js_array_str', 'to_js_array_str');
    // (struct arrays use the parametric pair, imported separately below)
    output.push(`from napi.framework.convert import ${importNames.join(', ')}`);
  }
  if (needsStructArray) {
    output.push('from napi.framework.convert import from_js_array, to_js_array');
  }
  if (needsClassState) {
    output.push('from napi.types import NapiTypeTag');
    output.push('from napi.framework.js_class import wrap_native, unwrap_native_from_this');
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
    const cState = resolveClassState(cName, cDecl, structs);
    if (cState) {
      output.push(`# ${jsName} class — GC finalizer for its native state`);
      output.push(generateClassFinalizer(cName, cState));
      output.push('');
    }
    output.push(`# ${jsName} class — constructor`);
    output.push(generateClassConstructor(cName, cDecl, structs));
    output.push('');
    for (const [mName, mDecl] of Object.entries(cDecl.instance_methods || {})) {
      output.push(`# ${jsName}.${mName} (instance method)`);
      output.push(generateClassMethod(cName, mName, mDecl, structs, cDecl));
      output.push('');
    }
    for (const [gName, gDecl] of Object.entries(cDecl.getters || {})) {
      output.push(`# ${jsName}.${gName} (getter)`);
      output.push(generateClassGetter(cName, gName, gDecl, structs, cDecl));
      output.push('');
    }
    for (const [sName, sDecl] of Object.entries(cDecl.setters || {})) {
      output.push(`# ${jsName}.${sName} (setter)`);
      output.push(generateClassSetter(cName, sName, sDecl, structs, cDecl));
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
    structOutput.push('from napi.framework.convert import ToJsValue, FromJsValue');
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
