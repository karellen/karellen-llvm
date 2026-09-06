#!/bin/bash

set -eEux
set -o pipefail

OLD_PATH=$PATH
PYTHON=$(which python)
PYTHON_VER="$($PYTHON -c 'import sys; print("".join(map(str, sys.version_info[:2])))')"
PYTHON_VENV="$(readlink -nf ./venv-cp$PYTHON_VER)"
$PYTHON -m venv $PYTHON_VENV
PATH=$PYTHON_VENV/bin:$OLD_PATH
export PATH
PYTHON=$PYTHON_VENV/bin/python

"$PYTHON" -m pip install --no-input $(ls -f wheels/*py3-none*.whl wheels/*cp$PYTHON_VER*.whl 2>/dev/null || true)
"$PYTHON" -c pass
which clang
clang --version
which lldb
lldb --version
$PYTHON -c "import lldb;"

############################################################
# LLVM development files: prove an out-of-tree C++ project can
# find, compile and link against the installed headers, CMake
# package and libLLVM, and that the IR tools round-trip.
############################################################

CMAKE_BIN="$(command -v cmake3 || command -v cmake)"
SMOKE_SRC="$(readlink -nf ./tests/dev-smoke)"
SMOKE_BUILD="$(readlink -nf .)/dev-smoke.build-cp$PYTHON_VER"

llvm-config --version
llvm-config --includedir
llvm-config --libdir
# llvm-config must describe the tree it was installed into, not the build tree.
test -f "$(llvm-config --includedir)/llvm/IR/Module.h"
test -f "$(llvm-config --includedir)/llvm/Config/llvm-config.h"
test -f "$(llvm-config --libdir)/cmake/llvm/LLVMConfig.cmake"

rm -rf "$SMOKE_BUILD"
"$CMAKE_BIN" -G Ninja -S "$SMOKE_SRC" -B "$SMOKE_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$PYTHON_VENV/bin/clang" \
    -DCMAKE_CXX_COMPILER="$PYTHON_VENV/bin/clang++" \
    -DLLVM_DIR="$(llvm-config --libdir)/cmake/llvm"
"$CMAKE_BIN" --build "$SMOKE_BUILD"

# Deliberately no LD_LIBRARY_PATH: the executable must resolve libLLVM *and*
# the libc++ runtimes purely through the rpath dev-smoke derives from
# LLVMConfig.cmake, which is what an installed consumer has to rely on.
"$SMOKE_BUILD/llvm-dev-smoke" > "$SMOKE_BUILD/out.ll" 2> "$SMOKE_BUILD/out.log"
cat "$SMOKE_BUILD/out.log"
cat "$SMOKE_BUILD/out.ll"
grep -q "llvm-dev-smoke: LLVM .* OK" "$SMOKE_BUILD/out.log"
# The default -O2 pipeline must have folded 40 + 2 into a constant.
grep -q "ret i32 42" "$SMOKE_BUILD/out.ll"

# The IR tools ship in the same wheel and must handle what the library emits.
llvm-as "$SMOKE_BUILD/out.ll" -o "$SMOKE_BUILD/out.bc"
llvm-extract -func=answer "$SMOKE_BUILD/out.bc" -o "$SMOKE_BUILD/answer.bc"
llvm-extract -func=negate "$SMOKE_BUILD/out.bc" -o "$SMOKE_BUILD/negate.bc"
llvm-link "$SMOKE_BUILD/answer.bc" "$SMOKE_BUILD/negate.bc" -o "$SMOKE_BUILD/linked.bc"
opt -O2 "$SMOKE_BUILD/linked.bc" -o "$SMOKE_BUILD/opt.bc"
llvm-dis "$SMOKE_BUILD/opt.bc" -o "$SMOKE_BUILD/opt.ll"
cat "$SMOKE_BUILD/opt.ll"
# Both extracted functions must have survived the extract/link round-trip.
grep -q "define .*@answer" "$SMOKE_BUILD/opt.ll"
grep -q "define .*@negate" "$SMOKE_BUILD/opt.ll"
llc "$SMOKE_BUILD/opt.bc" -o "$SMOKE_BUILD/opt.s"
grep -q "answer" "$SMOKE_BUILD/opt.s"

