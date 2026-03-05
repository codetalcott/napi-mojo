const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const addon = require('../build/index.node');

const DTS_PATH = path.join(__dirname, '..', 'build', 'index.d.ts');

beforeAll(() => {
  execSync('node scripts/generate-dts.js', {
    cwd: path.join(__dirname, '..'),
  });
});

test('generate-dts.js produces build/index.d.ts', () => {
  expect(fs.existsSync(DTS_PATH)).toBe(true);
});

test('.d.ts contains export for every addon function', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  const keys = Object.keys(addon).filter(
    k => typeof addon[k] === 'function' && !['Counter', 'Animal', 'Dog'].includes(k)
  );
  for (const key of keys) {
    expect(dts).toMatch(new RegExp(`export function ${key}\\b`));
  }
});

test('.d.ts contains Counter class declaration', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toContain('export class Counter');
  expect(dts).toContain('constructor(');
  expect(dts).toContain('increment()');
  expect(dts).toContain('reset()');
  expect(dts).toContain('value:');
  expect(dts).toContain('static isCounter(');
  expect(dts).toContain('static fromValue(');
});

test('.d.ts contains Animal and Dog class declarations with inheritance', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toContain('export class Animal');
  expect(dts).toContain('export class Dog extends Animal');
  expect(dts).toContain('static isAnimal(');
  expect(dts).toMatch(/readonly name: string/);
  expect(dts).toMatch(/readonly breed: string/);
});

test('.d.ts has correct Animal constructor params', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/class Animal[\s\S]*?constructor\(name: string\)/);
});

test('.d.ts has correct Dog constructor params', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/class Dog[\s\S]*?constructor\(name: string, breed: string\)/);
});

test('.d.ts has correct return types for Phase 20 functions', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/createExternalArrayBuffer\(size: number\): ArrayBuffer/);
  expect(dts).toMatch(/bigIntFromWords\(sign: number, words: bigint\[\]\): bigint/);
  expect(dts).toMatch(/createDataView\(ab: ArrayBuffer, offset: number, length: number\): DataView/);
});

test('.d.ts has correct return type for hello()', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/export function hello\(\): string/);
});

test('.d.ts has correct signature for add()', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/export function add\(.*number.*number.*\): number/);
});

test('.d.ts has correct signature for asyncDouble()', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/export function asyncDouble\(.*\): Promise</);
});

test('.d.ts has correct return type for addBigInts()', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  expect(dts).toMatch(/export function addBigInts\(.*\): bigint/);
});

test('.d.ts file has balanced braces', () => {
  const dts = fs.readFileSync(DTS_PATH, 'utf8');
  const opens = (dts.match(/\{/g) || []).length;
  const closes = (dts.match(/\}/g) || []).length;
  expect(opens).toBe(closes);
});
