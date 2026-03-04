const addon = require('../build/index.node');

describe('Exception Handling', () => {
  // throwValue — throws any JS value as an exception

  test('throwValue throws a string', () => {
    try {
      addon.throwValue('boom');
      expect(true).toBe(false); // should not reach
    } catch (e) {
      expect(e).toBe('boom');
    }
  });

  test('throwValue throws a number', () => {
    try {
      addon.throwValue(404);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBe(404);
    }
  });

  test('throwValue throws an object', () => {
    try {
      addon.throwValue({ code: 42, msg: 'fail' });
      expect(true).toBe(false);
    } catch (e) {
      expect(e.code).toBe(42);
      expect(e.msg).toBe('fail');
    }
  });

  test('throwValue throws an Error instance', () => {
    const err = new Error('test error');
    try {
      addon.throwValue(err);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBe(err);
      expect(e.message).toBe('test error');
    }
  });

  test('throwValue throws null', () => {
    try {
      addon.throwValue(null);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBe(null);
    }
  });

  test('throwValue throws undefined', () => {
    try {
      addon.throwValue(undefined);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBe(undefined);
    }
  });

  test('throwValue throws a boolean', () => {
    try {
      addon.throwValue(false);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBe(false);
    }
  });

  // catchAndReturn — triggers an internal exception, catches it, returns the value

  test('catchAndReturn recovers a thrown string', () => {
    const result = addon.catchAndReturn('oops');
    expect(result).toBe('oops');
  });

  test('catchAndReturn recovers a thrown object', () => {
    const obj = { x: 1 };
    const result = addon.catchAndReturn(obj);
    expect(result).toBe(obj);
  });

  test('catchAndReturn recovers a thrown Error', () => {
    const err = new Error('recovered');
    const result = addon.catchAndReturn(err);
    expect(result).toBe(err);
    expect(result.message).toBe('recovered');
  });

  test('catchAndReturn recovers a thrown number', () => {
    const result = addon.catchAndReturn(42);
    expect(result).toBe(42);
  });
});
