'use strict';
// The generator's REJECTION branches — the half tests/codegen/ cannot cover.
//
// kitchen-sink.toml proves every template that emits code; a declaration the
// generator is supposed to refuse can't live there, because that file has to
// compile. Each case below emitted plausible-looking Mojo (or a plausible
// .d.ts) that failed far from its cause, which is exactly the failure mode
// the kitchen-sink gate was built to end.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const GEN = path.join(__dirname, '..', 'scripts', 'generate-addon.mjs');

// Runs the generator on `toml`, returns { code, stderr }. Never throws.
function generate(toml) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'napi-mojo-guard-'));
  fs.writeFileSync(path.join(dir, 'exports.toml'), toml);
  try {
    execFileSync(process.execPath, [GEN], {
      encoding: 'utf8',
      stdio: 'pipe',
      env: {
        ...process.env,
        NAPI_MOJO_TOML: path.join(dir, 'exports.toml'),
        NAPI_MOJO_OUT: path.join(dir, 'generated'),
      },
    });
    return { code: 0, stderr: '', dir };
  } catch (e) {
    return { code: e.status, stderr: String(e.stderr || ''), dir };
  }
}

describe('generator input guards', () => {
  test('a struct with no fields is rejected, not emitted as empty method bodies', () => {
    const r = generate('[structs.empty]\njs_name = "Empty"\n[structs.empty.fields]\n');
    // Was: struct EmptyData with `def __init__(out self, ):` and two more
    // empty bodies — three syntax errors, surfacing only at `mojo build`.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/declares no fields/);
    expect(r.stderr).toMatch(/\[structs\.empty\.fields\]/);
  });

  test('a nullable converting arg becomes Optional[T], checked inside the null test', () => {
    const r = generate(
      '[functions.maybe_add]\njs_name = "maybeAdd"\nmojo_fn = "maybe_add"\n' +
        'args = ["number", "number?"]\nreturns = "number"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('from napi.types import NAPI_TYPE_NULL, NAPI_TYPE_UNDEFINED');
    expect(out).toContain('var mojo_arg1: Optional[Float64] = None');
    expect(out).toContain('if _n_mojo_arg1 != NAPI_TYPE_NULL and _n_mojo_arg1 != NAPI_TYPE_UNDEFINED:');
    // The typed check lives INSIDE the null test: null passes, a wrong type
    // still gets the descriptive TypeError rather than the generic catch.
    expect(out).toMatch(/if _n_mojo_arg1 != NAPI_TYPE_NUMBER:/);
    expect(out).toContain('expected number or null for arg 2');
    // arg 0 is not nullable, so it keeps the plain unconditional extract.
    expect(out).toContain('var mojo_arg0 = JsNumber.from_napi_value(_b, env, args[0])');
  });

  test('a struct can be a nullable arg too', () => {
    const r = generate(
      '[structs.cfg]\njs_name = "Cfg"\n[structs.cfg.fields]\nhost = "string"\n\n' +
        '[functions.take_cfg]\njs_name = "takeCfg"\nmojo_fn = "take_cfg"\n' +
        'args = ["cfg?"]\nreturns = "number"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('var mojo_arg0: Optional[CfgData] = None');
    expect(out).toContain('var _v_mojo_arg0 = cfg_from_js(_b, env, arg0)');
  });

  test('tokens with no meaningful Optional form are still refused', () => {
    // An absent array is an empty one; an absent zero-copy view has no buffer.
    for (const tok of ['number[]', 'float64array']) {
      const r = generate(
        '[functions.f]\njs_name = "f"\nmojo_fn = "f"\n' +
          `args = ["${tok}?"]\nreturns = "number"\n`
      );
      expect(r.code).toBe(1);
      expect(r.stderr).toMatch(/has no meaningful Optional form/);
    }
  });

  test("'?' stays supported on pass-through args and on return types", () => {
    const r = generate(
      '[functions.pass_any]\njs_name = "passAny"\nmojo_fn = "pass_any"\n' +
        'args = ["any?", "object?", "array?"]\nreturns = "number?"\n'
    );
    expect(r.stderr).toBe('');
    expect(r.code).toBe(0);
  });

  test('mojo_fn on a class member requires declared state', () => {
    const r = generate(
      '[classes.thing]\njs_name = "Thing"\n\n' +
        '[classes.thing.instance_methods.go]\nreturns = "number"\nmojo_fn = "go"\n'
    );
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/requires the class to declare state/);
  });

  test('state must name a real struct, and needs a constructor to build it', () => {
    const missing = generate('[classes.thing]\njs_name = "Thing"\nstate = "nope"\n');
    expect(missing.code).toBe(1);
    expect(missing.stderr).toMatch(/does not match any \[structs\.\*\] declaration/);

    const noCtor = generate(
      '[structs.st]\njs_name = "St"\n[structs.st.fields]\nn = "number"\n\n' +
        '[classes.thing]\njs_name = "Thing"\nstate = "st"\n'
    );
    expect(noCtor.code).toBe(1);
    expect(noCtor.stderr).toMatch(/requires constructor_mojo_fn/);
  });

  test('a mojo_fn setter is rejected on a class with no state', () => {
    // A setter reaches its instance through the unwrap, so without a state
    // struct there is nothing for the pure function to set. Statics are the
    // opposite case and are covered below.
    const stateless =
      '[classes.thing]\njs_name = "Thing"\nconstructor_args = ["number"]\n' +
      'constructor_body = """\npass\n"""\n\n' +
      '[classes.thing.setters.n]\ntype = "number"\nmojo_fn = "set_n"\n';
    const r = generate(stateless);
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/requires the class to declare state/);
  });

  test('a mojo_fn setter unwraps state and type-checks its value', () => {
    const toml =
      '[structs.st]\njs_name = "St"\n[structs.st.fields]\nn = "number"\n\n' +
      '[classes.thing]\njs_name = "Thing"\nstate = "st"\n' +
      'constructor_args = ["number"]\nconstructor_mojo_fn = "mk"\n\n' +
      '[classes.thing.setters.n]\ntype = "number"\nmojo_fn = "set_n"\n';
    const r = generate(toml);
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toMatch(/unwrap_native_from_this\[StData\]/);
    // The declared token must actually gate the value, not just name it.
    expect(out).toMatch(/js_typeof\(_b, env, val\)/);
    expect(out).toMatch(/set_n\(_state\[\], mojo_val\)/);
  });

  test('a mojo_fn static method needs no state and no unwrap', () => {
    // The inverse of the setter guard: a static has no instance, so it must
    // work on a class that declares no state at all.
    const toml =
      '[classes.thing]\njs_name = "Thing"\nconstructor_args = ["number"]\n' +
      'constructor_body = """\npass\n"""\n\n' +
      '[classes.thing.static_methods.make]\nargs = ["number"]\nreturns = "number"\nmojo_fn = "mk2"\n';
    const r = generate(toml);
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toMatch(/mk2\(mojo_arg0\)/);
    // No instance means no unwrap and no `this` in the static's body.
    const staticFn = out.split('def thing_static_make_fn')[1].split('\ndef ')[0];
    expect(staticFn).not.toMatch(/unwrap_native/);
    expect(staticFn).not.toMatch(/get_this/);
  });

  test('a stateful class emits the wrap/unwrap ceremony with a stable tag', () => {
    const toml =
      '[structs.st]\njs_name = "St"\n[structs.st.fields]\nn = "number"\n\n' +
      '[classes.thing]\njs_name = "Thing"\nstate = "st"\n' +
      'constructor_args = ["number"]\nconstructor_mojo_fn = "mk"\n\n' +
      '[classes.thing.instance_methods.bump]\nreturns = "number"\nmojo_fn = "bump"\n';
    const a = generate(toml);
    expect(a.code).toBe(0);
    const out = fs.readFileSync(path.join(a.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('def thing_finalize(');
    expect(out).toContain('ptr.unsafe_deinit_pointee()');
    expect(out).toContain('wrap_native(');
    expect(out).toContain('var _state = unwrap_native_from_this[StData](');
    expect(out).toContain('var mojo_result = bump(_state[])');
    // Ownership returns to the caller when wrap_native raises, so the data is
    // freed there rather than leaked or double-freed against the finalizer.
    expect(out).toContain('raise e^');

    // The tag is derived from the class name, so regeneration is byte-stable —
    // the drift gate compares bytes, and a random tag would break every run.
    const tag = out.match(/NapiTypeTag\((0x[0-9A-F]+), (0x[0-9A-F]+)\)/);
    expect(tag).not.toBeNull();
    const b = generate(toml);
    const out2 = fs.readFileSync(path.join(b.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out2).toBe(out);
  });

  test('a declared struct also yields a <struct>[] token', () => {
    const r = generate(
      '[structs.cfg]\njs_name = "Cfg"\n[structs.cfg.fields]\nhost = "string"\n\n' +
        '[functions.pick]\njs_name = "pick"\nmojo_fn = "pick"\n' +
        'args = ["cfg[]"]\nreturns = "cfg[]"\n'
    );
    expect(r.code).toBe(0);
    const cbs = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    const structs = fs.readFileSync(path.join(r.dir, 'generated', 'structs.mojo'), 'utf8');
    // The array form is carried entirely by the struct's trait conformance
    // plus the parametric converters — no per-struct array emitter.
    expect(structs).toContain('struct CfgData(Movable, Copyable, ToJsValue, FromJsValue):');
    expect(structs).toContain('def to_js(self, b: Bindings, env: NapiEnv) raises -> NapiValue:');
    expect(structs).toContain('def from_js(b: Bindings, env: NapiEnv, val: NapiValue) raises -> Self:');
    expect(cbs).toContain('from napi.framework.convert import from_js_array, to_js_array');
    expect(cbs).toContain('var mojo_arg0 = from_js_array[CfgData](_b, env, arg0)');
    expect(cbs).toContain('return to_js_array[CfgData](_b, env, mojo_result)');
  });

  test('buffer is rejected as a return type, with the reason', () => {
    const r = generate(
      '[functions.make_buf]\njs_name = "makeBuf"\nmojo_fn = "make_buf"\n' +
        'args = ["number"]\nreturns = "buffer"\n'
    );
    // float64array returns work because MojoFloat64Array owns a buffer JS can
    // adopt; there is no Buffer counterpart, so the alternative is a silent
    // copy — which is exactly what the zero-copy tokens exist to avoid.
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/no Mojo-owned Buffer type/);
  });

  test('float64array generates a zero-copy Span in and MojoFloat64Array out', () => {
    const r = generate(
      '[functions.scale]\njs_name = "scale"\nmojo_fn = "scale"\n' +
        'args = ["float64array", "number"]\nreturns = "float64array"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('from napi.framework.js_mojo_array import MojoFloat64Array');
    expect(out).toContain('JsTypedArray.is_typedarray(_b, env, args[0])');
    expect(out).toContain('Span[Float64](unsafe_ptr=_ta_mojo_arg0.data_ptr_float64(_b, env)');
    expect(out).toContain('return mojo_result.to_js(_b, env)');
  });

  test('async now goes past 4 args, via the heap-argv path', () => {
    const r = generate(
      '[functions.wide]\njs_name = "wide"\nasync = true\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\n' +
        'execute_body = """\nptr[].result = ptr[].input0\n"""\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('var _argv = unsafe_alloc[NapiValue](5)');
    expect(out).toContain('var input4: Float64');
  });

  test('an async string result transfers rather than copies in __moveinit__', () => {
    const r = generate(
      '[functions.label]\njs_name = "label"\nasync = true\nreturns = "string"\n' +
        'args = ["string"]\nexecute_body = """\nptr[].result = ptr[].input0\n"""\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    expect(out).toContain('var result: String');
    // String is not ImplicitlyCopyable: the move ctor must transfer both the
    // input and the result, or the struct does not compile.
    expect(out).toContain('self.input0 = take.input0^');
    expect(out).toContain('self.result = take.result^');
    expect(out).toContain('self.result = String()');
  });

  test('async still refuses argument and return tokens it cannot hold', () => {
    const r = generate(
      '[functions.bad]\njs_name = "bad"\nasync = true\nreturns = "object"\n' +
        'args = ["number"]\nexecute_body = """\nptr[].result = 0\n"""\n'
    );
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/return type "object" is not supported for async/);
  });

  test('class members are capped at 4 args', () => {
    const r = generate(
      '[classes.thing]\njs_name = "Thing"\n\n' +
        '[classes.thing.instance_methods.wide]\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\nbody = """\nreturn arg0\n"""\n'
    );
    expect(r.code).toBe(1);
    expect(r.stderr).toMatch(/class method "thing\.wide": 5 args declared/);
  });

  test('a >=5-arg sync function still emits the heap-argv path', () => {
    const r = generate(
      '[functions.sum5]\njs_name = "sum5"\nreturns = "number"\n' +
        'args = ["number", "number", "number", "number", "number"]\n' +
        'body = """\nreturn _a0\n"""\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'callbacks.mojo'), 'utf8');
    // Sync is the one shape that goes past 4 args, and the origin widening on
    // the alloc'd buffer is what an earlier template bug got wrong.
    expect(out).toContain('var _argv = unsafe_alloc[NapiValue](5)');
    expect(out).toContain('_argv.as_unsafe_any_origin()');
    expect(out).toContain('var _a4 = _argv[unsafe_offset=4]');
    expect(out).toContain('_argv.unsafe_free()');
  });

  test('field names that collide with the converter\'s identifiers emit distinct locals', () => {
    const r = generate(
      '[structs.thing]\njs_name = "Thing"\n[structs.thing.fields]\n' +
        'obj = "number"\nval = "string"\nb = "int32"\nenv = "boolean"\n'
    );
    expect(r.code).toBe(0);
    const out = fs.readFileSync(path.join(r.dir, 'generated', 'structs.mojo'), 'utf8');
    const fromJs = out.slice(out.indexOf('def thing_from_js'), out.indexOf('def thing_to_js'));
    // The converter's own local and parameters must survive intact...
    expect(fromJs).toContain('var obj = JsObject(val)');
    // ...and every field local must be distinct from them.
    for (const f of ['obj', 'val', 'b', 'env']) {
      expect(fromJs).toContain(`var _f_${f} = `);
      expect(fromJs).not.toMatch(new RegExp(`^\\s*var ${f} = (?!JsObject)`, 'm'));
    }
    expect(fromJs).toContain('return ThingData(_f_obj, _f_val, _f_b, _f_env)');
  });
});
