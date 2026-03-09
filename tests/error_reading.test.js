'use strict';
const addon = require('../build/index.node');

describe('getErrorMessage / getErrorStack (Phase 24a)', () => {
  test('getErrorMessage returns message from Error object', () => {
    const err = new Error('test message');
    expect(addon.getErrorMessage(err)).toBe('test message');
  });

  test('getErrorMessage works with custom message', () => {
    const err = new TypeError('type mismatch');
    expect(addon.getErrorMessage(err)).toBe('type mismatch');
  });

  test('getErrorMessage returns empty string for Error with no message', () => {
    const err = new Error();
    expect(addon.getErrorMessage(err)).toBe('');
  });

  test('getErrorStack returns a string containing the error type', () => {
    const err = new Error('stack test');
    const stack = addon.getErrorStack(err);
    expect(typeof stack).toBe('string');
    expect(stack).toContain('Error: stack test');
  });

  test('getErrorStack includes file/line information', () => {
    const err = new Error('location');
    const stack = addon.getErrorStack(err);
    // Stack should have multiple lines (Error + at ... frames)
    expect(stack.split('\n').length).toBeGreaterThan(1);
  });

  test('getErrorMessage works on plain objects with message property', () => {
    const obj = { message: 'plain object message' };
    expect(addon.getErrorMessage(obj)).toBe('plain object message');
  });
});
