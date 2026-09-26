## A host program that imports a package from a library include root:
##
##   napi-mojo run tests/fixtures/library-roots/app/main.mojo \
##       -I tests/fixtures/library-roots/lib

from napi.types import NapiEnv, NapiValue
from napi.bindings import Bindings
from napi.framework.js_host import NodeHost
from napi.framework.js_number import JsNumber

from greeting import greeting


def mojo_main(b: Bindings, env: NapiEnv, ctx: NapiValue) raises -> NapiValue:
    var host = NodeHost.from_context(b, env, ctx)
    host.console_log(greeting())
    return JsNumber.create_int(b, env, 0).value
