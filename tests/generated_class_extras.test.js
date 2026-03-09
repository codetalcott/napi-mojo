'use strict';
const addon = require('../build/index.node');

describe('ExamplePoint — static methods and setters (Phase 30)', () => {
  test('ExamplePoint.isPoint returns true for ExamplePoint instance', () => {
    const p = new addon.ExamplePoint(1, 2);
    expect(addon.ExamplePoint.isPoint(p)).toBe(true);
  });

  test('ExamplePoint.isPoint returns false for plain object', () => {
    expect(addon.ExamplePoint.isPoint({})).toBe(false);
  });

  test('ExamplePoint.isPoint returns false for null', () => {
    expect(addon.ExamplePoint.isPoint(null)).toBe(false);
  });

  test('setter: p.x = 10 updates x getter', () => {
    const p = new addon.ExamplePoint(1, 2);
    p.x = 10;
    expect(p.x).toBe(10);
  });

  test('setter: p.y = 99 updates y getter', () => {
    const p = new addon.ExamplePoint(1, 2);
    p.y = 99;
    expect(p.y).toBe(99);
  });

  test('setter + sum: after setting x and y, sum reflects new values', () => {
    const p = new addon.ExamplePoint(1, 2);
    p.x = 5;
    p.y = 7;
    expect(p.sum()).toBe(12);
  });
});
