'use strict';
// Concurrent async work with heap-allocated results.
//
// `returns = "string"` puts a Mojo String in the async data struct, which is
// built on a libuv worker thread and destroyed on the main thread when the
// completion callback deinitializes the struct. The reasoning for why that is
// sound is recorded in CLAUDE.md; what it does NOT establish is behaviour when
// many of those structs are in flight at once, each allocating and freeing on
// a different worker.
//
// This suite is the load. On its own it proves only that results stay correct;
// its real job is to be the workload for the `async-stress` CI job, which runs
// it under Guard Malloc on macOS (MALLOC_STRICT_SIZE=1 turns a heap overrun
// into an immediate fault at the bad access) and under glibc's malloc checks
// on Linux. A UAF or overrun in the async path shows up there, not here.
//
// Sized to stay quick under a normal allocator; the allocators above are
// 10-100x slower, which is why the counts are modest and tunable.
const addon = require('../build/index.node');

const ROUNDS = Number(process.env.NAPI_MOJO_STRESS_ROUNDS || 20);
const WIDTH = Number(process.env.NAPI_MOJO_STRESS_WIDTH || 50);

jest.setTimeout(120000);

describe('concurrent async work', () => {
  test('string results stay correct with many in flight', async () => {
    for (let round = 0; round < ROUNDS; round++) {
      const inputs = Array.from({ length: WIDTH }, (_, i) => `r${round}-${i}`);
      const out = await Promise.all(inputs.map((s) => addon.asyncLabel(s)));
      // Each work item owns its own data struct; a shared or reused buffer
      // would show up as a crossed or repeated result here.
      expect(out).toEqual(inputs.map((s) => `${s} done`));
    }
  });

  test('varying string lengths, so the allocator sees many size classes', async () => {
    const inputs = Array.from({ length: WIDTH }, (_, i) => 'x'.repeat(i * 7 + 1));
    for (let round = 0; round < ROUNDS; round++) {
      const out = await Promise.all(inputs.map((s) => addon.asyncLabel(s)));
      expect(out[0]).toBe('x done');
      expect(out[out.length - 1]).toBe(`${inputs[inputs.length - 1]} done`);
      expect(out).toHaveLength(WIDTH);
    }
  });

  test('string and numeric async interleaved', async () => {
    for (let round = 0; round < ROUNDS; round++) {
      const jobs = [];
      for (let i = 0; i < WIDTH; i++) {
        jobs.push(addon.asyncLabel(`n${i}`));
        jobs.push(addon.asyncSum(i, i));
      }
      const out = await Promise.all(jobs);
      for (let i = 0; i < WIDTH; i++) {
        expect(out[i * 2]).toBe(`n${i} done`);
        expect(out[i * 2 + 1]).toBe(i * 2);
      }
    }
  });

  test('results survive a GC between rounds', async () => {
    const held = [];
    for (let round = 0; round < Math.min(ROUNDS, 5); round++) {
      held.push(...(await Promise.all(
        Array.from({ length: WIDTH }, (_, i) => addon.asyncLabel(`held${round}-${i}`))
      )));
      if (global.gc) global.gc();
    }
    // Strings handed to JS are owned by JS; a premature free in the Mojo side
    // would corrupt these after collection.
    expect(held).toHaveLength(Math.min(ROUNDS, 5) * WIDTH);
    expect(held[0]).toBe('held0-0 done');
    expect(held[held.length - 1]).toBe(`held${Math.min(ROUNDS, 5) - 1}-${WIDTH - 1} done`);
  });
});
