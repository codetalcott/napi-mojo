#!/usr/bin/env node
/**
 * generate-dts.js — Auto-generate TypeScript definitions from src/lib.mojo
 *
 * Scans the Mojo source for register_method calls, class registrations,
 * and callback function bodies to infer TypeScript signatures.
 *
 * Usage: node scripts/generate-dts.js
 * Output: build/index.d.ts
 *
 * AUTO-GENERATED — do not edit manually.
 */

const fs = require('fs');
const path = require('path');

const SRC_DIR = path.join(__dirname, '..', 'src');
const ADDON_DIR = path.join(SRC_DIR, 'addon');
const OUT = path.join(__dirname, '..', 'build', 'index.d.ts');

// Manual overrides for complex signatures that regex inference can't handle.
// Value is the full signature after the function name: "(params): returnType"
const OVERRIDES = {
  makeGreeting: '(): { message: string }',
  getProperty: '(obj: object, key: string): any',
  callFunction: '(fn: Function, arg: any): any',
  mapArray: '(arr: any[], fn: (item: any) => any): any[]',
  resolveWith: '(value: any): Promise<any>',
  rejectWith: '(msg: string): Promise<any>',
  asyncProgress: '(count: number, cb: (i: number) => void): Promise<void>',
  createCallback: '(): (...args: any[]) => any',
  createAdder: '(n: number): (x: number) => number',
  getGlobal: '(): typeof globalThis',
  testRef: '(): object',
  testRefObject: '(): object',
  testRefString: '(s: string): object',
  buildInScope: '(): object',
  getKeys: '(obj: object): string[]',
  hasOwn: '(obj: object, key: string): boolean',
  deleteProperty: '(obj: object, key: string): object',
  freezeObject: '(obj: object): Readonly<object>',
  sealObject: '(obj: object): object',
  arrayHasElement: '(arr: any[], index: number): boolean',
  arrayDeleteElement: '(arr: any[], index: number): any[]',
  getPrototype: '(obj: object): object | null',
  getExternalData: '(ext: unknown): { x: number; y: number }',
  doubleFloat64Array: '(arr: Float64Array): Float64Array',
  sumBuffer: '(buf: Buffer): number',
  createArrayBuffer: '(size: number): ArrayBuffer',
  createBuffer: '(size: number): Buffer',
  arrayBufferLength: '(buf: ArrayBuffer): number',
  symbolFor: '(key: string): symbol',
  createSymbol: '(description: string): symbol',
  getDateValue: '(d: Date): number',
  coerceToBool: '(val: any): boolean',
  coerceToNumber: '(val: any): number',
  coerceToString: '(val: any): string',
  coerceToObject: '(val: any): object',
  isInstanceOf: '(obj: any, ctor: Function): boolean',
  strictEquals: '(a: any, b: any): boolean',
  setPropertyByKey: '(obj: object, key: string | symbol, value: any): object',
  hasPropertyByKey: '(obj: object, key: string | symbol): boolean',
  throwValue: '(value: any): never',
  catchAndReturn: '(value: any): any',
  getNapiVersion: '(): number',
  getNodeVersion: '(): { major: number; minor: number; patch: number }',
  createExternalArrayBuffer: '(size: number): ArrayBuffer',
  attachFinalizer: '(obj: object): boolean',
  bigIntFromWords: '(sign: number, words: bigint[]): bigint',
  bigIntToWords: '(bi: bigint): { sign: number; words: bigint[] }',
  createDataView: '(ab: ArrayBuffer, offset: number, length: number): DataView',
  getDataViewInfo: '(dv: DataView): { byteLength: number; byteOffset: number }',
  isDataView: '(val: any): boolean',
  createExternal: '(x: number, y: number): unknown',
  asyncDouble: '(arg: number): Promise<number>',
  asyncTriple: '(arg: number): Promise<number>',
  cancelAsyncWork: '(): Promise<never>',
  createTypedArrayView: '(type: string, ab: ArrayBuffer, offset: number, length: number): ArrayBufferView',
  getTypedArrayType: '(ta: ArrayBufferView): number',
  getTypedArrayLength: '(ta: ArrayBufferView): number',
  // Phase 21-22
  isError: '(val: any): boolean',
  adjustExternalMemory: '(changeInBytes: number): number',
  runScript: '(code: string): any',
  throwSyntaxError: '(): never',
  isDetachedArrayBuffer: '(val: ArrayBuffer): boolean',
  detachArrayBuffer: '(ab: ArrayBuffer): boolean',
  typeTagObject: '(obj: object, lower: number, upper: number): boolean',
  checkObjectTypeTag: '(obj: object, lower: number, upper: number): boolean',
  // Async context (C2/C3)
  makeCallback: '(fn: Function, arg: any): any',
  makeCallback0: '(fn: Function): any',
  makeCallback2: '(fn: Function, a: any, b: any): any',
  makeCallbackScope: '(fn: Function): any',
  // Collection helpers (Steps 1+2)
  genericDoubleArray: '(arr: number[]): number[]',
  genericReverseStrings: '(arr: string[]): string[]',
  objectFromArrays: '(keys: string[], values: number[]): Record<string, number>',
  objectToArrays: '(obj: Record<string, number>): { keys: string[]; values: number[] }',
};

// Collect source from all addon files + lib.mojo
const sourceParts = [];
if (fs.existsSync(ADDON_DIR)) {
  for (const f of fs.readdirSync(ADDON_DIR).sort()) {
    if (f.endsWith('.mojo') && f !== '__init__.mojo') {
      sourceParts.push(fs.readFileSync(path.join(ADDON_DIR, f), 'utf8'));
    }
  }
}
sourceParts.push(fs.readFileSync(path.join(SRC_DIR, 'lib.mojo'), 'utf8'));
const source = sourceParts.join('\n');
const lines = source.split('\n');

// --- Pass 1: Extract registered JS function names ---
const registeredFunctions = [];
const registerMethodRe = /(?:register_method\(env, exports, |m\.method\()\"(\w+)\"/;
const multilineMethodRe = /^\s*m\.method\(\s*$/;
const multilineNameRe = /^\s*\"(\w+)\"/;
for (let i = 0; i < lines.length; i++) {
  const m = lines[i].match(registerMethodRe);
  if (m) { registeredFunctions.push(m[1]); continue; }
  // Handle mojo format splitting m.method( onto separate line from "name"
  if (multilineMethodRe.test(lines[i]) && i + 1 < lines.length) {
    const nameMatch = lines[i + 1].match(multilineNameRe);
    if (nameMatch) registeredFunctions.push(nameMatch[1]);
  }
}

// --- Pass 2: Map JS names to Mojo callback function names ---
// Pattern: var NAME_ref = NAME_fn, then register_method uses NAME_ref
const refToFn = {};
const refRe = /^\s*var (\w+_ref) = (\w+_fn)\s*$/;
for (const line of lines) {
  const m = line.match(refRe);
  if (m) refToFn[m[1]] = m[2];
}

// Map JS name -> callback fn name by finding which ref is used
const jsFnToCallback = {};
for (let i = 0; i < lines.length; i++) {
  // Extract JS name from single-line or multiline m.method() call
  let jsName = null;
  let searchLines = [lines[i], lines[i + 1] || ''];
  const m = lines[i].match(registerMethodRe);
  if (m) {
    jsName = m[1];
  } else if (multilineMethodRe.test(lines[i]) && i + 1 < lines.length) {
    const nameMatch = lines[i + 1].match(multilineNameRe);
    if (nameMatch) jsName = nameMatch[1];
    searchLines = [lines[i + 1] || '', lines[i + 2] || ''];
  }
  if (jsName) {
    // Check current + next lines for fn_ptr(xxx_ref) pattern
    const combined = searchLines.join(' ');
    const fnPtrMatch = combined.match(/fn_ptr\((\w+_ref)\)/);
    if (fnPtrMatch && refToFn[fnPtrMatch[1]]) {
      jsFnToCallback[jsName] = refToFn[fnPtrMatch[1]];
      continue;
    }
    // Fallback: check for UnsafePointer(to=xxx_ref) pattern (old style)
    const refMatch = combined.match(/UnsafePointer\(to=(\w+_ref)\)/);
    if (refMatch && refToFn[refMatch[1]]) {
      jsFnToCallback[jsName] = refToFn[refMatch[1]];
    }
  }
}

// --- Pass 3: Extract function bodies ---
const fnBodies = {};
const fnStartRe = /^def (\w+)\(env: NapiEnv, info: NapiValue\) -> NapiValue:/;
let currentFn = null;
let currentBody = [];

for (const line of lines) {
  const m = line.match(fnStartRe);
  if (m) {
    if (currentFn) fnBodies[currentFn] = currentBody.join('\n');
    currentFn = m[1];
    currentBody = [];
  } else if (currentFn) {
    // End of function: next top-level declaration or blank + comment block
    if (/^(def |@export|struct |##)/.test(line) && !line.startsWith('    ')) {
      fnBodies[currentFn] = currentBody.join('\n');
      currentFn = null;
      currentBody = [];
    } else {
      currentBody.push(line);
    }
  }
}
if (currentFn) fnBodies[currentFn] = currentBody.join('\n');

// --- Pass 4: Analyze function bodies for type inference ---
function inferReturnType(body) {
  if (!body) return 'any';

  // Check for promise (async patterns)
  if (body.includes('JsPromise.create(')) return 'Promise<any>';

  // Check specific return types
  if (body.includes('JsString.create_literal(') || body.includes('JsString.create(')) return 'string';
  if (body.includes('JsBigInt.from_int64(') || body.includes('JsBigInt.from_uint64(')) return 'bigint';
  if (body.includes('JsDate.create(')) return 'Date';
  if (body.includes('JsSymbol.create(') || body.includes('JsSymbol.create_for(')) return 'symbol';
  if (body.includes('JsBoolean.create(')) return 'boolean';
  if (body.includes('JsInt32.create(') || body.includes('JsUInt32.create(') || body.includes('JsNumber.create(')) return 'number';
  if (body.includes('JsNull.create(')) return 'null';
  if (body.includes('JsUndefined.create(')) return 'undefined';
  if (body.includes('JsArrayBuffer.create(')) return 'ArrayBuffer';
  if (body.includes('JsBuffer.create(')) return 'Buffer';
  if (body.includes('JsExternal.create(')) return 'unknown';
  if (body.includes('JsArray.create_with_length(')) return 'any[]';
  if (body.includes('JsObject.create(')) return 'object';

  // Error-only functions (throw without meaningful return)
  if (body.includes('throw_js_type_error(') && !body.includes('JsNumber') && !body.includes('JsString') && !body.includes('JsBoolean')) {
    return 'never';
  }
  if (body.includes('throw_js_range_error(') && !body.includes('JsNumber') && !body.includes('JsString')) {
    return 'never';
  }

  return 'any';
}

function inferParamCount(body) {
  if (!body) return 0;
  if (body.includes('CbArgs.argc(')) return -1; // variadic
  if (body.includes('CbArgs.get_three(') || body.includes('CbArgs.get_bindings_and_three(')) return 3;
  if (body.includes('CbArgs.get_two(') || body.includes('CbArgs.get_bindings_and_two(')) return 2;
  if (body.includes('CbArgs.get_this_and_one(')) return 1;
  if (body.includes('CbArgs.get_one(') || body.includes('CbArgs.get_bindings_and_one(')) return 1;
  return 0;
}

function inferParamTypes(body, count) {
  if (count === 0) return [];
  if (count === -1) return [{ name: 'args', type: 'number', rest: true }]; // sumArgs pattern

  const params = [];
  const paramNames = count === 1 ? ['arg'] : ['a', 'b'];

  for (let i = 0; i < Math.abs(count); i++) {
    let type = 'any';

    // Look for type checks on this parameter
    if (count === 1) {
      if (body.includes('NAPI_TYPE_STRING')) type = 'string';
      else if (body.includes('NAPI_TYPE_NUMBER')) type = 'number';
      else if (body.includes('NAPI_TYPE_FUNCTION')) type = 'Function';
      else if (body.includes('NAPI_TYPE_BIGINT')) type = 'bigint';
      else if (body.includes('NAPI_TYPE_EXTERNAL')) type = 'unknown';
      else if (body.includes('js_is_array(')) type = 'any[]';
      else if (body.includes('NAPI_TYPE_OBJECT')) type = 'object';
      // Infer from usage
      else if (body.includes('JsNumber.from_napi_value(')) type = 'number';
      else if (body.includes('JsString.from_napi_value(') || body.includes('JsString.read_arg_0(')) type = 'string';
    } else if (count === 2) {
      // For two-arg functions, check common patterns
      if (body.includes('JsNumber.from_napi_value(')) type = 'number';
      else if (body.includes('JsInt32.from_napi_value(')) type = 'number';
      else if (body.includes('JsUInt32.from_napi_value(')) type = 'number';
      else if (body.includes('JsBigInt.')) type = 'bigint';
    }

    params.push({ name: paramNames[i] || `arg${i}`, type });
  }

  return params;
}

function buildSignature(jsName) {
  if (OVERRIDES[jsName]) return OVERRIDES[jsName];

  const callbackName = jsFnToCallback[jsName];
  const body = fnBodies[callbackName] || '';

  const returnType = inferReturnType(body);
  const paramCount = inferParamCount(body);
  const params = inferParamTypes(body, paramCount);

  const paramStr = params
    .map(p => p.rest ? `...${p.name}: ${p.type}[]` : `${p.name}: ${p.type}`)
    .join(', ');

  return `(${paramStr}): ${returnType}`;
}

// --- Pass 5: Extract class info ---
const classes = {};
// Support both old and new patterns
const defineClassRe = /(?:define_class\(env, |m\.class_def\()"(\w+)"/;
const instanceMethodRe = /(?:register_instance_method\(env, \w+, |\w+\.instance_method\()"(\w+)"/;
const staticMethodRe = /(?:register_static_method\(env, \w+, |\w+\.static_method\()"(\w+)"/;
const getterSetterRe = /(?:register_getter_setter\(env, \w+, |\w+\.getter_setter\()"(\w+)"/;
const getterRe = /(?:register_getter\(env, \w+, |\w+\.getter\()"(\w+)"/;

let currentClass = null;
let inClassBlock = false;

for (let i = 0; i < lines.length; i++) {
  const line = lines[i];

  const classMatch = line.match(defineClassRe);
  if (classMatch) {
    currentClass = classMatch[1];
    classes[currentClass] = {
      instanceMethods: [],
      staticMethods: [],
      getterSetters: [],
      getters: [],
    };
    inClassBlock = true;
    continue;
  }

  if (inClassBlock && currentClass) {
    const im = line.match(instanceMethodRe);
    if (im) {
      // Check current line for fn_ptr(xxx_ref) (new style)
      const fnPtrMatch = line.match(/fn_ptr\((\w+_ref)\)/);
      let callbackName = fnPtrMatch ? refToFn[fnPtrMatch[1]] : null;
      if (!callbackName) {
        // Fallback: check next line for UnsafePointer(to=xxx_ref) (old style)
        const nextLine = lines[i + 1] || '';
        const refMatch = nextLine.match(/UnsafePointer\(to=(\w+_ref)\)/);
        callbackName = refMatch ? refToFn[refMatch[1]] : null;
      }
      classes[currentClass].instanceMethods.push({
        name: im[1],
        callback: callbackName,
      });
      continue;
    }

    const sm = line.match(staticMethodRe);
    if (sm) {
      const fnPtrMatch = line.match(/fn_ptr\((\w+_ref)\)/);
      let callbackName = fnPtrMatch ? refToFn[fnPtrMatch[1]] : null;
      if (!callbackName) {
        const nextLine = lines[i + 1] || '';
        const refMatch = nextLine.match(/UnsafePointer\(to=(\w+_ref)\)/);
        callbackName = refMatch ? refToFn[refMatch[1]] : null;
      }
      classes[currentClass].staticMethods.push({
        name: sm[1],
        callback: callbackName,
      });
      continue;
    }

    const gs = line.match(getterSetterRe);
    if (gs) {
      classes[currentClass].getterSetters.push(gs[1]);
      continue;
    }

    const g = line.match(getterRe);
    if (g) {
      classes[currentClass].getters.push(g[1]);
      continue;
    }

    // End of class block: blank line, comment line, or non-class-member code
    // (next class_def is caught at the top of the loop)
    if (line.match(/^\s*$/) || line.match(/^\s*#/) ||
        line.includes('set_property') && line.includes(currentClass)) {
      inClassBlock = false;
      currentClass = null;
    }
  }
}

// Manual overrides for class constructor params
const CONSTRUCTOR_OVERRIDES = {
  Animal: 'name: string',
  Dog: 'name: string, breed: string',
};

// Class inheritance: child -> parent
const CLASS_EXTENDS = {
  Dog: 'Animal',
};

// Manual overrides for class methods: { "ClassName.methodName": "paramStr: returnType" }
const METHOD_OVERRIDES = {
  'Counter.isCounter': { paramStr: 'val: any', returnType: 'boolean' },
  'Counter.fromValue': { paramStr: 'n: number', returnType: 'Counter' },
  'Counter.increment': { paramStr: '', returnType: 'void' },
  'Counter.reset': { paramStr: '', returnType: 'void' },
  'Animal.speak': { paramStr: '', returnType: 'string' },
  'Animal.isAnimal': { paramStr: 'val: any', returnType: 'boolean' },
};

// --- Pass 6: Infer class method signatures ---
function inferMethodSignature(callbackName, className, methodName) {
  const key = `${className}.${methodName}`;
  if (METHOD_OVERRIDES[key]) return METHOD_OVERRIDES[key];

  const body = fnBodies[callbackName] || '';
  const returnType = inferReturnType(body);

  // Instance methods typically have no user-facing params (they use this)
  // Check for CbArgs usage beyond get_this
  let paramCount = 0;
  if (body.includes('CbArgs.get_this_and_one(') || body.includes('CbArgs.get_one(')) {
    paramCount = 1;
  } else if (body.includes('CbArgs.get_two(')) {
    paramCount = 2;
  }

  const params = inferParamTypes(body, paramCount);
  const paramStr = params.map(p => `${p.name}: ${p.type}`).join(', ');

  return { paramStr, returnType };
}

// --- Pass 7: Infer constructor signature ---
function inferConstructorParams(className) {
  if (CONSTRUCTOR_OVERRIDES[className]) return CONSTRUCTOR_OVERRIDES[className];

  const ctorName = `${className.toLowerCase()}_constructor_fn`;
  const body = fnBodies[ctorName] || '';

  if (body.includes('CbArgs.get_one(') || body.includes('CbArgs.get_this_and_one(')) {
    if (body.includes('JsNumber.from_napi_value(') || body.includes('NAPI_TYPE_NUMBER')) {
      return 'initialValue: number';
    }
    if (body.includes('JsString.from_napi_value(') || body.includes('NAPI_TYPE_STRING')) {
      return 'value: string';
    }
    return 'arg: any';
  }
  if (body.includes('CbArgs.get_two(')) {
    return 'a: any, b: any';
  }
  return '';
}

// --- Pass 8: Infer getter/setter types ---
function inferPropertyType(className, propName) {
  // Look for the getter callback
  const getterName = `${className.toLowerCase()}_get_${propName}_fn`;
  const body = fnBodies[getterName] || '';
  if (body.includes('JsNumber.create(')) return 'number';
  if (body.includes('JsString.create(')) return 'string';
  if (body.includes('JsBoolean.create(')) return 'boolean';
  return 'any';
}

// One-line JSDoc descriptions emitted as /** ... */ before each export.
// Pattern from napi-rs: keep the DTS self-describing so IDE hover and
// typedoc (npm run generate:docs) work without a separate docs file.
const DOCS = {
  // Math & arithmetic
  hello:          'Returns "Hello from Mojo!".',
  add:            'Returns a + b (Float64).',
  addInts:        'Returns a + b (Int32).',
  bitwiseOr:      'Returns a | b (UInt32 bitwise OR).',
  addIntsStrict:  'Like addInts but throws TypeError if either argument is not a number.',
  addBigInts:     'Returns a + b for arbitrary-precision BigInt values.',
  sumArgs:        'Returns the sum of any number of Float64 arguments.',
  isPositive:     'Returns true if n > 0.',
  // Strings
  greet:          'Returns "Hello, <name>!".',
  toJsString:     'Coerces any value to a string (equivalent to String(val)).',
  // Objects
  createObject:   'Returns an empty plain object {}.',
  makeGreeting:   'Returns { message: "Hello!" }.',
  getProperty:    'Returns obj[key] using napi_get_property.',
  getKeys:        'Returns the own enumerable property names of obj (Object.keys).',
  hasOwn:         'Returns true if obj has own property key.',
  deleteProperty: 'Deletes obj[key] and returns the mutated object.',
  setPropertyByKey:  'Sets obj[key] = value using a string or symbol key; returns obj.',
  hasPropertyByKey:  'Returns key in obj (walks the prototype chain).',
  freezeObject:   'Freezes obj and returns it (Object.freeze).',
  sealObject:     'Seals obj and returns it (Object.seal).',
  getPrototype:   'Returns Object.getPrototypeOf(obj).',
  getAllPropertyNames: 'Returns all property names including non-enumerable and inherited.',
  getOptValue:    'Returns obj.x if present, null otherwise.',
  getGlobal:      'Returns the global object (globalThis).',
  // Arrays
  sumArray:       'Returns the sum of a JavaScript number array.',
  mapArray:       'Returns arr.map(fn), using a Mojo handle scope to avoid GC pressure.',
  arrayHasElement:   'Returns true if arr[index] exists.',
  arrayDeleteElement: 'Deletes arr[index] (sparse deletion); returns the array.',
  sumJsArray:     'Sums a Float64Array or plain number[] using Mojo-side iteration.',
  doubleArray:    'Doubles each element of a number[] in place.',
  joinStrings:    'Concatenates two strings.',
  reverseStrings: 'Reverses a string[].',
  genericDoubleArray:    'Doubles each element of a number[] and returns a new array.',
  genericReverseStrings: 'Reverses a string[] and returns a new array.',
  objectFromArrays: 'Zips parallel string keys[] and number values[] into a plain object.',
  objectToArrays:   'Splits an object into parallel { keys: string[], values: number[] } arrays.',
  // Binary data
  createArrayBuffer:      'Creates an ArrayBuffer of `size` bytes filled with incrementing values.',
  arrayBufferLength:      'Returns the byte length of an ArrayBuffer.',
  createBuffer:           'Creates a Node.js Buffer of `size` bytes filled with incrementing values.',
  createBufferCopy:       'Creates a new Buffer with a copy of the source Buffer\'s bytes.',
  sumBuffer:              'Returns the sum of all bytes in a Node.js Buffer.',
  doubleFloat64Array:     'Doubles each element of a Float64Array in place.',
  createTypedArrayView:   'Creates a typed array view (Int8/Uint8/Int32/Float64 etc.) over an ArrayBuffer.',
  getTypedArrayType:      'Returns the NAPI_*_ARRAY type constant for a TypedArray.',
  getTypedArrayLength:    'Returns the element count (not bytes) of a TypedArray.',
  createDataView:         'Creates a DataView over an ArrayBuffer with the given byte offset and length.',
  getDataViewInfo:        'Returns { byteLength, byteOffset } for a DataView.',
  isDataView:             'Returns true if val is a DataView.',
  createExternalArrayBuffer: 'Creates an ArrayBuffer backed by Mojo-managed memory; GC finalizer frees it.',
  isDetachedArrayBuffer:  'Returns true if the ArrayBuffer has been detached.',
  detachArrayBuffer:      'Detaches an ArrayBuffer, rendering it zero-length.',
  // Async & promises
  resolveWith:    'Returns a Promise that immediately resolves with value.',
  rejectWith:     'Returns a Promise that immediately rejects with Error(msg).',
  asyncDouble:    'Returns a Promise that resolves with arg * 2 (computed on a worker thread).',
  asyncTriple:    'Returns a Promise that resolves with arg * 3 (computed on a worker thread).',
  asyncProgress:  'Calls cb(i) for i in 0..count-1 from a worker thread via ThreadsafeFunction; returns a Promise.',
  cancelAsyncWork: 'Queues then immediately cancels async work; returns a rejected Promise.',
  // Callbacks & async context
  callFunction:   'Calls fn(arg) and returns the result.',
  createCallback: 'Returns a new Mojo-created JavaScript function.',
  createAdder:    'Returns a function that adds n to its argument.',
  makeCallback:   'Calls fn(arg) within the current async context (napi_make_callback).',
  makeCallback0:  'Calls fn() within the current async context.',
  makeCallback2:  'Calls fn(a, b) within the current async context.',
  makeCallbackScope: 'Calls fn() inside an explicit napi_callback_scope.',
  createNamedFn:  'Creates and returns a named JavaScript function with explicit arity.',
  // Symbols, BigInt, Date
  createSymbol:   'Creates a new unique Symbol with the given description.',
  symbolFor:      'Returns the global Symbol for key (Symbol.for).',
  createDate:     'Creates a Date from a millisecond timestamp.',
  getDateValue:   'Returns the millisecond timestamp of a Date.',
  bigIntFromWords: 'Creates a BigInt from a sign flag and an array of 64-bit words.',
  bigIntToWords:   'Returns { sign, words } decomposition of a BigInt.',
  // Type checks & coercion
  strictEquals:   'Returns a === b (uses napi_strict_equals).',
  isInstanceOf:   'Returns obj instanceof ctor.',
  coerceToBool:   'Returns Boolean(val).',
  coerceToNumber: 'Returns Number(val); throws TypeError for Symbol.',
  coerceToString: 'Returns String(val); throws TypeError for Symbol.',
  coerceToObject: 'Returns Object(val); throws TypeError for null/undefined.',
  isExternal:     'Returns true if val is an N-API external (opaque native pointer).',
  isError:        'Returns true if val is an Error object.',
  // Error handling
  throwTypeError:  'Throws a TypeError. Always returns undefined.',
  throwRangeError: 'Throws a RangeError. Always returns undefined.',
  throwSyntaxError: 'Throws a SyntaxError. Always returns undefined.',
  throwValue:      'Throws any JavaScript value as an exception.',
  catchAndReturn:  'Throws then catches val; returns the caught value.',
  getErrorMessage: 'Returns the .message property of an Error (or any object).',
  getErrorStack:   'Returns the .stack property of an Error (or any object).',
  // GC & lifecycle
  createExternal:    'Wraps native { x, y } data as an N-API external with a GC finalizer.',
  getExternalData:   'Retrieves the { x, y } from an N-API external value.',
  attachFinalizer:   'Attaches a native GC finalizer to any JavaScript object.',
  setInstanceData:   'Stores a number as per-environment singleton data.',
  getInstanceData:   'Retrieves the per-environment singleton number.',
  addCleanupHook:    'Registers an env cleanup hook; returns true.',
  removeCleanupHook: 'Registers then removes an env cleanup hook; returns true.',
  addAsyncCleanupHook:    'Registers an async env cleanup hook; returns true.',
  removeAsyncCleanupHook: 'Registers then removes an async env cleanup hook; returns true.',
  // Runtime introspection
  getNapiVersion: 'Returns the highest N-API version supported by this Node.js runtime.',
  getNodeVersion: 'Returns { major, minor, patch } of the running Node.js version.',
  runScript:      'Evaluates a JavaScript string and returns the result (napi_run_script).',
  adjustExternalMemory: 'Hints the V8 GC about native memory held outside the JS heap.',
  getUvEventLoop: 'Returns the address of the libuv event loop as a BigInt pointer.',
  // Type tagging
  typeTagObject:        'Tags an object with a 128-bit type ID (lower/upper uint32 halves).',
  checkObjectTypeTag:   'Returns true if the object\'s tag matches lower/upper.',
  // Refs & scopes (internal/test)
  testRef:        'Creates an object, stores it in an napi_ref, retrieves it, and returns it.',
  testRefObject:  'Round-trips an object through an napi_ref.',
  testRefString:  'Wraps a string in an object, stores in an napi_ref, returns the wrapper.',
  testWeakRef:    'Creates a weak reference (refcount=0) and returns the value.',
  buildInScope:   'Creates an object inside an escapable handle scope and escapes it.',
  newCounterFromRegistry: 'Creates a Counter via the ClassRegistry new_instance helper.',
  // Misc
  getNull:        'Returns JavaScript null.',
  getUndefined:   'Returns JavaScript undefined.',
  getAllPropertyNames: 'Returns all own + inherited property names (napi_get_all_property_names).',
  objectFromArrays: 'Zips parallel string keys[] and number values[] into a plain object.',
  objectToArrays:   'Splits an object into { keys: string[], values: number[] }.',
};

// --- Generate output ---
const output = [];
output.push('// Auto-generated by scripts/generate-dts.js — do not edit manually');
output.push('');

// Generate function declarations
for (const jsName of registeredFunctions) {
  const sig = buildSignature(jsName);
  if (DOCS[jsName]) output.push(`/** ${DOCS[jsName]} */`);
  output.push(`export function ${jsName}${sig};`);
}

output.push('');

// Generate class declarations
for (const [className, info] of Object.entries(classes)) {
  const extendsClause = CLASS_EXTENDS[className] ? ` extends ${CLASS_EXTENDS[className]}` : '';
  output.push(`export class ${className}${extendsClause} {`);

  // Constructor
  const ctorParams = inferConstructorParams(className);
  output.push(`  constructor(${ctorParams});`);

  // Instance methods
  for (const method of info.instanceMethods) {
    const sig = inferMethodSignature(method.callback, className, method.name);
    output.push(`  ${method.name}(${sig.paramStr}): ${sig.returnType};`);
  }

  // Getter/setter properties
  for (const prop of info.getterSetters) {
    const type = inferPropertyType(className, prop);
    output.push(`  ${prop}: ${type};`);
  }

  // Read-only getters
  for (const prop of info.getters) {
    const type = inferPropertyType(className, prop);
    output.push(`  readonly ${prop}: ${type};`);
  }

  // Static methods
  for (const method of info.staticMethods) {
    const sig = inferMethodSignature(method.callback, className, method.name);
    output.push(`  static ${method.name}(${sig.paramStr}): ${sig.returnType};`);
  }

  output.push('}');
  output.push('');
}

// --- TOML-defined classes (from src/exports.toml) ---
function parseTOML(text) {
  const result = {};
  let current = result;
  const lines2 = text.split('\n');
  let i = 0;
  while (i < lines2.length) {
    const line = lines2[i].trim();
    i++;
    if (!line || line.startsWith('#')) continue;
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
    const kvMatch = line.match(/^(\w+)\s*=\s*(.*)$/);
    if (kvMatch) {
      const key = kvMatch[1];
      let value = kvMatch[2].trim();
      if (value.startsWith('"""')) {
        value = value.slice(3);
        const bodyLines = [value];
        while (i < lines2.length) {
          const nextLine = lines2[i]; i++;
          if (nextLine.trim().endsWith('"""')) { bodyLines.push(nextLine.trim().slice(0, -3)); break; }
          bodyLines.push(nextLine);
        }
        current[key] = bodyLines.join('\n').trim();
        continue;
      }
      if (value.startsWith('"') && value.endsWith('"')) { current[key] = value.slice(1, -1); continue; }
      if (value.startsWith('[')) {
        current[key] = value.slice(1, -1).split(',').map(s => s.trim().replace(/"/g, '')).filter(Boolean);
        continue;
      }
      current[key] = value;
    }
  }
  return result;
}

const TOML_TYPE_TO_TS = {
  number: 'number', string: 'string', boolean: 'boolean', bool: 'boolean',
  int32: 'number', uint32: 'number', int64: 'number',
  object: 'object', array: 'any[]', any: 'any',
  'number[]': 'number[]', 'string[]': 'string[]',
};
function tomlTokenToTs(token) {
  const noQ = (token || 'any').replace(/\?$/, '');
  // Handle typed array tokens (number[], string[]) before looking up
  if (noQ.endsWith('[]')) return TOML_TYPE_TO_TS[noQ] || 'any[]';
  return TOML_TYPE_TO_TS[noQ] || 'any';
}

const TOML_PATH = path.join(__dirname, '..', 'src', 'exports.toml');
let toml = {};
try {
  toml = parseTOML(fs.readFileSync(TOML_PATH, 'utf8'));
} catch {
  console.log(`Note: ${TOML_PATH} not found or unreadable — skipping TOML-declared exports.`);
}

// Register struct types and emit TypeScript interfaces
const tomlStructs = toml.structs || {};
for (const [sName, sDecl] of Object.entries(tomlStructs)) {
  const jsName = sDecl.js_name || sName;
  // Register the TOML struct name as a TS type mapping
  TOML_TYPE_TO_TS[sName] = jsName;
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
  const fnArgs = (fn.args || []).map((t, i) => `arg${i}: ${tomlTokenToTs(t)}`).join(', ');
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

  // Setters paired with getters (Phase 30: tracked via setters map)
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

// Write output
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, output.join('\n'));
const tomlClassCount = Object.keys(toml.classes || {}).length;
console.log(`Generated ${OUT} (${registeredFunctions.length} functions, ${Object.keys(classes).length + tomlClassCount} class(es))`);
