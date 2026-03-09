'use strict';
const addon = require('../build/index.node');

describe('ExamplePoint — generated class (Phase 28)', () => {
  test('ExamplePoint is a constructor', () => {
    expect(typeof addon.ExamplePoint).toBe('function');
  });

  test('new ExamplePoint(3, 4) creates an instance', () => {
    const p = new addon.ExamplePoint(3, 4);
    expect(p).toBeInstanceOf(addon.ExamplePoint);
  });

  test('x getter returns x coordinate', () => {
    const p = new addon.ExamplePoint(3, 4);
    expect(p.x).toBe(3);
  });

  test('y getter returns y coordinate', () => {
    const p = new addon.ExamplePoint(3, 4);
    expect(p.y).toBe(4);
  });

  test('sum() method returns x + y', () => {
    const p = new addon.ExamplePoint(3, 4);
    expect(p.sum()).toBe(7);
  });

  test('sum() works with floating point', () => {
    const p = new addon.ExamplePoint(1.5, 2.5);
    expect(p.sum()).toBe(4);
  });

  test('throws TypeError if x is not a number', () => {
    expect(() => new addon.ExamplePoint('a', 4)).toThrow();
  });

  test('throws TypeError if y is not a number', () => {
    expect(() => new addon.ExamplePoint(3, 'b')).toThrow();
  });

  test('multiple instances are independent', () => {
    const p1 = new addon.ExamplePoint(1, 2);
    const p2 = new addon.ExamplePoint(10, 20);
    expect(p1.x).toBe(1);
    expect(p2.x).toBe(10);
    expect(p1.sum()).toBe(3);
    expect(p2.sum()).toBe(30);
  });
});
