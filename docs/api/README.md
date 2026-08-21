# Framework API reference

Generated from Mojo docstrings by `npm run generate:api-reference`.
Do not edit these files by hand — edit the docstrings in `src/napi/`.

New to napi-mojo? Start with the [tutorial](../TUTORIAL.md); this is the
reference for the framework surface your addon calls into. The demo
addon's own exports are listed separately in [EXPORTS.md](../EXPORTS.md).

## Modules

| module | symbols documented |
|---|---|
| [`args`](args.md) | 48 / 48 |
| [`convert`](convert.md) | 35 / 35 |
| [`error`](error.md) | 18 / 18 |
| [`instance_data`](instance_data.md) | 2 / 2 |
| [`js_array`](js_array.md) | 9 / 9 |
| [`js_boolean`](js_boolean.md) | 5 / 5 |
| [`js_class`](js_class.md) | 16 / 16 |
| [`js_coerce`](js_coerce.md) | 4 / 4 |
| [`js_function`](js_function.md) | 12 / 12 |
| [`js_host`](js_host.md) | 10 / 10 |
| [`js_int32`](js_int32.md) | 5 / 5 |
| [`js_int64`](js_int64.md) | 5 / 5 |
| [`js_null`](js_null.md) | 4 / 4 |
| [`js_number`](js_number.md) | 7 / 7 |
| [`js_object`](js_object.md) | 22 / 22 |
| [`js_uint32`](js_uint32.md) | 5 / 5 |
| [`js_undefined`](js_undefined.md) | 4 / 4 |
| [`js_value`](js_value.md) | 8 / 8 |
| [`runtime`](runtime.md) | 2 / 2 |

## Not yet documented

These modules are below the documentation threshold, so a rendered page
would be mostly bare signatures. Read the source until they clear it —
each carries a module header comment with usage examples.

| module | symbols documented |
|---|---|
| [`async_work.mojo`](../../src/napi/framework/async_work.mojo) | 0 / 10 |
| [`callback_scope.mojo`](../../src/napi/framework/callback_scope.mojo) | 0 / 5 |
| [`escapable_handle_scope.mojo`](../../src/napi/framework/escapable_handle_scope.mojo) | 0 / 6 |
| [`handle_scope.mojo`](../../src/napi/framework/handle_scope.mojo) | 1 / 6 |
| [`js_arraybuffer.mojo`](../../src/napi/framework/js_arraybuffer.mojo) | 0 / 10 |
| [`js_async_context.mojo`](../../src/napi/framework/js_async_context.mojo) | 0 / 8 |
| [`js_bigint.mojo`](../../src/napi/framework/js_bigint.mojo) | 0 / 10 |
| [`js_buffer.mojo`](../../src/napi/framework/js_buffer.mojo) | 0 / 10 |
| [`js_dataview.mojo`](../../src/napi/framework/js_dataview.mojo) | 0 / 9 |
| [`js_date.mojo`](../../src/napi/framework/js_date.mojo) | 0 / 6 |
| [`js_exception.mojo`](../../src/napi/framework/js_exception.mojo) | 0 / 5 |
| [`js_external.mojo`](../../src/napi/framework/js_external.mojo) | 5 / 8 |
| [`js_promise.mojo`](../../src/napi/framework/js_promise.mojo) | 0 / 7 |
| [`js_ref.mojo`](../../src/napi/framework/js_ref.mojo) | 0 / 9 |
| [`js_symbol.mojo`](../../src/napi/framework/js_symbol.mojo) | 0 / 5 |
| [`js_typedarray.mojo`](../../src/napi/framework/js_typedarray.mojo) | 0 / 23 |
| [`js_version.mojo`](../../src/napi/framework/js_version.mojo) | 0 / 5 |
| [`threadsafe_function.mojo`](../../src/napi/framework/threadsafe_function.mojo) | 0 / 9 |
| [`module.mojo`](../../src/napi/module.mojo) | 0 / 2 |

## Not renderable

`mojo doc` compiles its target as a main module, where an explicit
`__moveinit__` fails to compile. These are excluded until that is fixed;
`scripts/check-docstring-coverage.mjs` fails if one starts working.

- [`js_string.mojo`](../../src/napi/framework/js_string.mojo) — explicit __moveinit__ on Latin1Buf
- [`js_mojo_array.mojo`](../../src/napi/framework/js_mojo_array.mojo) — explicit __moveinit__ on MojoFloat64Array
- [`register.mojo`](../../src/napi/framework/register.mojo) — explicit __moveinit__ on ClassRegistry
