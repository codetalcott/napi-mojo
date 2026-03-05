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
const TYPE_MAP = {
  number: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsNumber.from_napi_value(env, ${argExpr})`,
    create: (expr) => `JsNumber.create(env, ${expr}).value`,
  },
  string: {
    napi_type: 'NAPI_TYPE_STRING',
    type_name: 'string',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsString.from_napi_value(env, ${argExpr})`,
    create: (expr) => `JsString.create(env, ${expr}).value`,
  },
  boolean: {
    napi_type: 'NAPI_TYPE_BOOLEAN',
    type_name: 'boolean',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsBoolean.from_napi_value(env, ${argExpr})`,
    create: (expr) => `JsBoolean.create(env, ${expr}).value`,
  },
  int32: {
    napi_type: 'NAPI_TYPE_NUMBER',
    type_name: 'number',
    extract: (varName, argExpr) =>
      `        var ${varName} = JsInt32.from_napi_value(env, ${argExpr})`,
    create: (expr) => `JsInt32.create(env, ${expr}).value`,
  },
  any: {
    napi_type: null, // no type check
    type_name: 'any',
    extract: (varName, argExpr) =>
      `        var ${varName} = ${argExpr}`,
    create: (expr) => expr,
  },
};

// --- Code generation ---
function generateCallback(name, decl) {
  const jsName = decl.js_name || name;
  const args = decl.args || [];
  const returns = decl.returns || 'any';
  const body = decl.body;
  const fnName = `${name}_fn`;

  const lines = [];
  lines.push(`fn ${fnName}(env: NapiEnv, info: NapiValue) -> NapiValue:`);
  lines.push(`    try:`);

  if (args.length === 0) {
    // No args — just run body
  } else if (args.length === 1) {
    lines.push(`        var arg0 = CbArgs.get_one(env, info)`);
    const typeInfo = TYPE_MAP[args[0]];
    if (typeInfo && typeInfo.napi_type) {
      lines.push(`        var t0 = js_typeof(env, arg0)`);
      lines.push(`        if t0 != ${typeInfo.napi_type}:`);
      lines.push(`            throw_js_type_error_dynamic(env, "${jsName}: expected ${typeInfo.type_name}, got " + js_type_name(t0))`);
      lines.push(`            return NapiValue()`);
    }
  } else if (args.length === 2) {
    lines.push(`        var args = CbArgs.get_two(env, info)`);
    for (let i = 0; i < 2; i++) {
      const typeInfo = TYPE_MAP[args[i]];
      if (typeInfo && typeInfo.napi_type) {
        lines.push(`        var t${i} = js_typeof(env, args[${i}])`);
        lines.push(`        if t${i} != ${typeInfo.napi_type}:`);
        lines.push(`            throw_js_type_error_dynamic(env, "${jsName}: expected ${typeInfo.type_name} for arg ${i + 1}, got " + js_type_name(t${i}))`);
        lines.push(`            return NapiValue()`);
      }
    }
  }

  // Insert body (indented to 8 spaces)
  if (body) {
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
  const entries = Object.entries(functions);

  if (entries.length === 0) {
    console.log('No functions declared in exports.toml');
    process.exit(0);
  }

  // Generate output
  const output = [];
  output.push('## src/generated/callbacks.mojo — AUTO-GENERATED by scripts/generate-addon.mjs');
  output.push('## Do not edit manually. Regenerate with: node scripts/generate-addon.mjs');
  output.push('');
  output.push('from napi.types import NapiEnv, NapiValue, NAPI_TYPE_STRING, NAPI_TYPE_NUMBER, NAPI_TYPE_BOOLEAN');
  output.push('from napi.framework.js_string import JsString');
  output.push('from napi.framework.js_number import JsNumber');
  output.push('from napi.framework.js_boolean import JsBoolean');
  output.push('from napi.framework.js_int32 import JsInt32');
  output.push('from napi.framework.args import CbArgs');
  output.push('from napi.framework.js_value import js_typeof, js_type_name');
  output.push('from napi.error import throw_js_error, throw_js_type_error_dynamic');
  output.push('from napi.framework.register import fn_ptr, ModuleBuilder');
  output.push('');

  // Generate callbacks
  for (const [name, funcDecl] of entries) {
    output.push(`# ${funcDecl.js_name || name}`);
    output.push(generateCallback(name, funcDecl));
    output.push('');
  }

  // Generate registration helper
  output.push('');
  output.push('## register_generated — register all generated functions on the module builder');
  output.push('##');
  output.push('## Call from register_module after creating the ModuleBuilder:');
  output.push('##   register_generated(m)');
  output.push('fn register_generated(m: ModuleBuilder) raises:');
  output.push(generateRegistration(functions));

  mkdirSync(OUT_DIR, { recursive: true });
  writeFileSync(OUT_PATH, output.join('\n') + '\n');
  console.log(`Generated ${OUT_PATH} (${entries.length} functions)`);
}

main();
