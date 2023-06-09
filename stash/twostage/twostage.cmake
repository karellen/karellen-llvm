# Common
set(PACKAGE_VENDOR "Karellen, Inc. (https://karellen.co)" CACHE STRING "")

set(LLVM_ENABLE_PROJECTS "clang;clang-tools-extra;lld;lldb" CACHE STRING "")
set(LLVM_ENABLE_RUNTIMES "compiler-rt;libcxx;libcxxabi;libunwind" CACHE STRING "")
# set(LLVM_TARGET_ARCH Native CACHE STRING "")
set(LLVM_TARGETS_TO_BUILD Native CACHE STRING "")
# set(LLVM_RUNTIME_TARGETS default CACHE STRING "")

set(CLANG_ENABLE_BOOTSTRAP ON CACHE BOOL "")
set(CLANG_BOOTSTRAP_PASSTHROUGH "CMAKE_INSTALL_PREFIX;PYTHON_HOME;PYTHON_EXECUTABLE;Python3_EXECUTABLE;LLVM_TARGETS_TO_BUILD;LLVM_PARALLEL_COMPILE_JOBS;LLVM_PARALLEL_LINK_JOBS" CACHE STRING "")
set(CLANG_BOOTSTRAP_TARGETS check-llvm check-clang check-all runtimes clang-resource-headers CACHE STRING "")

set(LLVM_PARALLEL_LINK_JOBS 1 CACHE STRING "")

# Stage 1
set(LLVM_BUILD_TOOLS OFF CACHE BOOL "")
set(LLVM_INCLUDE_EXAMPLES OFF CACHE BOOL "")
set(LLVM_INCLUDE_TESTS OFF CACHE BOOL "")
set(LLVM_INCLUDE_BENCHMARKS OFF CACHE BOOL "")
set(COMPILER_RT_DEFAULT_TARGET_ONLY ON CACHE BOOL "")

set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -g0" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g0" CACHE STRING "")
set(CMAKE_ASM_FLAGS_RELWITHDEBINFO "-O2 -g0" CACHE STRING "")

# Stage 2
set(BOOTSTRAP_LLVM_BUILD_TOOLS OFF CACHE BOOL "")
set(BOOTSTRAP_LLVM_INCLUDE_EXAMPLES OFF CACHE BOOL "")
set(BOOTSTRAP_LLVM_INCLUDE_TESTS OFF CACHE BOOL "")
set(BOOTSTRAP_LLVM_INCLUDE_BENCHMARKS OFF CACHE BOOL "")

set(BOOTSTRAP_LLVM_ENABLE_DUMP ON CACHE BOOL "")

set(BOOTSTRAP_LLVM_BUILD_LLVM_DYLIB ON CACHE BOOL "")
set(BOOTSTRAP_LLVM_LINK_LLVM_DYLIB ON CACHE BOOL "")
set(BOOTSTRAP_CLANG_LINK_CLANG_DYLIB ON CACHE BOOL "")

set(BOOTSTRAP_LLVM_ENABLE_LTO THIN CACHE BOOL "")
set(BOOTSTRAP_LLVM_ENABLE_TERMINFO OFF CACHE BOOL "")
set(BOOTSTRAP_LLVM_ENABLE_LIBEDIT OFF CACHE BOOL "")
set(BOOTSTRAP_LLVM_ENABLE_LLD ON CACHE BOOL "")
set(BOOTSTRAP_LLVM_ENABLE_LIBCXX ON CACHE BOOL "")

set(BOOTSTRAP_CLANG_DEFAULT_CXX_STDLIB libc++ CACHE STRING "")
set(BOOTSTRAP_CLANG_DEFAULT_LINKER lld CACHE STRING "")
set(BOOTSTRAP_CLANG_DEFAULT_RTLIB compiler-rt CACHE STRING "")
set(BOOTSTRAP_CLANG_DEFAULT_UNWINDLIB libunwind CACHE STRING "")

set(BOOTSTRAP_COMPILER_RT_DEFAULT_TARGET_ONLY ON CACHE BOOL "")
set(BOOTSTRAP_COMPILER_RT_USE_BUILTINS_LIBRARY ON CACHE BOOL "")
set(BOOTSTRAP_SANITIZER_CXX_ABI libc++ CACHE STRING "")
set(BOOTSTRAP_SANITIZER_TEST_CXX libc++ CACHE STRING "")
set(BOOTSTRAP_LIBUNWIND_USE_COMPILER_RT ON CACHE BOOL "")
set(BOOTSTRAP_LIBCXX_USE_COMPILER_RT YES CACHE BOOL "")
set(BOOTSTRAP_LIBCXXABI_USE_COMPILER_RT YES CACHE BOOL "")
set(BOOTSTRAP_LIBCXXABI_USE_LLVM_UNWINDER YES CACHE BOOL "")

set(BOOTSTRAP_LLVM_INSTALL_BINUTILS_SYMLINKS ON CACHE BOOL "")
set(BOOTSTRAP_LLVM_INSTALL_CCTOOLS_SYMLINKS ON CACHE BOOL "")

set(BOOTSTRAP_LLVM_INSTALL_TOOLCHAIN_ONLY ON CACHE BOOL "")

set(BOOTSTRAP_LLVM_USE_SPLIT_DWARF ON CACHE BOOL "")
set(BOOTSTRAP_CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
set(BOOTSTRAP_CMAKE_C_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")
set(BOOTSTRAP_CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")
set(BOOTSTRAP_CMAKE_ASM_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")
