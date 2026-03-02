## src/napi/error.mojo — N-API error handling
##
## Provides `check_status()` which every N-API call must use after receiving
## its NapiStatus return value. Satisfies the CONTRIBUTING.md requirement:
## "Every N-API call returning napi_status must be immediately passed to
## check_status()."
##
## NapiError struct is defined for future use (e.g., typed error propagation
## in Phase 4+). Currently check_status() raises a built-in Error with a
## formatted message, which is compatible with Mojo v26.2's raises system.

from napi.types import NapiStatus, NAPI_OK

# ---------------------------------------------------------------------------
# NapiError — typed wrapper around a failed napi_status code
#
# Kept for future use when Mojo's error system supports raising custom struct
# types. Currently check_status() raises Error(...) with a string message.
# ---------------------------------------------------------------------------
struct NapiError:
    ## The raw napi_status code that caused the error.
    var status: NapiStatus

    fn __init__(out self, status: NapiStatus):
        self.status = status

    fn __str__(self) -> String:
        return "NapiError: status=" + String(self.status)

# ---------------------------------------------------------------------------
# check_status — verify every N-API call succeeded
#
# Call immediately after every N-API function that returns NapiStatus.
# Raises if status != napi_ok (0).
#
# Usage:
#   var status = raw_create_string_utf8(env, str_ptr, len, result_ptr)
#   check_status(status)
# ---------------------------------------------------------------------------
fn check_status(status: NapiStatus) raises:
    if status != NAPI_OK:
        raise Error("NapiError: status=" + String(status))
