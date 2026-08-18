// scripts/toml-dts.js — TypeScript declarations from a TOML declaration file.
//
// The TOML-driven half of generate-dts.js, extracted so the napi-mojo CLI can
// emit .d.ts for CONSUMER addons (whose types are fully declared in their
// exports.toml — no Mojo-source inference needed or possible there). One
// emitter, two callers; the two-copies-diverge failure mode is what forced
// toml-lite.js into existence, so don't fork this back into either caller.
//
// CJS on purpose: generate-dts.js is CJS (require) and bin/napi-mojo.mjs can
// import CJS through Node's ESM interop.

const TOML_TYPE_TO_TS_BASE = {
  number: 'number', string: 'string', boolean: 'boolean', bool: 'boolean',
  int32: 'number', uint32: 'number', int64: 'number',
  object: 'object', array: 'any[]', any: 'any',
  'number[]': 'number[]', 'string[]': 'string[]',
};

function makeTokenToTs(map) {
  return function tomlTokenToTs(token) {
    const noQ = (token || 'any').replace(/\?$/, '');
    // Handle typed array tokens (number[], string[]) before looking up
    if (noQ.endsWith('[]')) return map[noQ] || 'any[]';
    return map[noQ] || 'any';
  };
}

// Emit the .d.ts lines for one parsed TOML declaration object
// ({structs, functions, classes}). Returns an array of lines matching what
// generate-dts.js historically emitted, in the same order: struct interfaces,
// functions, a blank separator, classes.
function emitTomlDts(toml) {
  const map = { ...TOML_TYPE_TO_TS_BASE };
  const tomlTokenToTs = makeTokenToTs(map);

  // Argument position: a '?' token means the generated callback skips type
  // validation, so null/undefined are accepted — say so in the types instead
  // of silently stripping the '?'.
  function tomlArgToTs(token) {
    const base = tomlTokenToTs(token);
    if (String(token || '').endsWith('?') && base !== 'any') {
      return `${base} | null`;
    }
    return base;
  }

  const output = [];

  // Register struct types and emit TypeScript interfaces
  const tomlStructs = toml.structs || {};
  for (const [sName, sDecl] of Object.entries(tomlStructs)) {
    const jsName = sDecl.js_name || sName;
    // Register the TOML struct name as a TS type mapping
    map[sName] = jsName;
    // Emit interface
    const fields = sDecl.fields || {};
    output.push(`export interface ${jsName} {`);
    for (const [fName, fType] of Object.entries(fields)) {
      const tsType = tomlTokenToTs(fType);
      output.push(`  ${fName}: ${tsType};`);
    }
    output.push('}');
    output.push('');
  }

  // Emit DTS for TOML-declared functions (sync + async)
  for (const [, fn] of Object.entries(toml.functions || {})) {
    const jsName = fn.js_name;
    if (!jsName) continue;
    const fnArgs = (fn.args || []).map((t, i) => `arg${i}: ${tomlArgToTs(t)}`).join(', ');
    const rawRet = fn.returns || 'any';
    const retNullable = rawRet.endsWith('?');
    const retToken = rawRet.replace(/\?$/, '');
    const isAsync = fn.async === 'true' || fn.async === true;
    const baseRetTs = tomlTokenToTs(retToken);
    const retTs = isAsync
      ? `Promise<${retNullable ? baseRetTs + ' | null' : baseRetTs}>`
      : (retNullable ? `${baseRetTs} | null` : baseRetTs);
    output.push(`export function ${jsName}(${fnArgs}): ${retTs};`);
  }

  output.push('');

  for (const [, cls] of Object.entries(toml.classes || {})) {
    const jsName = cls.js_name;
    if (!jsName) continue;
    output.push(`export class ${jsName} {`);

    // Constructor
    const ctorArgs = cls.constructor_args || [];
    const ctorParams = ctorArgs.map((t, i) => `arg${i}: ${tomlTokenToTs(t)}`).join(', ');
    output.push(`  constructor(${ctorParams});`);

    // Instance methods
    for (const [mName, mDecl] of Object.entries(cls.instance_methods || {})) {
      const ret = tomlTokenToTs(mDecl.returns);
      const mArgs = (mDecl.args || []).map((t, i) => `arg${i}: ${tomlTokenToTs(t)}`).join(', ');
      output.push(`  ${mName}(${mArgs}): ${ret};`);
    }

    // Setters paired with getters (tracked via setters map)
    const setterNames = new Set(Object.keys(cls.setters || {}));

    // Getters
    for (const [gName, gDecl] of Object.entries(cls.getters || {})) {
      const ret = tomlTokenToTs(gDecl.returns);
      if (setterNames.has(gName)) {
        output.push(`  ${gName}: ${ret};`);
      } else {
        output.push(`  readonly ${gName}: ${ret};`);
      }
    }

    // Setter-only (no paired getter — unusual but possible)
    for (const sName of setterNames) {
      if (!(cls.getters || {})[sName]) {
        output.push(`  ${sName}: any;`);
      }
    }

    // Static methods
    for (const [smName, smDecl] of Object.entries(cls.static_methods || {})) {
      const ret = tomlTokenToTs(smDecl.returns);
      const smArgs = (smDecl.args || []).map((t, i) => `arg${i}: ${tomlTokenToTs(t)}`).join(', ');
      output.push(`  static ${smName}(${smArgs}): ${ret};`);
    }

    output.push('}');
    output.push('');
  }

  return output;
}

module.exports = { emitTomlDts };
