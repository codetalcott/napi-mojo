// Guards a failure mode that is otherwise invisible.
//
// parallelize_safe() needs the Mojo async runtime initialized, which
// init_async_runtime() does by resolving a symbol out of
// libKGENCompilerRTShared. When a nightly renames that symbol the lookup
// throws and parallelize_safe() runs its work SEQUENTIALLY instead: results
// stay correct, the build stays green, every other test stays green, and all
// thread parallelism is gone. dev2026072306 did exactly that and it went
// unnoticed until someone read the source.
//
// So this asserts the init actually succeeds. It runs on both CI matrix OSes,
// which also settles whether a future symbol change is Darwin-only.

const addon = require('../build/index.node');

describe('async runtime', () => {
  test('asyncRuntimeInitOk() returns a boolean', () => {
    expect(typeof addon.asyncRuntimeInitOk()).toBe('boolean');
  });

  test('async runtime initializes, so parallelize_safe() dispatches to threads', () => {
    // A false here is not a crash — it means parallel work silently became
    // sequential. Check the symbol name in src/napi/framework/runtime.mojo
    // against `dyld_info -exports` (macOS) / `nm -D` (Linux) on
    // libKGENCompilerRTShared; `nm -gU` shows nothing useful there.
    expect(addon.asyncRuntimeInitOk()).toBe(true);
  });

  test('init is idempotent across repeated calls', () => {
    for (let i = 0; i < 5; i++) {
      expect(addon.asyncRuntimeInitOk()).toBe(true);
    }
  });
});
