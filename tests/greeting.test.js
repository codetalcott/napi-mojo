const addon = require('../build/index.node');

test('makeGreeting() returns an object with message property', () => {
  const result = addon.makeGreeting();
  expect(typeof result).toBe('object');
  expect(result.message).toBe('Hello!');
});
