const addon = require('../build/index.node');

// --- createExternal / getExternalData round-trip ---

test('createExternal(1, 2) returns a value', () => {
  const ext = addon.createExternal(1, 2);
  expect(ext).toBeDefined();
});

test('typeof external is "object"', () => {
  const ext = addon.createExternal(1, 2);
  expect(typeof ext).toBe('object');
});

test('isExternal returns true for external values', () => {
  const ext = addon.createExternal(1, 2);
  expect(addon.isExternal(ext)).toBe(true);
});

test('isExternal returns false for plain objects', () => {
  expect(addon.isExternal({})).toBe(false);
});

test('isExternal returns false for numbers', () => {
  expect(addon.isExternal(42)).toBe(false);
});

test('isExternal returns false for null', () => {
  expect(addon.isExternal(null)).toBe(false);
});

test('getExternalData retrieves stored values', () => {
  const ext = addon.createExternal(3.14, 2.71);
  const data = addon.getExternalData(ext);
  expect(data.x).toBeCloseTo(3.14);
  expect(data.y).toBeCloseTo(2.71);
});

test('getExternalData with zero values', () => {
  const ext = addon.createExternal(0, 0);
  const data = addon.getExternalData(ext);
  expect(data.x).toBe(0);
  expect(data.y).toBe(0);
});

test('getExternalData with negative values', () => {
  const ext = addon.createExternal(-10, -20);
  const data = addon.getExternalData(ext);
  expect(data.x).toBe(-10);
  expect(data.y).toBe(-20);
});

test('getExternalData on non-external throws TypeError', () => {
  try {
    addon.getExternalData({});
    expect(true).toBe(false); // Should not reach here
  } catch (e) {
    expect(e.name).toBe('TypeError');
    expect(e.message).toContain('expected external');
  }
});

test('multiple externals are independent', () => {
  const a = addon.createExternal(1, 2);
  const b = addon.createExternal(10, 20);
  expect(addon.getExternalData(a)).toEqual({ x: 1, y: 2 });
  expect(addon.getExternalData(b)).toEqual({ x: 10, y: 20 });
});
