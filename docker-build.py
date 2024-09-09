#!/usr/bin/env python3

import argparse
from grp import getgrgid
from os import makedirs, pipe, getuid, getgid, close, environ
from os.path import exists, join as jp, abspath as ap, expanduser
from pwd import getpwuid
from subprocess import Popen

PYTHON_VERSION = "312"
CCACHE_VERSION = "4.10.2"
CMAKE_VERSION = "3.30.3"
NINJA_VERSION = "1.12.1"

DOCKER_BASES = {
    "ghcr.io/karellen/manylinux2014_x86_64:latest": (
        "manylinux2014", f'export PYTHON_BIN="$(echo /opt/python/cp{PYTHON_VERSION}*-shared*)/bin"'
                         ' && export PATH="$PYTHON_BIN:$PATH"'
                         f" && curl -Ls https://github.com/ccache/ccache/releases/download/v{CCACHE_VERSION}/ccache-{CCACHE_VERSION}-linux-x86_64.tar.xz | tar -xv --xz -C /tmp"
                         " && cd /tmp/ccache* && make install"
                         f" && curl -Ls -o /tmp/cmake.sh https://github.com/Kitware/CMake/releases/download/v{CMAKE_VERSION}/cmake-{CMAKE_VERSION}-linux-x86_64.sh"
                         " && chmod +x /tmp/cmake.sh && /tmp/cmake.sh --exclude-subdir --skip-license --prefix=/usr/local"
                         " && ln -s /usr/local/bin/cmake /usr/local/bin/cmake3"
                         f" && curl -Ls -o /tmp/ninja.zip https://github.com/ninja-build/ninja/releases/download/v{NINJA_VERSION}/ninja-linux.zip"
                         " && unzip /tmp/ninja.zip -d /usr/local/bin"
                         " && ln -s /usr/local/bin/ninja /usr/local/bin/ninja-build"
        # "&& tar -xf /opt/_internal/static-libs-for-embedding-only.tar.xz -C /opt/_internal"
    )
}

MAPPED_FILES = [
    ("twostage.cmake", None, "ro"),
    ("build-twostage.sh", None, "ro"),
    ("package-twostage.sh", None, "ro"),
    ("packager.py", None, "ro"),
    ("version_extractor.py", None, "ro"),
    ("requirements.txt", None, "ro")
]

MAPPED_DIRS = ["llvm.twostage.build"]
ENV_VARS = ["NO_CCACHE"]


parser = argparse.ArgumentParser()
parser.add_argument("-m", "--mode", choices=["build", "package"], required=True)
args = parser.parse_args()

if args.mode == "build":
    run_script = "./build-twostage.sh"
else:
    run_script = "./package-twostage.sh"

uid = getuid()
uname = getpwuid(uid)[0]
gid = getgid()
gname = getgrgid(gid)[0]
udir = expanduser("~")
ccache_dir = jp(udir, ".ccache")

for docker_img, docker_settings in DOCKER_BASES.items():
    docker_suffix, init_script = docker_settings
    cmd_line = ["docker", "run", "--pull", "always", "--rm", "-i"]
    for mf in MAPPED_FILES:
        cmd_line.extend(["-v", "%s:%s:%s" % (ap(mf[0]), mf[1] or jp("/build", mf[0]), mf[2])])
    for md in MAPPED_DIRS:
        local_dir = "%s.%s" % (md, docker_suffix)
        makedirs(local_dir, exist_ok=True)
        cmd_line.extend(["-v", "%s:%s" % (ap(local_dir), jp("/build", md))])
    cmd_line.extend(["-v", "%s:%s:ro" % (ap("llvm-project"), jp("/build", "llvm-project"))])
    cmd_line.extend(["-v", "%s:%s" % (ccache_dir, ccache_dir)])
    cmd_line.extend(["-v", "%s:%s" % (ap("ccache"), jp("/build", "ccache"))])
    cmd_line.extend(["-v", "%s:%s" % (ap("wheels"), jp("/build", "wheels"))])
    cmd_line.extend(["-v", "%s:%s" % (ap(".git"), jp("/build", ".git"))])
    if exists(".release"):
        cmd_line.extend(["-v", "%s:%s:ro" % (ap(".release"), jp("/build", ".release"))])

    for env in ENV_VARS:
        if env in environ:
            cmd_line.extend(["-e", f"{env}={environ[env]}"])

    cmd_line.append(docker_img)
    cmd_line.append("/bin/bash")

    return_code = None
    r, w = pipe()
    with Popen(cmd_line, stdin=r) as proc:
        try:
            with open(w, "wt") as out_f:
                out_f.write(f"set -eEux && {init_script or 'true'}"
                            f" && groupadd -g {gid} {gname}"
                            f" && useradd {uname} -u {uid} -g {gid} -d {udir} -M -s /bin/bash"
                            f" && chown {uname}:{gname} /build"
                            f" && chown {uname}:{gname} {udir}"
                            f" && chown {uname}:{gname} {ccache_dir}"
                            f' && export PYTHON_BIN="$(echo /opt/python/cp{PYTHON_VERSION}*-shared*)/bin"'
                            f' && export PATH="$PYTHON_BIN:$PATH"'
                            f" && cd /build"
                            f" && pip install -r requirements.txt"
                            f" && su -m {uname} {run_script}"
                            )
                out_f.flush()
            proc.wait()
            return_code = proc.poll()
        finally:
            try:
                close(r)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait()
                    return_code = proc.poll()

        if return_code:
            raise RuntimeError("Exited with %d" % return_code)
