#/bin/bash -eEu

LLVM_SRC="$(readlink -nf llvm-project/llvm)"
LLVM_BIN="$(readlink -nf llvm.libs)"
PATH="$(readlink -nf llvm.bin/bin):$PATH"

rm -rf /tmp/llvm.build || true
rm -rf "$LLVM_BIN" || true

PATH="$(readlink -nf llvm.bin/bin):$PATH"
export PATH

mkdir -p /tmp/llvm.build
pushd /tmp/llvm.build

cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$LLVM_BIN" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_ENABLE_PROJECTS='' \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O3 -g" \
  -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O3 -g" \
  -DLLVM_ENABLE_DUMP=ON -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_PARALLEL_COMPILE_JOBS=8 -DLLVM_PARALLEL_LINK_JOBS=8 \
  "$LLVM_SRC"

cmake --build . --target install
popd

rm -rf /tmp/llvm.build || true
