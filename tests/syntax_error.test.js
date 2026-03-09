const addon = require('../build/index.node');

describe('throwSyntaxError', () => {
  test('throws a SyntaxError', () => {
    try {
      addon.throwSyntaxError();
      expect(true).toBe(false); // should not reach
    } catch (e) {
      expect(e.name).toBe('SyntaxError');
      expect(e.message).toBe('test syntax error');
    }
  });

  test('has Error-like properties', () => {
    try {
      addon.throwSyntaxError();
    } catch (e) {
      // Cross-realm: use name check instead of instanceof
      expect(e.name).toBe('SyntaxError');
      expect(typeof e.message).toBe('string');
    }
  });
});
