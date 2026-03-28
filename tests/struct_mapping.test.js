const addon = require('../index');

describe('struct-to-object mapping', () => {
  test('round-trip struct through Mojo', () => {
    const config = { host: 'localhost', port: 8080, verbose: true };
    const result = addon.echoConfig(config);
    expect(result.host).toBe('localhost');
    expect(result.port).toBe(8080);
    expect(result.verbose).toBe(true);
  });

  test('struct with computed field', () => {
    const result = addon.configSummary({ host: 'db', port: 5432, verbose: false });
    expect(result).toBe('db:5432');
  });

  test('preserves all field types', () => {
    const config = { host: '', port: 0, verbose: false };
    const result = addon.echoConfig(config);
    expect(result.host).toBe('');
    expect(result.port).toBe(0);
    expect(result.verbose).toBe(false);
  });

  test('throws on non-object arg', () => {
    expect(() => addon.echoConfig('not an object')).toThrow();
    expect(() => addon.echoConfig(42)).toThrow();
  });

  test('throws on missing field', () => {
    expect(() => addon.echoConfig({ host: 'x' })).toThrow();
  });
});
