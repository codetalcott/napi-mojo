// Native class state (`state = "<struct>"` + mojo_fn members) at RUNTIME.
//
// This whole feature shipped in 0.9.0 with compile-only coverage: the kitchen
// sink (tests/codegen/kitchen-sink.toml) generates and COMPILES a state-backed
// class but never loads it, so wrap/unwrap, the type tag, `mut` mutation
// persisting across calls, and the finalizer had never actually run. Tally in
// src/exports.toml exists to be driven from here.

const addon = require('../build/index.node');

describe('native class state — construction and wrapping', () => {
  test('constructor_mojo_fn builds the wrapped state', () => {
    const t = new addon.Tally('counter', 5);
    expect(t.total).toBe(5);
    expect(t.label).toBe('counter');
  });

  test('a String field survives the wrap/unwrap round trip', () => {
    // Not redundant with the case above: `label` is heap-allocated inside the
    // wrapped struct, so a botched move on the way in reads as garbage here
    // rather than as a crash.
    const t = new addon.Tally('a longer label that will not fit inline', 0);
    expect(t.label).toBe('a longer label that will not fit inline');
  });

  test('instances hold independent state', () => {
    const a = new addon.Tally('a', 1);
    const b = new addon.Tally('b', 100);
    a.add(10);
    expect(a.total).toBe(11);
    expect(b.total).toBe(100);
    expect(b.label).toBe('b');
  });
});

describe('native class state — mutation through `mut`', () => {
  test('an instance method mutates state that persists across calls', () => {
    const t = new addon.Tally('t', 0);
    expect(t.add(1)).toBe(1);
    expect(t.add(2)).toBe(3);
    expect(t.add(0.5)).toBe(3.5);
    expect(t.total).toBe(3.5);
  });

  test('a mojo_fn setter writes state the getter reads back', () => {
    const t = new addon.Tally('t', 0);
    t.total = 42;
    expect(t.total).toBe(42);
    t.add(8);
    expect(t.total).toBe(50);
  });

  test('the setter type-checks its value', () => {
    const t = new addon.Tally('t', 0);
    expect(() => {
      t.total = 'not a number';
    }).toThrow(/expected number, got string/);
    // The failed assignment must not have corrupted the state.
    expect(t.total).toBe(0);
  });
});

describe('native class state — static methods', () => {
  test('a static mojo_fn takes no instance', () => {
    expect(addon.Tally.zero()).toBe(0);
    expect(addon.Tally.combine(2, 3)).toBe(5);
  });

  test('a static is callable without any instance existing', () => {
    // Statics do not unwrap, so they must work before any construction has
    // happened. Detached from the class object to make that explicit.
    const { combine } = addon.Tally;
    expect(combine(1.5, 2.5)).toBe(4);
  });

  test('a nullable static return maps to null', () => {
    expect(addon.Tally.parseTotal('zero')).toBe(0);
    expect(addon.Tally.parseTotal('one')).toBe(1);
    expect(addon.Tally.parseTotal('nope')).toBeNull();
  });

  test('a static type-checks its arguments', () => {
    expect(() => addon.Tally.combine('a', 2)).toThrow();
    expect(() => addon.Tally.parseTotal(7)).toThrow();
  });
});

describe('native class state — type tagging', () => {
  // napi_unwrap alone only proves "some native pointer is wrapped here".
  // Borrowing a member onto a foreign wrapped instance must be a TypeError,
  // not a reinterpret of the wrong struct — that is memory corruption
  // reachable from pure JS.

  test('an instance method borrowed onto a foreign wrapped instance throws', () => {
    const counter = new addon.Counter(0);
    expect(() => addon.Tally.prototype.add.call(counter, 1)).toThrow();
  });

  test('a getter borrowed onto a foreign wrapped instance throws', () => {
    const counter = new addon.Counter(0);
    const desc = Object.getOwnPropertyDescriptor(addon.Tally.prototype, 'total');
    expect(() => desc.get.call(counter)).toThrow();
  });

  test('a setter borrowed onto a foreign wrapped instance throws', () => {
    // The setter is the newly generated path, so it gets its own case rather
    // than riding on the method's.
    const counter = new addon.Counter(0);
    const desc = Object.getOwnPropertyDescriptor(addon.Tally.prototype, 'total');
    expect(() => desc.set.call(counter, 1)).toThrow();
  });

  test('members borrowed onto a plain object throw', () => {
    expect(() => addon.Tally.prototype.add.call({}, 1)).toThrow();
  });
});
