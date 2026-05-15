## src/napi/framework/instance_data.mojo — typed per-env singleton state
##
## Wraps napi_set_instance_data / napi_get_instance_data with heap-alloc +
## generic finalizer plumbing, so consumers can stash typed Mojo state on
## the napi_env without writing the alloc/init/finalize/bitcast dance.
##
## LIMITATION: N-API provides exactly one instance-data slot per env. If two
## unrelated consumers both call set_instance_data, the second overwrites the
## first (and its finalizer runs on overwrite). Build a registry on top if
## you need multiple slots.

from std.memory import alloc
from napi.types import NapiEnv
from napi.bindings import Bindings
from napi.raw import raw_set_instance_data, raw_get_instance_data
from napi.error import check_status


def set_instance_data[T: Movable & ImplicitlyDestructible](
    b: Bindings, env: NapiEnv, var value: T
) raises:
    """Heap-allocate `value` and register it as the env's instance data.

    Installs an auto-finalizer that destroys the pointee and frees the slot
    when the env is torn down (or when overwritten by a later call).
    """
    var data_ptr = alloc[T](1)
    data_ptr.init_pointee_move(value^)
    var fin_ref = _typed_instance_data_finalize[T]
    var fin_ptr = UnsafePointer(to=fin_ref).bitcast[
        OpaquePointer[MutAnyOrigin]
    ]()[]
    check_status(
        raw_set_instance_data(
            b,
            env,
            data_ptr.bitcast[NoneType](),
            fin_ptr,
            OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
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


def _typed_instance_data_finalize[T: Movable & ImplicitlyDestructible](
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[T]()
    ptr.destroy_pointee()
    ptr.free()
