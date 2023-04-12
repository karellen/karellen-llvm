#/bin/bash -eEu

LLVM_SRC="$(readlink -nf llvm-project/llvm)"
LLVM_BIN="$(readlink -nf llvm.bin.scratch)"

rm -rf /tmp/llvm.build || true
rm -rf "$LLVM_BIN" || true

mkdir -p /tmp/llvm.build
pushd /tmp/llvm.build

# -Wdev --debug-output --trace
cmake  -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$LLVM_BIN" \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DLIBCXX_USE_COMPILER_RT=YES -DLIBCXXABI_USE_COMPILER_RT=YES \
  -DLLVM_ENABLE_DUMP=ON \
  -DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON -DLLVM_INSTALL_CCTOOLS_SYMLINKS=ON \
  -DLLVM_PARALLEL_COMPILE_JOBS=8 -DLLVM_PARALLEL_LINK_JOBS=8 \
  "$LLVM_SRC"

#ninja stage2-distribution
#make stage2-distribution

popd
# rm -rf /tmp/llvm.build || true
