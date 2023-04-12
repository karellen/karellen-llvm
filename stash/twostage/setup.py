#!/usr/bin/env python
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
        yield path_prefix, [jp(root, f) for f in files]


data_files = list(get_data_files("."))
sys.argv.extend(("--root-is-pure", "false", "--abi-tag", "none"))
plat = os.environ.get("AUDITWHEEL_PLAT", None)
if plat:
    sys.argv.extend(("-p", plat))

setup(
    name="",
    version="",
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
    cmdclass={"bdist_wheel": BdistAxle}
)
