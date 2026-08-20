# Host-mode example

A Mojo program that Node hosts — the inverse of the addon direction.

```bash
napi-mojo run main.mojo -- one two
```

`napi-mojo run` compiles a generated wrapper around `mojo_main`, then launches
Node on a bootstrap that calls it. The `ctx` argument carries
`{ require, argv, cwd }`; `require` is module-scoped in Node, so the bootstrap
hands it in rather than Mojo trying to reach it through `globalThis`.

Scaffold your own with `napi-mojo init <dir> --host`.

## `pipeline.mojo` — the split that makes host mode worth it

```bash
napi-mojo run pipeline.mojo -- 200000
```

Mojo generates 200,000 samples and computes the statistics in a tight numeric
loop. Node does the parts Mojo has no in-process answer for: `JSON.stringify`,
gzip through `node:zlib`, and the file write.

The samples never cross into JavaScript — only the finished statistics object
does, and the compressed bytes come back as one Buffer. That is the rule
`scripts/benchmark.mjs` measures: roughly **~100 ns per value crossing the
boundary**, so cross with few coarse values rather than many fine ones. Handing
200,000 raw samples to JS would cost more than the entire computation.

This is deliberately not an HTTP server. When Mojo should own `main()` and
serve HTTP itself, the answer is the sibling project
[mojo-http](https://github.com/codetalcott/mojo-http), not this. Host mode is
for reaching what the Node ecosystem has and Mojo does not.
