/* src/napi_callbacks.c — C trampolines for N-API callbacks
 *
 * Mojo 1.0.0b1 doesn't expose a way to obtain a thin C-ABI function pointer
 * to a `def`. The address-of-local-var pattern (`var f = my_def_fn;
 * UnsafePointer(to=f).bitcast[OpaquePointer]()[]`) extracts the AnyTrait
 * wrapper struct's first 8 bytes — a sentinel/discriminant, not the
 * function's code address. When N-API later calls that "pointer" at env
 * teardown, on Linux it lands on unmapped memory (SIGSEGV); on macOS it
 * usually lands on benign garbage. Hence the platform-skewed flake.
 *
 * @export(ABI="C") emits a real C symbol but only when the function lives
 * in the top-level compilation unit (lib.mojo), and even then we have no
 * way to take its address from Mojo. The standard workaround used by other
 * Mojo-as-C-callback projects (e.g., wgpu-mojo) is what we do here:
 *
 *   1. Each callback body lives in lib.mojo as @export("..._impl", ABI="C").
 *   2. A C trampoline forwards the args to the Mojo impl by name.
 *   3. The C function's address is taken normally (C has no DCE issues
 *      with function-pointer use; the trampoline is referenced from the
 *      cb_table below so it survives).
 *   4. We bundle the trampoline addresses into NapiMojoCallbackTable and
 *      hand the struct pointer to Mojo via napi_mojo_register_module.
 *      Mojo copies the addresses into NapiBindings so every callsite can
 *      read them via the existing CbArgs.get_bindings(...) pipeline.
 *   5. C also owns napi_register_module_v1 (the symbol Node looks up).
 *      It just delegates to napi_mojo_register_module after wiring the
 *      cb_table.
 *
 * Result: cross-platform, no dlsym dance, no platform-specific RTLD_LOCAL
 * visibility issues.
 */

#include <stddef.h>

/* N-API opaque types — we only need them as void* here. */
typedef struct napi_env__* napi_env;
typedef struct napi_value__* napi_value;

/* napi_finalize signature: void (*)(napi_env, void* data, void* hint). */
typedef void (*napi_mojo_finalize_fn)(napi_env, void*, void*);
/* napi_cleanup_hook signature: void (*)(void* arg). */
typedef void (*napi_mojo_cleanup_hook_fn)(void*);
/* napi_async_cleanup_hook signature: void (*)(handle, arg). */
typedef void (*napi_mojo_async_cleanup_hook_fn)(void*, void*);

/* Forward declarations — Mojo @export("..._impl", ABI="C") in lib.mojo. */
extern void napi_mojo_instance_data_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_counter_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_animal_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_dog_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_external_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_external_ab_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_noop_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_external_string_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_progress_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_typed_payload_finalize_impl(napi_env, void*, void*);
extern void napi_mojo_typed_instance_data_finalize_impl(
    napi_env, void*, void*);
extern void napi_mojo_cleanup_hook_impl(void*);
extern void napi_mojo_async_cleanup_hook_impl(void*, void*);

/* C trampolines — static so they don't pollute the symbol table. Their
 * addresses live in g_cb_table below, which keeps them reachable. */
static void instance_data_finalize(napi_env env, void* d, void* h) {
    napi_mojo_instance_data_finalize_impl(env, d, h);
}
static void counter_finalize(napi_env env, void* d, void* h) {
    napi_mojo_counter_finalize_impl(env, d, h);
}
static void animal_finalize(napi_env env, void* d, void* h) {
    napi_mojo_animal_finalize_impl(env, d, h);
}
static void dog_finalize(napi_env env, void* d, void* h) {
    napi_mojo_dog_finalize_impl(env, d, h);
}
static void external_finalize(napi_env env, void* d, void* h) {
    napi_mojo_external_finalize_impl(env, d, h);
}
static void external_ab_finalize(napi_env env, void* d, void* h) {
    napi_mojo_external_ab_finalize_impl(env, d, h);
}
static void noop_finalize(napi_env env, void* d, void* h) {
    napi_mojo_noop_finalize_impl(env, d, h);
}
static void external_string_finalize(napi_env env, void* d, void* h) {
    napi_mojo_external_string_finalize_impl(env, d, h);
}
static void progress_finalize(napi_env env, void* d, void* h) {
    napi_mojo_progress_finalize_impl(env, d, h);
}
static void typed_payload_finalize(napi_env env, void* d, void* h) {
    napi_mojo_typed_payload_finalize_impl(env, d, h);
}
static void typed_instance_data_finalize(napi_env env, void* d, void* h) {
    napi_mojo_typed_instance_data_finalize_impl(env, d, h);
}
static void cleanup_hook(void* arg) {
    napi_mojo_cleanup_hook_impl(arg);
}
static void async_cleanup_hook(void* handle, void* arg) {
    napi_mojo_async_cleanup_hook_impl(handle, arg);
}

/* Layout MUST match the Mojo NapiMojoCallbackTable struct in bindings.mojo.
 * Order is load-bearing — Mojo reads fields by offset. */
typedef struct {
    napi_mojo_finalize_fn instance_data_finalize;
    napi_mojo_finalize_fn counter_finalize;
    napi_mojo_finalize_fn animal_finalize;
    napi_mojo_finalize_fn dog_finalize;
    napi_mojo_finalize_fn external_finalize;
    napi_mojo_finalize_fn external_ab_finalize;
    napi_mojo_finalize_fn noop_finalize;
    napi_mojo_finalize_fn external_string_finalize;
    napi_mojo_finalize_fn progress_finalize;
    napi_mojo_finalize_fn typed_payload_finalize;
    napi_mojo_finalize_fn typed_instance_data_finalize;
    napi_mojo_cleanup_hook_fn cleanup_hook;
    napi_mojo_async_cleanup_hook_fn async_cleanup_hook;
} NapiMojoCallbackTable;

static const NapiMojoCallbackTable g_cb_table = {
    .instance_data_finalize       = instance_data_finalize,
    .counter_finalize             = counter_finalize,
    .animal_finalize              = animal_finalize,
    .dog_finalize                 = dog_finalize,
    .external_finalize            = external_finalize,
    .external_ab_finalize         = external_ab_finalize,
    .noop_finalize                = noop_finalize,
    .external_string_finalize     = external_string_finalize,
    .progress_finalize            = progress_finalize,
    .typed_payload_finalize       = typed_payload_finalize,
    .typed_instance_data_finalize = typed_instance_data_finalize,
    .cleanup_hook                 = cleanup_hook,
    .async_cleanup_hook           = async_cleanup_hook,
};

/* The Mojo entry point we delegate to. Mojo declares this with
 * @export("napi_mojo_register_module", ABI="C"). */
extern napi_value napi_mojo_register_module(
    napi_env env, napi_value exports, const NapiMojoCallbackTable* cb_table);

/* The actual N-API entry point. Node finds this by symbol name. */
napi_value napi_register_module_v1(napi_env env, napi_value exports) {
    return napi_mojo_register_module(env, exports, &g_cb_table);
}
