## src/addon/class_animal.mojo — Animal and Dog classes (with inheritance)

from std.memory import alloc
from napi.types import (
    NapiEnv,
    NapiValue,
    NAPI_TYPE_STRING,
    NAPI_TYPE_OBJECT,
    NAPI_TYPE_FUNCTION,
)
from napi.bindings import Bindings
from napi.error import throw_js_error, throw_js_type_error, check_status
from napi.raw import raw_wrap
from napi.framework.js_string import JsString
from napi.framework.js_boolean import JsBoolean
from napi.framework.js_object import JsObject
from napi.framework.js_class import unwrap_native, unwrap_native_from_this
from napi.framework.args import CbArgs
from napi.framework.js_value import js_typeof
from napi.framework.register import fn_ptr, ModuleBuilder


struct AnimalData(Movable):
    var name_ptr: OpaquePointer[MutAnyOrigin]
    var name_len: UInt

    def __init__(
        out self, name_ptr: OpaquePointer[MutAnyOrigin], name_len: UInt
    ):
        self.name_ptr = name_ptr
        self.name_len = name_len

    def __moveinit__(out self, deinit take: Self):
        self.name_ptr = take.name_ptr
        self.name_len = take.name_len


struct DogData(Movable):
    var name_ptr: OpaquePointer[MutAnyOrigin]
    var name_len: UInt
    var breed_ptr: OpaquePointer[MutAnyOrigin]
    var breed_len: UInt

    def __init__(
        out self,
        name_ptr: OpaquePointer[MutAnyOrigin],
        name_len: UInt,
        breed_ptr: OpaquePointer[MutAnyOrigin],
        breed_len: UInt,
    ):
        self.name_ptr = name_ptr
        self.name_len = name_len
        self.breed_ptr = breed_ptr
        self.breed_len = breed_len

    def __moveinit__(out self, deinit take: Self):
        self.name_ptr = take.name_ptr
        self.name_len = take.name_len
        self.breed_ptr = take.breed_ptr
        self.breed_len = take.breed_len


def animal_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[AnimalData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()


def dog_finalize(
    env: NapiEnv,
    data: OpaquePointer[MutAnyOrigin],
    hint: OpaquePointer[MutAnyOrigin],
):
    var ptr = data.bitcast[DogData]()
    ptr[].name_ptr.bitcast[Byte]().free()
    ptr[].breed_ptr.bitcast[Byte]().free()
    ptr.destroy_pointee()
    ptr.free()


def animal_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_STRING:
            throw_js_type_error(
                b, env, "Animal constructor requires a string name"
            )
            return NapiValue(unsafe_from_address=0)
        var name_str = JsString.from_napi_value(b, env, arg0)
        var name_len = UInt(name_str.byte_length())
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]
        var data_ptr = alloc[AnimalData](1)
        data_ptr.init_pointee_move(
            AnimalData(name_buf.bitcast[NoneType](), name_len)
        )
        var fin_ref = animal_finalize
        var fin_ptr = UnsafePointer(to=fin_ref).bitcast[
            OpaquePointer[MutAnyOrigin]
        ]()[]
        try:
            check_status(
                raw_wrap(
                    b,
                    env,
                    this_val,
                    data_ptr.bitcast[NoneType](),
                    fin_ptr,
                    OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
                    OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
                )
            )
        except e:
            name_buf.free()
            data_ptr.destroy_pointee()
            data_ptr.free()
            raise e^
        return this_val
    except:
        throw_js_error(env, "Animal constructor failed")
        return NapiValue(unsafe_from_address=0)


def animal_get_name_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[AnimalData](a.b, env, a.this_val)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        return JsString.create(a.b, env, name).value
    except:
        throw_js_error(env, "Animal.name getter failed")
        return NapiValue(unsafe_from_address=0)


def animal_speak_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[AnimalData](a.b, env, a.this_val)
        var name_bytes = ptr[].name_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=name_bytes, length=Int(ptr[].name_len))
        var name = String(from_utf8=span)
        var msg = name + " says hello"
        return JsString.create(a.b, env, msg).value
    except:
        throw_js_error(env, "Animal.speak failed")
        return NapiValue(unsafe_from_address=0)


def animal_is_animal_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var arg0 = CbArgs.get_one(b, env, info)
        var t = js_typeof(b, env, arg0)
        if t != NAPI_TYPE_OBJECT and t != NAPI_TYPE_FUNCTION:
            return JsBoolean.create(b, env, False).value
        var result = JsObject(arg0).instance_of(b, env, this_val)
        return JsBoolean.create(b, env, result).value
    except:
        throw_js_error(env, "Animal.isAnimal failed")
        return NapiValue(unsafe_from_address=0)


def dog_constructor_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var b = CbArgs.get_bindings(env, info)
        var this_val = CbArgs.get_this(b, env, info)
        var args = CbArgs.get_two(b, env, info)
        var t0 = js_typeof(b, env, args[0])
        var t1 = js_typeof(b, env, args[1])
        if t0 != NAPI_TYPE_STRING or t1 != NAPI_TYPE_STRING:
            throw_js_type_error(
                b, env, "Dog constructor requires (name: string, breed: string)"
            )
            return NapiValue(unsafe_from_address=0)
        var name_str = JsString.from_napi_value(b, env, args[0])
        var name_len = UInt(name_str.byte_length())
        var name_buf = alloc[Byte](Int(name_len))
        for i in range(Int(name_len)):
            name_buf[i] = name_str.as_bytes()[i]
        try:
            var breed_str = JsString.from_napi_value(b, env, args[1])
            var breed_len = UInt(breed_str.byte_length())
            var breed_buf = alloc[Byte](Int(breed_len))
            for i in range(Int(breed_len)):
                breed_buf[i] = breed_str.as_bytes()[i]
            var data_ptr = alloc[DogData](1)
            data_ptr.init_pointee_move(
                DogData(
                    name_buf.bitcast[NoneType](),
                    name_len,
                    breed_buf.bitcast[NoneType](),
                    breed_len,
                )
            )
            var fin_ref = dog_finalize
            var fin_ptr = UnsafePointer(to=fin_ref).bitcast[
                OpaquePointer[MutAnyOrigin]
            ]()[]
            try:
                check_status(
                    raw_wrap(
                        b,
                        env,
                        this_val,
                        data_ptr.bitcast[NoneType](),
                        fin_ptr,
                        OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
                        OpaquePointer[MutAnyOrigin](unsafe_from_address=0),
                    )
                )
            except e:
                name_buf.free()
                breed_buf.free()
                data_ptr.destroy_pointee()
                data_ptr.free()
                raise e^
        except e:
            name_buf.free()
            raise e^
        return this_val
    except:
        throw_js_error(env, "Dog constructor failed")
        return NapiValue(unsafe_from_address=0)


def dog_get_breed_fn(env: NapiEnv, info: NapiValue) -> NapiValue:
    try:
        var a = CbArgs.get_bindings_and_this(env, info)
        var ptr = unwrap_native_from_this[DogData](a.b, env, a.this_val)
        var breed_bytes = ptr[].breed_ptr.bitcast[Byte]()
        var span = Span[Byte](ptr=breed_bytes, length=Int(ptr[].breed_len))
        var breed = String(from_utf8=span)
        return JsString.create(a.b, env, breed).value
    except:
        throw_js_error(env, "Dog.breed getter failed")
        return NapiValue(unsafe_from_address=0)


def register_animal(mut m: ModuleBuilder) raises:
    var animal_constructor_ref = animal_constructor_fn
    var animal_get_name_ref = animal_get_name_fn
    var animal_speak_ref = animal_speak_fn
    var animal_is_animal_ref = animal_is_animal_fn
    var dog_constructor_ref = dog_constructor_fn
    var dog_get_breed_ref = dog_get_breed_fn
    var animal = m.class_def("Animal", fn_ptr(animal_constructor_ref))
    animal.getter("name", fn_ptr(animal_get_name_ref))
    animal.instance_method("speak", fn_ptr(animal_speak_ref))
    animal.static_method("isAnimal", fn_ptr(animal_is_animal_ref))
    var dog = m.class_def("Dog", fn_ptr(dog_constructor_ref))
    dog.getter("breed", fn_ptr(dog_get_breed_ref))
    dog.inherits(animal)
