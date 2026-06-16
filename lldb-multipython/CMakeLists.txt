# lldb-multipython — repo-owned orchestration driver
#
# Builds a *standalone* LLDB once per Python ABI against an already-built
# two-stage LLVM/Clang, so we never rebuild LLVM/Clang per Python. Each Python
# yields its own liblldb linked to that interpreter's libpython.
#
# This is the "loop in CMake over a parameter containing Python versions" — a
# foreach() that emits one ExternalProject per Python. LLVM/Clang are consumed
# as prebuilt external libraries (LLDB_BUILT_STANDALONE), which is a first-class
# upstream LLDB mode (lldb/CMakeLists.txt) — no patch to llvm-project required.
#
# Required -D inputs (set by build-twostage.sh):
#   LLDB_PYTHONS     ';'-separated list of python executables, one per ABI
#   LLDB_SOURCE      path to llvm-project/lldb
#   STAGE2_COMMON    path to stage2-common.cmake (shared opt/quality settings)
#   LLVM_DIR         <stage2-bins>/lib/cmake/llvm
#   Clang_DIR        <stage2-bins>/lib/cmake/clang
#   STAGE1_CC        stage-1 clang   (the compiler that built the in-tree stage2)
#   STAGE1_CXX       stage-1 clang++
#   STAGING_ROOT     directory to install each per-Python LLDB into
#   INSTALL_TARGETS  ';'-separated ninja targets to build (install-<tool>...)
#   PACKAGE_VENDOR   vendor string for `lldb --version` (003 patch)
#   LLVM_DEFAULT_TARGET_TRIPLE
#                    stage-2 default triple (llvm-config --host-target). The
#                    001-runpath patch derives the lib/<triple> RPATH entries from
#                    this var, but LLVMConfig.cmake does NOT export it; without it
#                    the standalone lldb/liblldb get only $ORIGIN/../lib (no triple
#                    subdir) and fail to load libc++.so.1 at runtime.
# Optional:
#   LLVM_CCACHE_BUILD            ON/OFF (default OFF)
#   PARALLEL_COMPILE_JOBS        passed to each LLDB build
#   PARALLEL_LINK_JOBS           passed to each LLDB build (ThinLTO links: keep low)

cmake_minimum_required(VERSION 3.20)
project(lldb-multipython NONE)

include(ExternalProject)

foreach(_var LLDB_PYTHONS LLDB_SOURCE STAGE2_COMMON LLVM_DIR Clang_DIR
             STAGE1_CC STAGE1_CXX STAGING_ROOT INSTALL_TARGETS
             LLVM_DEFAULT_TARGET_TRIPLE)
  if(NOT DEFINED ${_var})
    message(FATAL_ERROR "lldb-multipython: required -D${_var}=... is not set")
  endif()
endforeach()

# Build the per-Python LLDBs sequentially (each chained to the previous) to bound
# peak memory: ThinLTO link steps are memory-hungry and N concurrent ones OOM.
# Flip the add_dependencies() below off to parallelize if the host has headroom.
set(_prev "")

foreach(_py IN LISTS LLDB_PYTHONS)
  execute_process(
    COMMAND "${_py}" -c "import sys;sys.stdout.write('cp%d%d' % sys.version_info[:2])"
    OUTPUT_VARIABLE _tag
    RESULT_VARIABLE _rc)
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "lldb-multipython: failed to read ABI tag from ${_py}")
  endif()

  execute_process(
    COMMAND "${_py}" -c "import sys;sys.stdout.write(sys.exec_prefix)"
    OUTPUT_VARIABLE _pyhome)

  ExternalProject_Add(lldb-${_tag}
    SOURCE_DIR  "${LLDB_SOURCE}"
    PREFIX      "${CMAKE_BINARY_DIR}/${_tag}"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/${_tag}/build"
    CMAKE_GENERATOR Ninja
    CMAKE_ARGS
      # Shared opt/quality settings — identical file the stage-2 build consumes.
      -C${STAGE2_COMMON}
      # Compile LLDB with the SAME compiler that built the in-tree stage2
      # (stage-1 clang), linking the stage-2 LLVM/Clang dylibs.
      -DCMAKE_C_COMPILER=${STAGE1_CC}
      -DCMAKE_CXX_COMPILER=${STAGE1_CXX}
      -DLLVM_DIR=${LLVM_DIR}
      -DClang_DIR=${Clang_DIR}
      # The 001-runpath patch builds the lib/<triple> RPATH entries from
      # LLVM_DEFAULT_TARGET_TRIPLE; LLVMConfig.cmake doesn't export it, so set it
      # explicitly to match the stage-2 runtimes layout (lib/<triple>/libc++.so.1).
      # Without this the standalone lldb fails: "libc++.so.1: cannot open ...".
      -DLLVM_DEFAULT_TARGET_TRIPLE=${LLVM_DEFAULT_TARGET_TRIPLE}
      # Per-Python binding.
      -DLLDB_ENABLE_PYTHON=ON
      -DPython3_EXECUTABLE=${_py}
      -DPYTHON_HOME=${_pyhome}
      # Vendor string (003 patch reads PACKAGE_VENDOR -> LLDB_VENDOR).
      -DPACKAGE_VENDOR=${PACKAGE_VENDOR}
      # Keep test targets so install-lldb-test exists (parity with in-tree build,
      # which packages lldb-test). See packager.LLDB_TOOLS.
      -DLLDB_INCLUDE_TESTS=ON
      -DLLVM_CCACHE_BUILD=${LLVM_CCACHE_BUILD}
      -DLLVM_PARALLEL_COMPILE_JOBS=${PARALLEL_COMPILE_JOBS}
      -DLLVM_PARALLEL_LINK_JOBS=${PARALLEL_LINK_JOBS}
      -DCMAKE_INSTALL_PREFIX=${STAGING_ROOT}/lldb-${_tag}
    # Build (and install, via the install-<tool> targets) only what we package.
    BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target ${INSTALL_TARGETS}
    INSTALL_COMMAND ""
    USES_TERMINAL_CONFIGURE 1
    USES_TERMINAL_BUILD 1
    LIST_SEPARATOR |
  )

  if(_prev)
    add_dependencies(lldb-${_tag} ${_prev})
  endif()
  set(_prev lldb-${_tag})
endforeach()
