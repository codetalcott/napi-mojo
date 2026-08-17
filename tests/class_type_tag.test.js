'use strict';
const addon = require('../build/index.node');

// Regression suite for class-layer type tagging. Before wrap_native /
// tag-verified unwraps, napi_unwrap only proved "some native pointer is
// wrapped here" — borrowing a method onto a foreign wrapped instance
// (Counter.prototype.increment.call(someAnimal)) reinterpreted the wrong
// struct type: memory corruption reachable from pure JS.
//
// Cross-realm note (CLAUDE.md): Jest's sandbox breaks `instanceof TypeError`,
// so assert on e.name instead.

function captureError(fn) {
  try {
    fn();
  } catch (e) {
    return e;
  }
  return undefined;
}

describe('cross-class method borrowing is rejected', () => {
  test('Counter method on an Animal instance throws TypeError', () => {
    const animal = new addon.Animal('Rex');
    const err = captureError(() => addon.Counter.prototype.increment.call(animal));
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
  });

  test('Counter getter on an Animal instance throws TypeError', () => {
    const animal = new addon.Animal('Rex');
    const desc = Object.getOwnPropertyDescriptor(addon.Counter.prototype, 'value');
    const err = captureError(() => desc.get.call(animal));
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
  });

  test('Counter setter on an Animal instance throws TypeError', () => {
    const animal = new addon.Animal('Rex');
    const desc = Object.getOwnPropertyDescriptor(addon.Counter.prototype, 'value');
    const err = captureError(() => desc.set.call(animal, 42));
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
  });

  test('Dog-only getter on an Animal instance throws TypeError', () => {
    // AnimalData is a strict prefix of DogData — reading an Animal as a Dog
    // would read past the allocation, so the Dog tag must match exactly.
    const animal = new addon.Animal('Milo');
    const desc = Object.getOwnPropertyDescriptor(addon.Dog.prototype, 'breed');
    const err = captureError(() => desc.get.call(animal));
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
  });

  test('Animal method on a Counter instance throws TypeError', () => {
    const counter = new addon.Counter(1);
    const err = captureError(() => addon.Animal.prototype.speak.call(counter));
    expect(err).toBeDefined();
    expect(err.name).toBe('TypeError');
  });

  test('Counter method on a plain object still throws', () => {
    expect(() => addon.Counter.prototype.increment.call({})).toThrow();
  });
});

describe('legitimate instances still work after tagging', () => {
  test('Counter round-trip', () => {
    const c = new addon.Counter(5);
    c.increment();
    expect(c.value).toBe(6);
    c.value = 10;
    c.reset();
    expect(c.value).toBe(5);
  });

  test('Counter.fromValue instances are tagged (constructed via napi_new_instance)', () => {
    const c = addon.Counter.fromValue(3);
    c.increment();
    expect(c.value).toBe(4);
  });

  test('inherited Animal methods accept Dog instances (accept-set, not exact tag)', () => {
    const dog = new addon.Dog('Rex', 'Labrador');
    expect(dog.speak()).toBe('Rex says hello');
    expect(dog.name).toBe('Rex');
    expect(dog.breed).toBe('Labrador');
  });

  test('Animal instances unaffected by Dog tag', () => {
    const animal = new addon.Animal('Milo');
    expect(animal.speak()).toBe('Milo says hello');
    expect(animal.name).toBe('Milo');
  });
});
