const addon = require('../build/index.node');

describe('Version Info', () => {
  // getNapiVersion — returns the highest supported N-API version

  test('getNapiVersion returns a number', () => {
    const v = addon.getNapiVersion();
    expect(typeof v).toBe('number');
  });

  test('getNapiVersion returns a positive integer', () => {
    const v = addon.getNapiVersion();
    expect(v).toBeGreaterThanOrEqual(1);
    expect(Number.isInteger(v)).toBe(true);
  });

  test('getNapiVersion returns at least 10', () => {
    // N-API v10 is the minimum — required for property keys, external strings, buffer-from-arraybuffer
    expect(addon.getNapiVersion()).toBeGreaterThanOrEqual(10);
  });

  // getNodeVersion — returns {major, minor, patch} object

  test('getNodeVersion returns an object with major/minor/patch', () => {
    const v = addon.getNodeVersion();
    expect(v).toHaveProperty('major');
    expect(v).toHaveProperty('minor');
    expect(v).toHaveProperty('patch');
  });

  test('getNodeVersion fields are numbers', () => {
    const v = addon.getNodeVersion();
    expect(typeof v.major).toBe('number');
    expect(typeof v.minor).toBe('number');
    expect(typeof v.patch).toBe('number');
  });

  test('getNodeVersion.major is at least 22', () => {
    // Node.js 22.12+ required for N-API v10
    expect(addon.getNodeVersion().major).toBeGreaterThanOrEqual(22);
  });

  test('getNodeVersion matches process.version', () => {
    const v = addon.getNodeVersion();
    const processVersion = process.version.slice(1).split('.').map(Number);
    expect(v.major).toBe(processVersion[0]);
    expect(v.minor).toBe(processVersion[1]);
    expect(v.patch).toBe(processVersion[2]);
  });
});
