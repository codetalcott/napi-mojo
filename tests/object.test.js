// RED: This test will fail until src/lib.mojo exports a createObject() function.
// It validates that createObject() returns a proper empty JavaScript object.

const addon = require('../build/index.node');

test('createObject() returns an empty object', () => {
  const result = addon.createObject();
  expect(typeof result).toBe('object');
  expect(result).not.toBeNull();
  expect(Object.keys(result).length).toBe(0);
});
