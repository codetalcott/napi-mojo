const addon = require('../build/index.node');

describe('Arbitrary-precision BigInt (words API)', () => {
  // bigIntFromWords(sign, wordsArray) → BigInt
  // bigIntToWords(bigint) → {sign, words}

  test('bigIntFromWords(0, [0]) produces 0n', () => {
    expect(addon.bigIntFromWords(0, [0])).toBe(0n);
  });

  test('bigIntFromWords(0, [1]) produces 1n', () => {
    expect(addon.bigIntFromWords(0, [1])).toBe(1n);
  });

  test('bigIntFromWords(0, [256]) produces 256n', () => {
    expect(addon.bigIntFromWords(0, [256])).toBe(256n);
  });

  test('bigIntFromWords(1, [1]) produces -1n', () => {
    expect(addon.bigIntFromWords(1, [1])).toBe(-1n);
  });

  test('bigIntFromWords(1, [100]) produces -100n', () => {
    expect(addon.bigIntFromWords(1, [100])).toBe(-100n);
  });

  test('bigIntFromWords multi-word: 2^64', () => {
    // 2^64 = word[0]=0, word[1]=1 (little-endian word order)
    expect(addon.bigIntFromWords(0, [0, 1])).toBe(2n ** 64n);
  });

  test('bigIntToWords(1n) returns sign:0, words:[1]', () => {
    const result = addon.bigIntToWords(1n);
    expect(result.sign).toBe(0);
    expect(result.words.length).toBe(1);
    expect(result.words[0]).toBe(1);
  });

  test('bigIntToWords(-1n) returns sign:1', () => {
    const result = addon.bigIntToWords(-1n);
    expect(result.sign).toBe(1);
    expect(result.words.length).toBe(1);
    expect(result.words[0]).toBe(1);
  });

  test('bigIntToWords(2n**64n) returns 2 words', () => {
    const result = addon.bigIntToWords(2n ** 64n);
    expect(result.sign).toBe(0);
    expect(result.words.length).toBe(2);
    expect(result.words[0]).toBe(0);
    expect(result.words[1]).toBe(1);
  });

  test('round-trip: from → to → from preserves value', () => {
    const original = 2n ** 64n + 42n;
    const { sign, words } = addon.bigIntToWords(original);
    const reconstructed = addon.bigIntFromWords(sign, words);
    expect(reconstructed).toBe(original);
  });
});
