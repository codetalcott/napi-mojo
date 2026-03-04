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

  test('getNapiVersion returns at least 6', () => {
    // N-API v6 is the minimum for all features we use
    expect(addon.getNapiVersion()).toBeGreaterThanOrEqual(6);
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

  test('getNodeVersion.major is at least 18', () => {
    // Node.js 18+ is required (engines field in package.json)
    expect(addon.getNodeVersion().major).toBeGreaterThanOrEqual(18);
  });

  test('getNodeVersion matches process.version', () => {
    const v = addon.getNodeVersion();
    const processVersion = process.version.slice(1).split('.').map(Number);
    expect(v.major).toBe(processVersion[0]);
    expect(v.minor).toBe(processVersion[1]);
    expect(v.patch).toBe(processVersion[2]);
  });
});
