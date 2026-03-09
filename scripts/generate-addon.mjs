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

const __dirname = dirname(fileURLToPath(import.meta.url));
const DECL_PATH = join(__dirname, '..', 'src', 'exports.toml');
const OUT_DIR = join(__dirname, '..', 'src', 'generated');
const OUT_PATH = join(OUT_DIR, 'callbacks.mojo');

// --- Simple TOML parser (handles our subset: sections, key=value, multiline strings) ---
function parseTOML(text) {
  const result = {};
  let current = result;
  const path = [];

  const lines = text.split('\n');
  let i = 0;

  while (i < lines.length) {
    const line = lines[i].trim();
    i++;

    // Skip comments and empty lines
    if (!line || line.startsWith('#')) continue;

    // Section header: [a.b.c]
    const sectionMatch = line.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      const parts = sectionMatch[1].split('.');
      current = result;
      for (const part of parts) {
        if (!current[part]) current[part] = {};
        current = current[part];
      }
      continue;
    }

    // Key = value
    const kvMatch = line.match(/^(\w+)\s*=\s*(.*)$/);
    if (kvMatch) {
      const key = kvMatch[1];
      let value = kvMatch[2].trim();

      // Multiline string (triple quotes)
      if (value.startsWith('"""')) {
        value = value.slice(3);
        const bodyLines = [value];
        while (i < lines.length) {
          const nextLine = lines[i];
          i++;
          if (nextLine.trim().endsWith('"""')) {
            bodyLines.push(nextLine.trim().slice(0, -3));
            break;
          }
          bodyLines.push(nextLine);
        }
        current[key] = bodyLines.join('\n').trim();
        continue;
      }

      // Single-line string (quoted)
      if (value.startsWith('"') && value.endsWith('"')) {
        current[key] = value.slice(1, -1);
        continue;
      }

      // Array: ["a", "b"]
      if (value.startsWith('[')) {
        const items = value.slice(1, -1).split(',').map(s => s.trim().replace(/"/g, ''));
        current[key] = items.filter(Boolean);
        continue;
      }

      // Number
      if (/^\d+$/.test(value)) {
        current[key] = parseInt(value);
        continue;
      }

      current[key] = value;
    }
  }

  return result;
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
    type_name: 'object',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
  // array: validate with js_is_array (typeof returns 'object' for arrays)
  array: {
    napi_type: '__IS_ARRAY__', // special sentinel — emits js_is_array check
    type_name: 'array',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
  any: {
    napi_type: null, // no type check
    type_name: 'any',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
};

// --- Resolve type, handling nullable suffix ('?') ---
// Returns { typeInfo, nullable } where nullable=true skips the type check.
function resolveType(rawType) {
  const nullable = rawType.endsWith('?');
  const baseType = nullable ? rawType.slice(0, -1) : rawType;
  return { typeInfo: TYPE_MAP[baseType] || TYPE_MAP.any, nullable };
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
  if (nullable || !typeInfo.napi_type) return;
  if (typeInfo.napi_type === '__IS_ARRAY__') {
    lines.push(`        if not js_is_array(_b, env, ${argExpr}):`);
    lines.push(`            throw_js_type_error_dynamic(_b, env, "${jsName}: expected array${argDesc ? ' for ' + argDesc : ''}")`);
    lines.push(`            return NapiValue()`);
  } else {
    const tVar = `_t_${argExpr.replace(/[^a-z0-9]/gi, '_')}`;
    lines.push(`        var ${tVar} = js_typeof(_b, env, ${argExpr})`);
    lines.push(`        if ${tVar} != ${typeInfo.napi_type}:`);
    lines.push(`            throw_js_type_error_dynamic(_b, env, "${jsName}: expected ${typeInfo.type_name}${argDesc ? ' for ' + argDesc : ''}, got " + js_type_name(${tVar}))`);
    lines.push(`            return NapiValue()`);
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

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
    lines.push(`        var _argv = alloc[NapiValue](${n})`);
    lines.push(`        CbArgs.get_argv(_b, env, info, ${n}, _argv)`);
    for (let i = 0; i < n; i++) lines.push(`        var _a${i} = _argv[${i}]`);
    lines.push(`        _argv.free()`);
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
    const { typeInfo: retTypeInfo } = resolveType(returns);
    lines.push(`        return ${retTypeInfo.create('mojo_result')}`);
  } else if (body) {
    // Insert body (indented to 8 spaces)
    const bodyLines = body.split('\n');
    for (const bl of bodyLines) {
      lines.push(`        ${bl}`);
    }
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${jsName} failed")`);
  lines.push(`        return NapiValue()`);

  return lines.join('\n');
}

// --- Async function generation ---

// Mojo types for async data struct fields (only numeric types allowed — no destructors)
const ASYNC_TYPE_MAP = {
  number: { mojoType: 'Float64', zeroVal: '0.0', createExpr: (e) => `JsNumber.create(env, ${e})` },
  int32:  { mojoType: 'Int32',   zeroVal: '0',   createExpr: (e) => `JsInt32.create(env, ${e})` },
  uint32: { mojoType: 'UInt32',  zeroVal: '0',   createExpr: (e) => `JsUInt32.create(env, ${e})` },
  int64:  { mojoType: 'Int64',   zeroVal: '0',   createExpr: (e) => `JsInt64.create(env, ${e})` },
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

  const retType = ASYNC_TYPE_MAP[returnsToken] || ASYNC_TYPE_MAP.number;
  const argMojoTypes = args.map(a => ASYNC_TYPE_MAP[a.replace(/\?$/, '')] || ASYNC_TYPE_MAP.number);

  const out = [];

  // 1. Data struct (Movable — no destructors, safe to pass across threads)
  out.push(`struct ${structName}(Movable):`);
  out.push(`    var deferred: NapiDeferred`);
  out.push(`    var work: NapiAsyncWork`);
  for (let i = 0; i < args.length; i++) {
    out.push(`    var input${i}: ${argMojoTypes[i].mojoType}`);
  }
  out.push(`    var result: ${retType.mojoType}`);
  out.push('');
  const initParams = argMojoTypes.map((t, i) => `input${i}: ${t.mojoType}`).join(', ');
  out.push(`    fn __init__(out self${initParams ? ', ' + initParams : ''}):`);
  out.push(`        self.deferred = NapiDeferred()`);
  out.push(`        self.work = NapiAsyncWork()`);
  for (let i = 0; i < args.length; i++) {
    out.push(`        self.input${i} = input${i}`);
  }
  out.push(`        self.result = ${retType.zeroVal}`);
  out.push('');
  out.push(`    fn __moveinit__(out self, deinit take: Self):`);
  out.push(`        self.deferred = take.deferred`);
  out.push(`        self.work = take.work`);
  for (let i = 0; i < args.length; i++) {
    out.push(`        self.input${i} = take.input${i}`);
  }
  out.push(`        self.result = take.result`);

  // 2. Execute callback (worker thread — no N-API calls allowed)
  out.push('');
  out.push(`fn ${name}_execute(env: NapiEnv, data: OpaquePointer[MutAnyOrigin]):`);
  out.push(`    var ptr = data.bitcast[${structName}]()`);
  for (const el of executeBody.split('\n')) {
    if (el.trim()) out.push(`    ${el.trim()}`);
  }

  // 3. Complete callback (main thread — resolve/reject, then free heap)
  out.push('');
  out.push(`fn ${name}_complete(env: NapiEnv, status: NapiStatus, data: OpaquePointer[MutAnyOrigin]):`);
  out.push(`    var ptr = data.bitcast[${structName}]()`);
  out.push(`    try:`);
  out.push(`        if status == NAPI_OK:`);
  out.push(`            var rv = ${retType.createExpr('ptr[].result')}`);
  out.push(`            AsyncWork.resolve(env, ptr[].deferred, ptr[].work, rv.value)`);
  out.push(`        else:`);
  out.push(`            AsyncWork.reject_with_error(env, ptr[].deferred, ptr[].work, "${jsName} failed")`);
  out.push(`    except:`);
  out.push(`        pass`);
  out.push(`    ptr.destroy_pointee()`);
  out.push(`    ptr.free()`);

  // 4. Entry-point callback (standard N-API: type-check, alloc, queue, return promise)
  out.push('');
  out.push(`fn ${name}_fn(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
  out.push(`        var data_ptr = alloc[${structName}](1)`);
  out.push(`        data_ptr.init_pointee_move(${structName}(${inputArgs}))`);
  out.push(`        var exec_ref = ${name}_execute`);
  out.push(`        var comp_ref = ${name}_complete`);
  out.push(`        var aw = AsyncWork.queue(_b, env, "${jsName}", data_ptr.bitcast[NoneType](), fn_ptr(exec_ref), fn_ptr(comp_ref))`);
  out.push(`        data_ptr[].deferred = aw.deferred`);
  out.push(`        data_ptr[].work = aw.work`);
  out.push(`        return aw.value`);
  out.push(`    except:`);
  out.push(`        throw_js_error(env, "${jsName} failed")`);
  out.push(`        return NapiValue()`);

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

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
  lines.push(`        return NapiValue()`);

  return lines.join('\n');
}

// Generate an instance method callback (has access to this_val)
function generateClassMethod(className, methodName, decl) {
  const jsName = decl.js_name || methodName;
  const fnName = `${className}_${methodName}_fn`;
  const args = decl.args || [];
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
  lines.push(`        return NapiValue()`);

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

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
  lines.push(`        return NapiValue()`);

  return lines.join('\n');
}

// Generate a setter callback (has access to this_val + val)
function generateClassSetter(className, propName, decl) {
  const fnName = `${className}_set_${propName}_fn`;
  const body = decl.body || 'return val';

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
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
  lines.push(`        return NapiValue()`);

  return lines.join('\n');
}

// Generate a getter callback (has access to this_val, no args)
function generateClassGetter(className, getterName, decl) {
  const fnName = `${className}_get_${getterName}_fn`;
  const body = decl.body || 'return JsUndefined.create(_b, env).value';

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);
  lines.push(`        var _b = CbArgs.get_bindings(env, info)`);
  lines.push(`        var this_val = CbArgs.get_this(_b, env, info)`);

  const bodyLines = body.split('\n');
  for (const bl of bodyLines) {
    lines.push(`        ${bl}`);
  }

  lines.push(`    except:`);
  lines.push(`        throw_js_error(env, "${getterName} getter failed")`);
  lines.push(`        return NapiValue()`);

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
  const funcEntries = Object.entries(functions);
  const classEntries = Object.entries(classes);

  if (funcEntries.length === 0 && classEntries.length === 0) {
    console.log('No functions or classes declared in exports.toml');
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
    output.push('from memory import alloc');
  }
  if (hasAsync) {
    output.push('from napi.framework.async_work import AsyncWork, AsyncWorkResult');
  }
  // Extra imports for mojo_fn declarations (user-defined pure Mojo functions)
  const extraImports = decl.extra_imports || [];
  for (const imp of (Array.isArray(extraImports) ? extraImports : [extraImports])) {
    output.push(imp);
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
  output.push('fn register_generated(mut m: ModuleBuilder) raises:');
  // All functions (sync + async) register via m.method
  output.push(generateRegistration(functions));
  if (hasClasses) {
    output.push(generateClassRegistration(classes));
  }

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT_PATH, output.join('\n') + '\n');
  const total = funcEntries.length + classEntries.length;
  console.log(`Generated ${OUT_PATH} (${funcEntries.length} functions, ${classEntries.length} classes)`);
}

main();
