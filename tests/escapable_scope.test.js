const addon = require('../build/index.node');

test('buildInScope() returns an object', () => {
  const result = addon.buildInScope();
  expect(typeof result).toBe('object');
});

test('buildInScope() has created: true', () => {
  const result = addon.buildInScope();
  expect(result.created).toBe(true);
});

test('buildInScope() has answer: 42', () => {
  const result = addon.buildInScope();
  expect(result.answer).toBe(42);
});
