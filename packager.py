#!/usr/bin/env python3

import argparse
import os
import sys
from enum import IntFlag, auto
from functools import lru_cache, partial
from itertools import chain
from pathlib import Path
from shutil import rmtree, move
from subprocess import check_call, check_output
from tempfile import TemporaryDirectory
from typing import Union

from elftools.elf.elffile import ELFFile, ELFError

import version_extractor

TOOLCHAIN_TOOLS = ["llvm-ar",
                   "llvm-cov",
                   "llvm-cxxfilt",
                   "llvm-dwp",
                   "llvm-ranlib",
                   "llvm-lib",
                   "llvm-ml",
                   "llvm-nm",
                   "llvm-objcopy",
                   "llvm-objdump",
                   "llvm-pdbutil",
                   "llvm-rc",
                   "llvm-readobj",
                   "llvm-size",
                   "llvm-strings",
                   "llvm-strip",
                   "llvm-profdata",
                   "llvm-symbolizer",
                   "llvm-dis",
                   "addr2line",
                   "ar",
                   "c++filt",
                   "ranlib",
                   "nm",
                   "objcopy",
                   "objdump",
                   "readelf",
                   "size",
                   "strings",
                   "strip",
                   ]

LLDB = ["lldb"]


class ElfState(IntFlag):
    IsELF = auto()
    HasSymbols = auto()
    HasDebugInfo = auto()


parser = argparse.ArgumentParser()
parser.add_argument("-S", "--stage", type=int, choices=[1, 2], required=True)
parser.add_argument("-b", "--build-dir", type=Path, help="LLVM build directory", required=True)
parser.add_argument("-t", "--target-dir", type=Path, help="LLVM binary directory", required=True)
parser.add_argument("-s", "--source-dir", type=Path, default=Path("llvm-project"), help="LLVM project source")

all_excluded = []

log = partial(print, file=sys.stderr)


def exclude(*dirs: Path):
    all_excluded.extend(list(chain(f.relative_to(d) for d in dirs for f in d.glob("**") if f != d)))


def is_excluded(path: Path):
    return path in all_excluded


def get_elf_state(path: Path) -> ElfState:
    with open(path, "rb") as f:
        elf_state = ElfState.IsELF
        try:
            elf = ELFFile(f)
            if elf.get_section_by_name(".symtab"):
                elf_state |= ElfState.HasSymbols
            if elf.get_section_by_name(".debug_info"):
                elf_state |= ElfState.HasDebugInfo
        except ELFError:
            pass
        return elf_state


def rm_dir_contents(d: Path):
    for f in d.glob("*"):
        if f != d:
            if f.is_dir():
                rmtree(f)
            else:
                f.unlink()


TEMPLATE = """#!/usr/bin/env python
#   -*- coding: utf-8 -*-
import os
import sys
from os import walk, environ
from os.path import abspath, join as jp

from setuptools import setup
from wheel_axle.bdist_axle import BdistAxle


def get_data_files(src_dir):
    current_path = abspath(src_dir)
    for root, dirs, files in walk(current_path, followlinks=True):
        if not files:
            continue
        path_prefix = root[len(current_path) + 1:]
        if path_prefix.endswith(".egg-info"):
            continue
        yield path_prefix, [jp(root, f) for f in files]


data_files = list(get_data_files("."))
sys.argv.extend(("--root-is-pure", "false", "--abi-tag", "none", "--python-tag", "py3"))
plat = os.environ.get("AUDITWHEEL_PLAT", None)
if plat:
    sys.argv.extend(("-p", plat))

setup(
    name=%(name)r,
    version=%(version)r,
    description=%(description)r,
    long_description=%(long_description)r,
    long_description_content_type='text/markdown',
    classifiers=[
        'Programming Language :: Python',
        'Operating System :: POSIX :: Linux',
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: Apache Software License',
        'Topic :: Software Development :: Build Tools',
    ],
    keywords=%(keywords)r,
    author="Karellen, Inc.",
    author_email="supervisor@karellen.co",
    maintainer="Arcadiy Ivanov",
    maintainer_email="arcadiy@karellen.co",

    license='Apache License, Version 2.0',

    url='https://github.com/karellen/karellen-llvm',
    project_urls={
        'Bug Tracker': 'https://github.com/karellen/karellen-llvm/issues',
        'Documentation': 'https://github.com/karellen/karellen-llvm',
        'Source Code': 'https://github.com/karellen/karellen-llvm'
    },
    scripts=[],
    packages=[],
    namespace_packages=[],
    py_modules=[],
    entry_points={},
    data_files=data_files,
    package_data={},
    install_requires=%(requires)r,
    extras_require=%(extras)r,
    dependency_links=[],
    zip_safe=False,
    obsoletes=[],
    cmdclass={"bdist_wheel": BdistAxle}
)
"""


class Packager:
    def __init__(self, stage: int, source_dir: Path, build_dir: Path, target_dir: Path,
                 wheel_dir: Path = Path("wheels")):
        self.stage = stage
        self.source_dir = source_dir
        self.build_dir = build_dir
        self.target_dir = target_dir
        self.target_dir_debug = target_dir.with_suffix(target_dir.suffix + ".debug")
        self.wheel_dir = wheel_dir
        self.processed: list[Path] = []
        self._call_env = dict(os.environ)
        self._llvm_config = self.build_dir / "bin" / "llvm-config"

        if self.stage == 2:
            log(f"Running in two-stage mode!")
            self.build_dir = self.build_dir / "tools" / "clang" / "stage2-bins"
            build_dir_libs = self.build_dir / "lib"
            host_target = check_output([self._llvm_config, '--host-target'], universal_newlines=True).strip()
            self._call_env["LD_LIBRARY_PATH"] = f"{build_dir_libs / host_target}:{build_dir_libs}"

        self._objcopy = (self.build_dir / "bin" / "llvm-objcopy").absolute()
        self._strip = (self.build_dir / "bin" / "llvm-strip").absolute()

        self.version = version_extractor.get_version("python", self.source_dir)
        log(f"LLVM Python Version: {self.version}")

    def call(self, *args, **kwargs):
        check_call(args, env=self._call_env, **kwargs)

    def prepare(self):
        rm_dir_contents(self.target_dir)
        rm_dir_contents(self.target_dir_debug)
        self.wheel_dir.mkdir(parents=True, exist_ok=True)

    def build(self, *cmds: Union[str, Path]):
        # self.target_dir.mkdir(parents=True, exist_ok=True)
        ninja = ["ninja-build", "-C", self.build_dir]
        ninja.extend(cmds)
        self.call(*ninja)

    def record_processed(self):
        target_dir = self.target_dir
        self.processed.extend(f for f in target_dir.glob("**/*") if not f.is_dir())

    def delete_in_target(self, pattern):
        log(f"Deleting {pattern}...")
        for f in self.target_dir.glob(pattern):
            log(f"\t{f!s}")
            if f.is_dir():
                rmtree(f)
            else:
                f.unlink()

    @lru_cache
    def check_debug_tools(self):
        self.call(self._objcopy, "--version")
        log("`objcopy` is working")
        self.call(self._strip, "--version")
        log("`strip` is working")
        return True

    def process_elf(self, extract=True, strip_debug=True):
        self.check_debug_tools()
        target_dir_debug = self.target_dir_debug
        target_dir = self.target_dir
        log(f"Processing ELF files...")
        for f in target_dir.glob("**/*"):
            if (f.is_file() and not f.is_symlink() and
                    (elf_state := get_elf_state(f)) and (ElfState.HasDebugInfo in elf_state)):
                debug_f = f.with_suffix(f.suffix + ".debug")
                target_debug_f = target_dir_debug / debug_f.relative_to(target_dir)
                if extract:
                    log(f"\tExtracting {f!s}")
                    self.call(self._objcopy, "--only-keep-debug", f, debug_f)
                if strip_debug:
                    log(f"\tStripping {f!s}")
                    self.call(self._strip, "-g", f)
                if extract:
                    self.call(self._objcopy, "--add-gnu-debuglink",
                              debug_f.name, f.absolute(),
                              cwd=debug_f.parent)
                    target_debug_f.parent.mkdir(parents=True, exist_ok=True)
                    move(debug_f, target_debug_f)
                    target_debug_f.chmod(0o644)

    def delete_processed(self, delete_empty_dirs=True):
        log(f"Deleting previously captured files... {self.processed}")
        for p in self.processed:
            if p.is_symlink() or p.exists() and not p.is_dir():
                log(f"\tDeleting {p}...")
                p.unlink()

        if delete_empty_dirs:
            for p in self.processed:
                if p.exists() and p.is_dir():
                    try:
                        p.rmdir()
                        log(f"\tDeleted empty dir {p}...")
                    except OSError:
                        pass

    def package(self, package_vars, debug_package_vars=None):
        def _package(package_dir, package_vars):
            setup_file = TEMPLATE % package_vars
            with TemporaryDirectory() as tmp_dir:
                tmp_setup = Path(tmp_dir) / "setup.py"
                with open(tmp_setup, "wt") as f:
                    f.write(setup_file)

                self.call(sys.executable, tmp_setup, "bdist_wheel", cwd=package_dir)
            for f in package_dir.glob("dist/*.whl"):
                move(f, self.wheel_dir / f.name)

        _package(self.target_dir, package_vars)
        if debug_package_vars:
            debug_vars = dict(package_vars)
            debug_vars.update(debug_package_vars)
            _package(self.target_dir_debug, debug_vars)


def main():
    args = parser.parse_args()
    pkgr = Packager(args.stage, args.source_dir, args.build_dir, args.target_dir)
    pkgr.prepare()

    pkgr.build("install-cxx", "install-cxxabi", "install-unwind")
    pkgr.build("install-LLVM", "install-LTO", "install-Remarks")

    pkgr.delete_in_target("**/*.a")
    pkgr.delete_in_target("include")
    pkgr.record_processed()
    pkgr.process_elf()

    pkgr.package(dict(name="karellen-llvm-core",
                      version=pkgr.version,
                      description="Karellen LLVM core libraries",
                      long_description="Contains LLVM, LTO, Remarks, libc++, libc++abi, and libunwind",
                      keywords=["LLVM", "libc++", "libcxx"],
                      requires=[], extras={}),
                 dict(name="karellen-llvm-core-debug",
                      description="Karellen LLVM core libraries (debug info)",
                      long_description="Contains LLVM, LTO, Remarks, libc++, libc++abi, and libunwind debug info",
                      requires=[f"karellen-llvm-core=={pkgr.version}"],
                      extras={}
                      ))

    pkgr.build(*map(lambda x: f"install-{x}", TOOLCHAIN_TOOLS))
    pkgr.delete_processed()
    pkgr.record_processed()
    pkgr.process_elf(extract=False)
    pkgr.package(dict(name="karellen-llvm-toolchain-tools",
                      version=pkgr.version,
                      description="Karellen LLVM Toolchain Tools",
                      long_description="Self-contained LLVM toolchain tools",
                      requires=[f"karellen-llvm-core=={pkgr.version}"],
                      extras={},
                      keywords=["LLVM", "toolchain", "tools"]), None)

    pkgr.build(*map(lambda x: f"install-{x}", LLDB_PACKAGES))
    pkgr.delete_processed()
    pkgr.record_processed()
    pkgr.process_elf(extract=False)
    pkgr.package(dict(name="karellen-llvm-lldb",
                      version=pkgr.version,
                      description="Karellen LLDB infrastructure",
                      long_description="Self-contained LLVM LLDB infrastructure",
                      requires=[f"karellen-llvm-core=={pkgr.version}"],
                      keywords=["LLVM", "lldb", "debugger"]), None)

    pkgr.build("install")
    pkgr.delete_processed()
    pkgr.process_elf(extract=False)
    pkgr.delete_in_target("lib/*a")
    pkgr.delete_in_target("include/clang*")
    pkgr.delete_in_target("include/lld*")
    pkgr.package(dict(name="karellen-llvm-clang",
                      version=pkgr.version,
                      description="Karellen Clang compiler infrastructure",
                      long_description="Self-contained LLVM Clang compiler infrastructure",
                      requires=[f"karellen-llvm-core=={pkgr.version}"],
                      extras={"tools": [f"karellen-llvm-toolchain-tools=={pkgr.version}"]},
                      keywords=["LLVM", "clang", "c", "c++", "compiler"]), None)


if __name__ == "__main__":
    main()
