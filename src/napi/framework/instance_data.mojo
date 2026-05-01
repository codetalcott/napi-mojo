## src/napi/framework/instance_data.mojo — typed per-env singleton state
##
## Wraps napi_set_instance_data / napi_get_instance_data with heap-alloc +
## explicit-finalizer plumbing, so consumers can stash typed Mojo state on
## the napi_env without writing the alloc/init/bitcast dance.
##
## LIMITATION: N-API provides exactly one instance-data slot per env. If two
## unrelated consumers both call set_instance_data, the second overwrites the
## first (and its finalizer runs on overwrite). Build a registry on top if
## you need multiple slots.
##
## ## Why the caller supplies fin_ptr
##
## Mojo 1.0.0b1 doesn't expose a way to take the address of a `def` and pass
## it as a thin C-ABI fn pointer to a C library — the address-of-local-var
## trick that prior versions used (`var f = my_def; UnsafePointer(to=f)...`)
## now extracts the AnyTrait wrapper's discriminant rather than a code
## address. The cross-platform fix is a per-type C trampoline (see
## src/napi_callbacks.c). Each caller of this helper must register such a
## trampoline for their concrete T and pass its address here. In napi-mojo
## itself the trampolines live in lib.mojo + napi_callbacks.c and the
## addresses come through NapiBindings (e.g. b[].typed_instance_data_finalize_ptr).

from std.memory import alloc
from napi.types import NapiEnv
from napi.bindings import Bindings
from napi.raw import raw_set_instance_data, raw_get_instance_data
from napi.error import check_status


def set_instance_data[T: Movable & ImplicitlyDestructible](
    b: Bindings,
    env: NapiEnv,
    var value: T,
    fin_ptr: OpaquePointer[MutAnyOrigin],
) raises:
    """Heap-allocate `value` and register it as the env's instance data.

    `fin_ptr` is a C-callable finalizer with the signature
    `void(*)(napi_env, void*, void*)` that destroys the heap pointee and
    frees the slot. Caller is responsible for providing one.
    """
    var data_ptr = alloc[T](1)
    data_ptr.init_pointee_move(value^)
    check_status(
        raw_set_instance_data(
            b,
            env,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](),
        )
    )


def get_instance_data[T: AnyType](
    b: Bindings, env: NapiEnv
) raises -> UnsafePointer[T, MutAnyOrigin]:
    """Retrieve the typed instance-data pointer. Raises if unset (NULL)."""
    var raw: Optional[OpaquePointer[MutAnyOrigin]] = None
    check_status(
        raw_get_instance_data(
            b, env, UnsafePointer(to=raw).bitcast[NoneType]()
        )
    )
    if raw is None:
        raise Error("instance data not set")
    return raw.value().bitcast[T]()
