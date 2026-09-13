'use strict';
// scripts/summarize-crash-reports.mjs prints the macOS crash reports a CI job
// left behind, so an intermittent native crash in CI is diagnosable from the
// job log alone. Until it existed, a Jest worker dying with signal=SIGSEGV
// left nothing behind: the crash report was on a runner that no longer exists.
const { spawnSync } = require('child_process');
const { mkdtempSync, writeFileSync, rmSync, utimesSync } = require('fs');
const os = require('os');
const path = require('path');

const SCRIPT = path.join(__dirname, '..', 'scripts', 'summarize-crash-reports.mjs');

// A .ips file is a one-line JSON header followed by a JSON body.
function ips({ procPath = '/opt/homebrew/bin/node', parentProc = 'node', frames, images, exception }) {
  const header = { app_name: path.basename(procPath), bug_type: '309', timestamp: '2026-09-13 15:47:24.00 -0400' };
  const body = {
    procPath, parentProc, pid: 12522, captureTime: '2026-09-13 15:47:24.4219 -0400',
    exception: exception || { type: 'EXC_BAD_ACCESS', signal: 'SIGSEGV', subtype: 'KERN_INVALID_ADDRESS at 0x0000000000000010' },
    termination: { indicator: 'Segmentation fault: 11' },
    faultingThread: 1,
    threads: [{ frames: [] }, { name: 'V8 worker', frames }],
    usedImages: images,
  };
  return JSON.stringify(header) + '\n' + JSON.stringify(body, null, 2);
}

let dir;
beforeEach(() => { dir = mkdtempSync(path.join(os.tmpdir(), 'crash-reports-')); });
afterEach(() => { rmSync(dir, { recursive: true, force: true }); });

const run = (...args) => spawnSync(process.execPath, [SCRIPT, '--dir', dir, ...args], { encoding: 'utf8' });

test('summarises the faulting thread and marks frames in the addon and the Mojo runtime', () => {
  writeFileSync(path.join(dir, 'node-2026-09-13-154724.ips'), ips({
    images: [
      { name: 'node', path: '/opt/homebrew/bin/node' },
      { name: 'index.node', path: '/Users/runner/work/napi-mojo/build/index.node' },
      { name: 'libKGENCompilerRTShared.dylib', path: '/x/libKGENCompilerRTShared.dylib' },
    ],
    frames: [
      { imageIndex: 2, imageOffset: 4096 },
      { imageIndex: 1, imageOffset: 8192, symbol: 'addon::typed_helpers_ops::typed_payload_finalize' },
      { imageIndex: 0, imageOffset: 12, symbol: 'v8::internal::GlobalHandles::InvokeFirstPassWeakCallbacks' },
    ],
  }));
  const r = run();
  expect(r.status).toBe(0);
  expect(r.stdout).toContain('node-2026-09-13-154724.ips');
  expect(r.stdout).toContain('EXC_BAD_ACCESS');
  expect(r.stdout).toContain('SIGSEGV');
  expect(r.stdout).toContain('parent: node');
  expect(r.stdout).toMatch(/>> *index\.node +addon::typed_helpers_ops::typed_payload_finalize/);
  expect(r.stdout).toMatch(/>> *libKGENCompilerRTShared\.dylib +0x1000/);
  expect(r.stdout).toMatch(/^ {5}node +v8::internal::GlobalHandles/m);
  expect(r.stdout).toContain('Mojo code is in the faulting thread');
});

test('a crash with no Mojo frames says so', () => {
  writeFileSync(path.join(dir, 'node-a.ips'), ips({
    images: [{ name: 'node', path: '/opt/homebrew/bin/node' }],
    frames: [{ imageIndex: 0, imageOffset: 1, symbol: 'uv_run' }],
  }));
  expect(run().stdout).toContain('no Mojo code in the faulting thread');
});

test('only recent reports are summarised, and none is not an error', () => {
  const old = path.join(dir, 'node-old.ips');
  writeFileSync(old, ips({ images: [{ name: 'node' }], frames: [{ imageIndex: 0, imageOffset: 1 }] }));
  const longAgo = new Date(Date.now() - 48 * 3600 * 1000);
  utimesSync(old, longAgo, longAgo);
  const r = run('--since-hours', '6');
  expect(r.status).toBe(0);
  expect(r.stdout).toContain('no crash reports');
  expect(r.stdout).not.toContain('node-old.ips');
});

test('an unreadable report is reported, not fatal', () => {
  writeFileSync(path.join(dir, 'node-broken.ips'), '{"app_name":"node"}\nnot json');
  const r = run();
  expect(r.status).toBe(0);
  expect(r.stdout).toContain('node-broken.ips');
  expect(r.stdout).toMatch(/could not parse/);
});

test('a missing directory is not an error', () => {
  const r = spawnSync(process.execPath, [SCRIPT, '--dir', path.join(dir, 'nope')], { encoding: 'utf8' });
  expect(r.status).toBe(0);
  expect(r.stdout).toContain('no crash reports');
});
