const addon = require('../build/index.node');

describe('isError', () => {
  test('returns true for Error', () => {
    expect(addon.isError(new Error('test'))).toBe(true);
  });

  test('returns true for TypeError', () => {
    expect(addon.isError(new TypeError('test'))).toBe(true);
  });

  test('returns true for RangeError', () => {
    expect(addon.isError(new RangeError('test'))).toBe(true);
  });

  test('returns true for SyntaxError', () => {
    expect(addon.isError(new SyntaxError('test'))).toBe(true);
  });

  test('returns false for plain object', () => {
    expect(addon.isError({})).toBe(false);
  });

  test('returns false for string', () => {
    expect(addon.isError('not an error')).toBe(false);
  });

  test('returns false for number', () => {
    expect(addon.isError(42)).toBe(false);
  });

  test('returns false for null', () => {
    expect(addon.isError(null)).toBe(false);
  });

  test('returns false for object with message property', () => {
    expect(addon.isError({ message: 'fake error' })).toBe(false);
  });
});
