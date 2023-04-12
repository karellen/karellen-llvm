#!/usr/bin/env python
#   -*- coding: utf-8 -*-

from setuptools import setup
from setuptools.command.install import install as _install

class install(_install):
    def pre_install_script(self):
        pass

    def post_install_script(self):
        pass

    def run(self):
        self.pre_install_script()

        _install.run(self)

        self.post_install_script()

if __name__ == '__main__':
    setup(
        name = 'llvm',
        version = '0.0.1',
        description = 'LLVM Description.',
        long_description = 'LLVM Long Description\n',
        long_description_content_type = 'text/markdown',
        classifiers = [
            'Programming Language :: Python',
            'Programming Language :: Python :: Implementation :: CPython',
            'Programming Language :: Python :: Implementation :: PyPy',
            'Programming Language :: Python :: 2',
            'Programming Language :: Python :: 2.7',
            'Programming Language :: Python :: 3',
            'Programming Language :: Python :: 3.5',
            'Programming Language :: Python :: 3.6',
            'Programming Language :: Python :: 3.7',
            'Programming Language :: Python :: 3.8',
            'Programming Language :: Python :: 3.9',
            'Operating System :: MacOS :: MacOS X',
            'Operating System :: POSIX :: Linux',
            'Operating System :: Microsoft :: Windows',
            'Operating System :: OS Independent',
            'Development Status :: 5 - Production/Stable',
            'Environment :: Console',
            'Intended Audience :: Developers',
            'License :: OSI Approved :: Apache Software License',
            'Topic :: Software Development :: Build Tools',
            'Topic :: Software Development :: Quality Assurance',
            'Topic :: Software Development :: Testing'
        ],
        keywords = 'LLVM keywords',

        author = 'Arcadiy Ivanov',
        author_email = 'arcadiy@ivanov.biz',
        maintainer = 'Arcadiy Ivanov',
        maintainer_email = 'arcadiy@ivanov.biz',

        license = 'Apache License, Version 2.0',

        url = 'https://pybuilder.io',
        project_urls = {
            'Bug Tracker': 'https://github.com/pybuilder/pybuilder/issues',
            'Documentation': 'https://pybuilder.io/documentation',
            'Source Code': 'https://github.com/pybuilder/pybuilder'
        },
        scripts = ["bin/llvm-config"],
        packages = [
            'llvm',
        ],
        namespace_packages = [],
        py_modules = [],
        entry_points = {
        },
        data_files = [
            ("lib", ["data/libLLVM.so"]),
            ("include/llvm", ["include/llvm/header1.h"])
        ],
        package_data = {
            'llvm': ['LICENSE'],
        },
        install_requires = [],
        dependency_links = [],
        zip_safe = True,
        cmdclass = {'install': install},
        python_requires = '!=3.0,!=3.1,!=3.2,!=3.3,!=3.4,>=2.7',
        obsoletes = []
    )
