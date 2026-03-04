const addon = require('../build/index.node');

// Jest's VM sandbox breaks cross-realm instanceof for error subtypes,
// so we check error.name instead of using .toThrow(TypeError).

test('throwTypeError() throws a TypeError', () => {
  try {
    addon.throwTypeError();
    throw new Error('should have thrown');
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});

test('throwTypeError() has the right message', () => {
  expect(() => addon.throwTypeError()).toThrow('wrong type');
});

test('throwRangeError() throws a RangeError', () => {
  try {
    addon.throwRangeError();
    throw new Error('should have thrown');
  } catch (e) {
    expect(e.name).toBe('RangeError');
  }
});

test('throwRangeError() has the right message', () => {
  expect(() => addon.throwRangeError()).toThrow('out of range');
});

test('addIntsStrict(3, 4) returns 7', () => {
  expect(addon.addIntsStrict(3, 4)).toBe(7);
});

test('addIntsStrict("a", 1) throws a TypeError', () => {
  try {
    addon.addIntsStrict('a', 1);
    throw new Error('should have thrown');
  } catch (e) {
    expect(e.name).toBe('TypeError');
  }
});
