# `instance_data`

Source: [`src/napi/framework/instance_data.mojo`](../../src/napi/framework/instance_data.mojo)

---

## Functions

### `set_instance_data`

```mojo
def set_instance_data[T: Deinitable & Movable](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin], var value: T)
```

Heap-allocate `value` and register it as the env's instance data.

Installs an auto-finalizer that destroys the pointee and frees the slot
when the env is torn down (or when overwritten by a later call).

### `get_instance_data`

```mojo
def get_instance_data[T: AnyType](b: Pointer[NapiBindings, MutUntrackedOrigin], env: Pointer[NoneType, MutUntrackedOrigin]) -> Pointer[T, MutAnyOrigin]
```

Retrieve the typed instance-data pointer. Raises if unset (NULL).
