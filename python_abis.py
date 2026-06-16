#!/usr/bin/env python3
"""Single source of truth for the CPython ABIs this project builds for.

Consumed two ways:
  * Python (docker-build.py): ``import python_abis`` and read the values directly.
  * Shell (build-twostage.sh, package-twostage.sh): ``eval "$(python python_abis.py)"``
    which defines PYTHON_ABI_MINORS, PYTHON_DEFAULT_VERSION and PYTHON_BUILD_GLOB.
"""

import sys

# CPython 3.x minor versions to build per-ABI LLDB wheels for.
# Bump this list as the manylinux build image gains or drops versions.
PYTHON_ABI_MINORS = [9, 10, 11, 12, 13, 14]

# Default interpreter for the one-time stage-2 build and the py3-none wheels
# ("314" => CPython 3.14; must be one of PYTHON_ABI_MINORS).
PYTHON_DEFAULT_VERSION = "314"


def build_globs():
    """Per-ABI manylinux interpreter globs: the shared (libpython.so),
    non-free-threaded builds. Free-threaded dirs end in 't', so the trailing
    '[0-9]' excludes them."""
    return [f"/opt/python/cp3{m}-*[0-9]-shared" for m in PYTHON_ABI_MINORS]


def build_glob():
    return " ".join(build_globs())


def emit_shell(out=sys.stdout):
    minors = " ".join(str(m) for m in PYTHON_ABI_MINORS)
    print(f'PYTHON_ABI_MINORS="{minors}"', file=out)
    print(f'PYTHON_DEFAULT_VERSION="{PYTHON_DEFAULT_VERSION}"', file=out)
    print(f'PYTHON_BUILD_GLOB="{build_glob()}"', file=out)


if __name__ == "__main__":
    emit_shell()
