#/bin/bash -eEu

LLVM_SRC="$(readlink -nf llvm-project/llvm)"
LLVM_BIN="$(readlink -nf llvm.bin.scratch)"
LLVM_BUILD="$(readlink -nf /tmp/llvm.build)"

rm -rf "$LLVM_BUILD" || true
rm -rf "$LLVM_BIN" || true

mkdir -p "$LLVM_BUILD"
pushd "$LLVM_BUILD"

cmake -G Ninja \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;lld" \
  -DCMAKE_INSTALL_PREFIX="$LLVM_BIN" \
  -DLLVM_BUILD_EXTERNAL_COMPILER_RT=ON \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DLIBCXX_USE_COMPILER_RT=YES \
  -DLIBCXXABI_USE_COMPILER_RT=YES \
  -DLLVM_ENABLE_DUMP=ON \
  -DLLVM_BUILD_LLVM_DYLIB=ON \
  -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON -DLLVM_INSTALL_CCTOOLS_SYMLINKS=ON \
  -DLLVM_PARALLEL_COMPILE_JOBS=8 -DLLVM_PARALLEL_LINK_JOBS=8 \
  "$LLVM_SRC"

cmake --build . --target install
popd
rm -rf "$LLVM_BUILD" || true
