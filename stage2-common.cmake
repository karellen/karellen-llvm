# stage2-common.cmake
#
# Single source of truth for the optimization / quality settings that MUST be
# identical between:
#   * the stage-2 LLVM/Clang/LLD build, and
#   * every per-Python standalone LLDB build (lldb-multipython driver).
#
# These are intentionally UN-prefixed (no BOOTSTRAP_) because both consumers
# read them as plain cache entries:
#   * stage 2:   twostage.cmake sets CLANG_BOOTSTRAP_CMAKE_ARGS="-C <this file>",
#                so the clang bootstrap passes "-C <this file>" to the stage-2
#                configure (see clang/CMakeLists.txt ExternalProject CMAKE_ARGS).
#   * standalone LLDB: lldb-multipython/CMakeLists.txt passes "-C <this file>"
#                to each ExternalProject configure.
#
# Because both configures consume this exact file, their cache values are
# identical by construction. Verify after a build by diffing the relevant
# entries of <stage2-bins>/CMakeCache.txt against
# <lldb staging build>/CMakeCache.txt.
#
# NOTE: these apply to LLVM/Clang/LLDB *targets*. ABI-critical settings
# (RTTI/EH/assertions/triple/PIC) are NOT here on purpose: a standalone LLDB
# inherits those automatically from the exported LLVMConfig.cmake via
# HandleLLVMOptions, so listing them would be redundant (and a second source of
# truth). This file is only the settings LLVMConfig does *not* carry.

# Build type + flags. CMake's default RelWithDebInfo is "-O2 -g -DNDEBUG"; we
# override to the project's "-O3 -glldb -DNDEBUG".
set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")
set(CMAKE_ASM_FLAGS_RELWITHDEBINFO "-O3 -glldb -DNDEBUG" CACHE STRING "")

# Link-time optimization + debug info layout.
set(LLVM_ENABLE_LTO THIN CACHE STRING "")
set(LLVM_USE_SPLIT_DWARF ON CACHE BOOL "")
set(LLVM_USE_RELATIVE_PATHS_IN_FILES ON CACHE BOOL "")
set(LLVM_USE_RELATIVE_PATHS_IN_DEBUG_INFO ON CACHE BOOL "")

# Feature / dependency parity. LLVM_ENABLE_DUMP changes inline dump() availability
# in LLVM headers, so a consumer (LLDB) must match the dylib it links against.
set(LLVM_ENABLE_DUMP ON CACHE BOOL "")
set(LLVM_ENABLE_TERMINFO OFF CACHE BOOL "")
set(LLVM_ENABLE_LIBEDIT OFF CACHE BOOL "")
set(LLVM_ENABLE_LLD ON CACHE BOOL "")
set(LLVM_ENABLE_LIBCXX ON CACHE BOOL "")
