## examples/host/main.mojo — a Mojo program that Node hosts.
##
## The inverse of every other example here. Instead of JavaScript calling into
## a Mojo addon, this is a Mojo PROGRAM that drives Node and uses the Node
## runtime and npm as its standard library.
##
##   napi-mojo run examples/host/main.mojo -- one two
##
## There is no napi_register_module_v1 in this file: `napi-mojo run` generates
## the wrapper that registers mojo_main, then launches Node on a bootstrap
## that calls it. `ctx` carries { require, argv, cwd } from that bootstrap —
## `require` is module-scoped and cannot be reached from Mojo any other way.

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.framework.js_host import NodeHost
from napi.framework.js_number import JsNumber
from napi.framework.js_string import JsString, js_to_string


def mojo_main(b: Bindings, env: NapiEnv, ctx: NapiValue) raises -> NapiValue:
    var host = NodeHost.from_context(b, env, ctx)

    host.console_log("hello from Mojo, hosted by Node")

    # Node builtins, called from Mojo with `this` bound correctly.
    var os_mod = host.require("os")
    var platform = os_mod.call_method(b, env, "platform", List[NapiValue]())
    host.console_log("platform: " + js_to_string(b, env, platform))

    var path_mod = host.require("path")
    var join_args = List[NapiValue]()
    join_args.append(JsString.create(b, env, "usr").value)
    join_args.append(JsString.create(b, env, "local").value)
    join_args.append(JsString.create(b, env, "bin").value)
    var joined = path_mod.call_method(b, env, "join", join_args)
    host.console_log("joined: " + js_to_string(b, env, joined))

    # Arguments after `--` on the napi-mojo run command line.
    var args = host.argv()
    host.console_log("argc: " + String(len(args)))
    for i in range(len(args)):
        host.console_log("  argv[" + String(i) + "]: " + args[i])

    # A number returned from mojo_main becomes the process exit code.
    return JsNumber.create_int(b, env, 0).value
