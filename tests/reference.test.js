const addon = require('../build/index.node');

test('testRef() round-trips a number through a reference', () => {
  expect(addon.testRef()).toBe(42);
});

test('testRefObject() round-trips an object through a reference', () => {
  const result = addon.testRefObject();
  expect(typeof result).toBe('object');
  expect(result.answer).toBe(42);
});

test('testRefString() round-trips a string through a reference', () => {
  expect(addon.testRefString('hello')).toBe('hello');
});
