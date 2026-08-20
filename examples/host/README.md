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
