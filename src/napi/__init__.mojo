## src/napi/__init__.mojo — package marker
##
## Makes `napi` a Mojo package so src/lib.mojo can import:
##   from napi.types import NapiEnv, NapiValue, ...
##   from napi.raw import raw_create_string_utf8, ...
##   from napi.error import check_status
##   from napi.module import define_property
