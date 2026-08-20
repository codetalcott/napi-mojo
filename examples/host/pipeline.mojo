## examples/host/pipeline.mojo — the demo that earns the pitch.
##
##   napi-mojo run examples/host/pipeline.mojo -- 200000
##
## A data pipeline split along the line each side is actually good at:
##
##   Mojo   generates the samples and computes the statistics — a tight
##          numeric loop over a List[Float64] with no boundary crossings.
##   Node   does everything Mojo has no answer for in-process: JSON
##          serialization, gzip via zlib, and writing the file to disk.
##
## Note what does NOT happen: the samples never cross into JavaScript. Only
## the finished statistics object does, and the compressed bytes come back as
## a single Buffer. That is the rule the benchmarks in scripts/benchmark.mjs
## measure — roughly ~100 ns per value crossing the boundary, so you cross
## with few coarse values, not many fine ones. Handing 200,000 raw samples to
## JS would cost more than the entire computation.
##
## This is deliberately NOT an HTTP server: when Mojo should own main() and
## serve HTTP itself, the answer is the sibling project mojo-http, not this.
## Host mode is for reaching what the Node ecosystem has and Mojo does not.

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.framework.js_host import NodeHost
from napi.framework.js_number import JsNumber
from napi.framework.js_object import JsObject
from napi.framework.js_string import JsString, js_to_string
from napi.framework.js_value import js_get_global


## A deterministic LCG — same output every run, so CI can assert on it.
def _samples(n: Int) -> List[Float64]:
    var out = List[Float64](capacity=n)
    var state: UInt64 = 0x2545F4914F6CDD1D
    for _ in range(n):
        state = state * 6364136223846793005 + 1442695040888963407
        # Top 24 bits -> [0, 1), scaled into a plausible latency-ish range.
        var unit = Float64((state >> 40) & 0xFFFFFF) / Float64(0xFFFFFF)
        out.append(1.0 + unit * unit * 249.0)
    return out^


struct Stats(Movable):
    var count: Int
    var mean: Float64
    var stddev: Float64
    var p50: Float64
    var p95: Float64
    var p99: Float64

    def __init__(
        out self,
        count: Int,
        mean: Float64,
        stddev: Float64,
        p50: Float64,
        p95: Float64,
        p99: Float64,
    ):
        self.count = count
        self.mean = mean
        self.stddev = stddev
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99

    # No explicit __moveinit__: it errors with "'None' has no attributes" when
    # the struct lives in a file compiled as a main module, and Movable is
    # auto-derived anyway. See the rule in CLAUDE.md.


def _compute(var xs: List[Float64]) -> Stats:
    var n = len(xs)
    var total: Float64 = 0.0
    for i in range(n):
        total += xs[i]
    var mean = total / Float64(n)

    var sq: Float64 = 0.0
    for i in range(n):
        var d = xs[i] - mean
        sq += d * d

    sort(xs)
    return Stats(
        n,
        mean,
        (sq / Float64(n)) ** 0.5,
        xs[n // 2],
        xs[Int(Float64(n) * 0.95)],
        xs[Int(Float64(n) * 0.99)],
    )


def mojo_main(b: Bindings, env: NapiEnv, ctx: NapiValue) raises -> NapiValue:
    var host = NodeHost.from_context(b, env, ctx)

    var n = 200000
    var args = host.argv()
    if len(args) > 0:
        n = Int(Float64(atof(args[0])))

    # --- Mojo's half: no boundary crossings in here at all ----------------
    var stats = _compute(_samples(n))

    # --- One coarse crossing: the finished statistics ---------------------
    var obj = JsObject.create(b, env)
    obj.set_named_property(b, env, "count", JsNumber.create_int(b, env, stats.count).value)
    obj.set_named_property(b, env, "mean", JsNumber.create(b, env, stats.mean).value)
    obj.set_named_property(b, env, "stddev", JsNumber.create(b, env, stats.stddev).value)
    obj.set_named_property(b, env, "p50", JsNumber.create(b, env, stats.p50).value)
    obj.set_named_property(b, env, "p95", JsNumber.create(b, env, stats.p95).value)
    obj.set_named_property(b, env, "p99", JsNumber.create(b, env, stats.p99).value)

    # --- Node's half: serialize, compress, write --------------------------
    var json_global = JsObject(
        js_get_global(b, env).get_named_property(b, env, "JSON")
    )
    var stringify_args = List[NapiValue]()
    stringify_args.append(obj.value)
    var json_str = json_global.call_method(b, env, "stringify", stringify_args)
    var json_text = js_to_string(b, env, json_str)

    var zlib = host.require("zlib")
    var gzip_args = List[NapiValue]()
    gzip_args.append(json_str)
    var gz = JsObject(zlib.call_method(b, env, "gzipSync", gzip_args))
    var gz_len = Int(
        JsNumber.from_napi_value(b, env, gz.get_named_property(b, env, "length"))
    )

    var os_mod = host.require("os")
    var tmpdir = js_to_string(
        b, env, os_mod.call_method(b, env, "tmpdir", List[NapiValue]())
    )
    var path_mod = host.require("path")
    var join_args = List[NapiValue]()
    join_args.append(JsString.create(b, env, tmpdir).value)
    join_args.append(JsString.create(b, env, "napi-mojo-stats.json.gz").value)
    var out_path = path_mod.call_method(b, env, "join", join_args)

    var fs = host.require("fs")
    var write_args = List[NapiValue]()
    write_args.append(out_path)
    write_args.append(gz.value)
    _ = fs.call_method(b, env, "writeFileSync", write_args)

    # Round-trip it back through Node to prove the file is real.
    var read_args = List[NapiValue]()
    read_args.append(out_path)
    var raw = fs.call_method(b, env, "readFileSync", read_args)
    var gunzip_args = List[NapiValue]()
    gunzip_args.append(raw)
    var restored = JsObject(zlib.call_method(b, env, "gunzipSync", gunzip_args))
    var restored_text = js_to_string(
        b,
        env,
        restored.call_method(
            b, env, "toString", _one_str(b, env, String("utf8"))
        ),
    )

    host.console_log("samples      " + String(stats.count) + " (generated in Mojo)")
    host.console_log("mean         " + String(stats.mean))
    host.console_log("p50/p95/p99  " + String(stats.p50) + " / " + String(stats.p95) + " / " + String(stats.p99))
    host.console_log("json         " + String(json_text.byte_length()) + " bytes")
    host.console_log("gzipped      " + String(gz_len) + " bytes (node:zlib)")
    host.console_log("wrote        " + js_to_string(b, env, out_path))
    if restored_text == json_text:
        host.console_log("round-trip   OK")
    else:
        host.console_log("round-trip   MISMATCH")
        return JsNumber.create_int(b, env, 1).value

    return JsNumber.create_int(b, env, 0).value


def _one_str(b: Bindings, env: NapiEnv, s: String) raises -> List[NapiValue]:
    var out = List[NapiValue]()
    out.append(JsString.create(b, env, s).value)
    return out^
