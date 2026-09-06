# Out-of-tree consumer of the installed LLVM development files. Driven by
# test-build.sh against the venv the wheels were installed into, so every build
# proves that karellen-llvm-toolchain-tools actually lets a downstream C++
# project compile and link against libLLVM.
cmake_minimum_required(VERSION 3.20)
# C is enabled because HandleLLVMOptions (and LLVM's FindLibEdit) probe the C
# compiler; without it they fail with "C: needs to be enabled before use".
project(llvm-dev-smoke C CXX)

find_package(LLVM REQUIRED CONFIG)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION} in ${LLVM_DIR}")
message(STATUS "  includes: ${LLVM_INCLUDE_DIRS}")
message(STATUS "  RTTI=${LLVM_ENABLE_RTTI} EH=${LLVM_ENABLE_EH} "
               "ABI_BREAKING_CHECKS=${LLVM_ABI_BREAKING_CHECKS}")

# The ABI flags the dylib was built with (C++ standard, libc++, RTTI, EH,
# ABI-breaking checks) come from LLVM's own modules rather than being restated
# here, which is the whole point of shipping lib/cmake/llvm.
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")
include(HandleLLVMOptions)
include(AddLLVM)

add_executable(llvm-dev-smoke main.cpp)
target_include_directories(llvm-dev-smoke SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND "${LLVM_DEFINITIONS}")
target_compile_definitions(llvm-dev-smoke PRIVATE ${LLVM_DEFINITIONS_LIST})

# LLVM is the imported dylib target from LLVMExports.cmake. Linking it proves
# the export set resolved and that abi-breaking.h agrees with the library: a
# mismatch leaves LLVMEnableABIBreakingChecks undefined at link time.
target_link_libraries(llvm-dev-smoke PRIVATE LLVM)

# The runtimes (libc++, libc++abi, libunwind) install into the per-target
# directory <prefix>/lib/<triple>, not <prefix>/lib. libLLVM carries a RUNPATH
# covering both, but a consumer compiled by this clang gets its own
# DT_NEEDED libc++.so.1 and must find it itself -- CMake only adds an rpath to
# the directory the imported target lives in. Both entries come from
# LLVMConfig.cmake, so nothing here has to know the layout or the triple.
#
# This is the recipe any out-of-tree consumer of these wheels needs; running
# llvm-dev-smoke with no LD_LIBRARY_PATH is what proves it works.
set_target_properties(llvm-dev-smoke PROPERTIES
    BUILD_RPATH "${LLVM_LIBRARY_DIR};${LLVM_LIBRARY_DIR}/${LLVM_HOST_TRIPLE}")
