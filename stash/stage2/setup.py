#!/usr/bin/env python
#   -*- coding: utf-8 -*-

import re
import sys

from os import walk, makedirs, readlink, symlink, unlink, chdir
from os.path import abspath, dirname, basename, join as jp, sep, islink

from setuptools import setup
from subprocess import check_output


def get_data_files(src_dir):
    current_path = abspath(src_dir)
    for root, dirs, files in walk(current_path, followlinks=True):
        if not files:
            continue
        path_prefix = root[len(current_path) + 1:]
        yield path_prefix, [jp(root, f) for f in files]


def get_llvm_version(llvm_src_dir, llvm_bin_dir):
    version_line = check_output([jp(llvm_bin_dir, "bin", "clang"), "--version"], universal_newlines=True)
    version = re.findall(r"^.*\s+clang version\s+(\d+)\.(\d+)\.(\d+)\s+\(.*\s+([a-fA-F0-9]+)\)$",
                         version_line.splitlines()[0])[0]
    revcount = check_output(["git", "rev-list", "--count", version[-1]], cwd=llvm_src_dir, universal_newlines=True)
    return *version[:3], f"{revcount.strip()}+{version[3]}"

llvm_src_dir = sys.argv[1]
llvm_bin_dir = sys.argv[2]
del sys.argv[1:3]

llvm_version = get_llvm_version(llvm_src_dir, llvm_bin_dir)
data_files = list(get_data_files(llvm_bin_dir))
sys.argv.extend(("--build-number", llvm_version[3], "--root-is-pure", "false", "--python-tag", "py3", "--abi-tag", "none"))

name = "karellen-llvm-stage1"

setup(
    name=name,
    version=".".join(llvm_version[:3]),
    description='Bootstrap (Stage 1) LLVM Clang Compiler',
    long_description='This distribution is a Bootstrap (Stage 1) LLVM/Clang build. It should not be used for anything else.',
    long_description_content_type='text/markdown',
    classifiers=[
        'Programming Language :: Python',
        'Operating System :: POSIX :: Linux',
        'Development Status :: 5 - Production/Stable',
        'Environment :: Console',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: Apache Software License',
        'Topic :: Software Development :: Build Tools',
    ],
    keywords="LLVM",
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
    install_requires=[],
    dependency_links=[],
    zip_safe=False,
    obsoletes=[],
)
