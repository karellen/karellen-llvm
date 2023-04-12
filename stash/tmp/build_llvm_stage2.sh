#/bin/bash -eEu

LLVM_SRC="$(readlink -nf llvm-project/llvm)"
LLVM_BIN="$(readlink -nf llvm.bin)"

rm -rf /tmp/llvm.build || true
rm -rf "$LLVM_BIN" || true

PATH="$(readlink -nf llvm.bin.scratch/bin):$PATH"
export PATH

mkdir -p /tmp/llvm.build
pushd /tmp/llvm.build

cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$LLVM_BIN" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;lld;lldb" \
  -DLLVM_ENABLE_RUNTIMES="" \
  -DCMAKE_C_FLAGS_RELWITHDEBINFO="-O3 -g" \
  -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O3 -g" \
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
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
  -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON -DLLVM_INSTALL_CCTOOLS_SYMLINKS=ON \
  -DLLVM_PARALLEL_COMPILE_JOBS=8 -DLLVM_PARALLEL_LINK_JOBS=8 \
  "$LLVM_SRC"

#   -DBUILD_SHARED_LIBS=ON \
cmake --build . --target install-distribution
popd
rm -rf /tmp/llvm.build || true
