## A library reached through `napi-mojo run -I`, for the "Host-mode program
## with library include roots" CI step. The step copies this directory, edits
## the string below and expects the next run to print the new one — through
## the -I root, and again through a symlink beside the entry.


def greeting() -> String:
    return "hello from a library root"
