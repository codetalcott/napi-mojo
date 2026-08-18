'use strict';
// A Worker gets its own napi_env: Node re-invokes napi_register_module_v1
// for it, so the addon allocates a SECOND NapiBindings, a second per-env
// instance-data slot, and a second ClassRegistry. Nothing in the framework
// may assume one env per process — Mojo has no module-level globals, which
// is what makes this hold by construction, and this suite is what keeps it
// held on purpose rather than by accident.
const { Worker } = require('worker_threads');
const path = require('path');

const addon = require('../build/index.node');
const ADDON = path.join(__dirname, '..', 'build', 'index.node');

function runWorker(code) {
  return new Promise((resolve, reject) => {
    const w = new Worker(code, { eval: true, workerData: { addon: ADDON } });
    const msgs = [];
    w.on('message', (m) => msgs.push(m));
    w.on('error', reject);
    w.on('exit', (c) =>
      c === 0 ? resolve(msgs) : reject(new Error(`worker exited with ${c}`))
    );
  });
}

describe('worker_threads (second napi_env)', () => {
  test('addon loads and runs in a Worker', async () => {
    const msgs = await runWorker(`
      const { parentPort, workerData } = require('worker_threads');
      const m = require(workerData.addon);
      parentPort.postMessage(m.greet('worker'));
    `);
    expect(msgs).toContain('Hello, worker!');
  });

  test('instance data is per-env: worker writes do not leak into the main env', async () => {
    addon.setTypedInstanceData(11);
    const msgs = await runWorker(`
      const { parentPort, workerData } = require('worker_threads');
      const m = require(workerData.addon);
      m.setTypedInstanceData(99);
      parentPort.postMessage(m.getTypedInstanceData());
    `);
    expect(msgs).toContain(99);
    // The worker's write went to ITS env's slot, not ours.
    expect(addon.getTypedInstanceData()).toBe(11);
  });

  test('classes work in a Worker (per-env ClassRegistry + type tags)', async () => {
    const msgs = await runWorker(`
      const { parentPort, workerData } = require('worker_threads');
      const m = require(workerData.addon);
      const c = new m.Counter(5);
      c.increment();
      const dog = new m.Dog('Rex', 'Lab');
      parentPort.postMessage({ counter: c.value, speak: dog.speak() });
    `);
    expect(msgs[0]).toEqual({ counter: 6, speak: 'Rex says hello' });
  });

  test('TSFN progress callbacks fire inside a Worker env', async () => {
    const msgs = await runWorker(`
      const { parentPort, workerData } = require('worker_threads');
      const m = require(workerData.addon);
      (async () => {
        const seen = [];
        const total = await m.asyncProgress(3, (v) => seen.push(v));
        parentPort.postMessage({ total, seen });
      })().catch((e) => {
        process.exitCode = 1;
        parentPort.postMessage({ error: String(e) });
      });
    `);
    expect(msgs[0]).toEqual({ total: 3, seen: [0, 1, 2] });
  });

  test('async work resolves in a Worker while the main env also works', async () => {
    const [workerMsgs, mainResult] = await Promise.all([
      runWorker(`
        const { parentPort, workerData } = require('worker_threads');
        const m = require(workerData.addon);
        m.asyncDouble(21).then((v) => parentPort.postMessage(v));
      `),
      addon.asyncDouble(4),
    ]);
    expect(workerMsgs).toContain(42);
    expect(mainResult).toBe(8);
  });
});
