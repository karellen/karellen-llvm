#!/usr/bin/env python3

"""Unit tests for packager.py.

Run with `python -m unittest discover -s tests -t .` from the repository root.
"""

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import packager
from packager import Packager

# Shape of the existence-check block CMake appends to a generated exports file.
# The real file also carries the add_library/set_target_properties calls, which
# verify_cmake_exports ignores.
EXPORTS_TEMPLATE = """\
# Import target "LLVM" for configuration "RelWithDebInfo"
set_property(TARGET LLVM APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)

{checks}

# Loop over all imported files and verify that they actually exist
foreach(_cmake_target IN LISTS _cmake_import_check_targets)
endforeach()
"""


def write_exports(cmake_dir: Path, imports: dict[str, str], name="LLVMExports-relwithdebinfo.cmake"):
    """Write an exports file importing `imports` (target -> prefix-relative path)."""
    cmake_dir.mkdir(parents=True, exist_ok=True)
    checks = "\n".join(
        f'list(APPEND _cmake_import_check_targets {target} )\n'
        f'list(APPEND _cmake_import_check_files_for_{target} "${{_IMPORT_PREFIX}}/{path}" )'
        for target, path in imports.items())
    (cmake_dir / name).write_text(EXPORTS_TEMPLATE.format(checks=checks), encoding="utf-8")


class VerifyCMakeExportsTest(unittest.TestCase):
    # verify_cmake_exports only reads `target_dir` and `processed`, so the
    # packager is built without touching git, CMake or the LLVM source tree.
    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.target_dir = Path(self._tmp.name)
        self.cmake_dir = self.target_dir / "lib" / "cmake" / "llvm"

        self.pkgr = Packager.__new__(Packager)
        self.pkgr.target_dir = self.target_dir
        self.pkgr.processed = set()

    def stage(self, *rel_paths):
        """Create the given prefix-relative files inside the staging dir."""
        for rel in rel_paths:
            f = self.target_dir / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(b"\x7fELF")

    def test_all_imports_present_in_staging_dir(self):
        write_exports(self.cmake_dir, {"llvm-ar": "bin/llvm-ar",
                                       "opt": "bin/opt",
                                       "llvm-config": "bin/llvm-config"})
        self.stage("bin/llvm-ar", "bin/opt", "bin/llvm-config")

        self.pkgr.verify_cmake_exports()

    def test_imports_supplied_by_a_previously_packaged_wheel(self):
        # libLLVM/libLTO/libRemarks are installed by the core step, which records
        # them and then wipes the staging dir; they are legitimately absent here.
        write_exports(self.cmake_dir, {"LLVM": "lib/libLLVM.so.23.1",
                                       "LTO": "lib/libLTO.so.23.1",
                                       "Remarks": "lib/libRemarks.so.23.1",
                                       "llvm-ar": "bin/llvm-ar",
                                       "llc": "bin/llc"})
        self.stage("bin/llvm-ar", "bin/llc")
        self.pkgr.processed = {self.target_dir / "lib" / "libLLVM.so.23.1",
                               self.target_dir / "lib" / "libLTO.so.23.1",
                               self.target_dir / "lib" / "libRemarks.so.23.1"}

        self.pkgr.verify_cmake_exports()

    def test_unpackaged_imports_are_reported(self):
        write_exports(self.cmake_dir, {"llvm-ar": "bin/llvm-ar",
                                       "llvm-mca": "bin/llvm-mca",
                                       "llvm-profgen": "bin/llvm-profgen",
                                       "opt": "bin/opt"})
        self.stage("bin/llvm-ar", "bin/opt")

        with self.assertRaises(RuntimeError) as ctx:
            self.pkgr.verify_cmake_exports()

        message = str(ctx.exception)
        self.assertIn("llvm-mca", message)
        self.assertIn("llvm-profgen", message)
        self.assertIn("bin/llvm-mca", message)
        self.assertIn("TOOLCHAIN_TOOLS", message)
        # Files that are present must not be reported as missing.
        self.assertNotIn("bin/llvm-ar", message)
        self.assertNotIn("bin/opt", message)

    def test_all_exports_files_are_scanned(self):
        # install(EXPORT) emits the config-independent file plus one per build
        # configuration; a tool missing from either one is fatal.
        write_exports(self.cmake_dir, {"llvm-ar": "bin/llvm-ar", "opt": "bin/opt"},
                      name="LLVMExports.cmake")
        write_exports(self.cmake_dir, {"llc": "bin/llc", "llvm-link": "bin/llvm-link"},
                      name="LLVMExports-relwithdebinfo.cmake")
        self.stage("bin/llvm-ar", "bin/opt", "bin/llc")

        with self.assertRaises(RuntimeError) as ctx:
            self.pkgr.verify_cmake_exports()

        self.assertIn("llvm-link", str(ctx.exception))

    def test_missing_exports_file_is_fatal(self):
        self.cmake_dir.mkdir(parents=True)
        self.stage("bin/llvm-ar", "bin/opt")

        with self.assertRaises(RuntimeError) as ctx:
            self.pkgr.verify_cmake_exports()

        self.assertIn("cmake-exports", str(ctx.exception))


class ToolchainToolsTest(unittest.TestCase):
    def test_dev_components_are_not_tools(self):
        # TOOLCHAIN_DEV_COMPONENTS are install components, not executables; they
        # must stay out of the tool list so process_elf/strip is never asked to
        # treat them as binaries.
        self.assertFalse(set(packager.TOOLCHAIN_DEV_COMPONENTS) & set(packager.TOOLCHAIN_TOOLS))

    def test_ir_tools_are_packaged(self):
        # These are exported by LLVMExports.cmake, so they must be packaged in
        # the same wheel that carries it.
        for tool in ("llvm-config", "opt", "llc", "llvm-as", "llvm-link", "llvm-extract",
                     "llvm-mca", "llvm-profgen"):
            with self.subTest(tool=tool):
                self.assertIn(tool, packager.TOOLCHAIN_TOOLS)

    def test_no_duplicate_tools(self):
        self.assertCountEqual(set(packager.TOOLCHAIN_TOOLS), packager.TOOLCHAIN_TOOLS)


if __name__ == "__main__":
    unittest.main()
