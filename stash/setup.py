#!/usr/bin/env python
#   -*- coding: utf-8 -*-

from os import walk, readlink, symlink, unlink
from os.path import abspath, dirname, join as jp, islink

from setuptools import setup


def get_data_files():
    current_path = abspath(dirname(__file__))
    for root, dirs, files in walk(current_path, followlinks=True):
        if root == current_path:
            continue

        path_prefix = root[len(current_path) + 1:]
        yield (path_prefix, [jp(path_prefix, f) for f in files])


name = "llvm-runtime"

include_name = f"include/{name}.h"
data_files = list(get_data_files())


# data_files.append(("include", [include_name]))

# makedirs("include", exist_ok=True)
# Path(include_name).touch()

# print(data_files)

setup(
    name=name,
    version='0.0.1',
    description='LLVM Description.',
    long_description='LLVM Long Description\n',
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
    keywords='LLVM keywords',

    author='Arcadiy Ivanov',
    author_email='arcadiy@ivanov.biz',
    maintainer='Arcadiy Ivanov',
    maintainer_email='arcadiy@ivanov.biz',

    license='Apache License, Version 2.0',

    url='https://karellen.co',
    project_urls={
        'Bug Tracker': 'https://github.com/pybuilder/pybuilder/issues',
        'Documentation': 'https://pybuilder.io/documentation',
        'Source Code': 'https://github.com/pybuilder/pybuilder'
    },
    scripts=[],
    packages=[],
    namespace_packages=[],
    py_modules=[],
    entry_points={
    },
    data_files=data_files,
    package_data={
    },
    install_requires=[],
    dependency_links=[],
    zip_safe=False,
    # python_requires = '!=3.0,!=3.1,!=3.2,!=3.3,!=3.4,>=2.7',
    obsoletes=[],

)
