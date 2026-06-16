#!/usr/bin/env python3

import atexit
import argparse
import os
import signal
import sys

import python_abis
from grp import getgrgid
from os import makedirs, getuid, getgid, environ
from os.path import exists, join as jp, abspath as ap, expanduser
from pwd import getpwuid
from subprocess import Popen, run

# CPython ABI set (single source of truth: python_abis.py).
PYTHON_VERSION = python_abis.PYTHON_DEFAULT_VERSION
PYTHON_BUILD_GLOB = python_abis.build_glob()

CCACHE_VERSION = "4.13.6"
CMAKE_VERSION = "4.3.3"
NINJA_VERSION = "1.13.2"

DOCKER_BASES = {
    "ghcr.io/karellen/manylinux_2_28_x86_64:latest": "manylinux2014",
}

INIT_SCRIPT = [
    'ARCH="$(uname -m)"',
    f'export PYTHON_BIN="$(echo /opt/python/cp{PYTHON_VERSION}-cp{PYTHON_VERSION}-shared*)/bin"',
    'export PATH="$PYTHON_BIN:$PATH"',
    f"curl -Ls https://github.com/ccache/ccache/releases/download/v{CCACHE_VERSION}/ccache-{CCACHE_VERSION}-linux-$ARCH-glibc.tar.xz | tar -xv --xz -C /tmp",
    "cd /tmp/ccache* && make install",
    f"curl -Ls -o /tmp/cmake.sh https://github.com/Kitware/CMake/releases/download/v{CMAKE_VERSION}/cmake-{CMAKE_VERSION}-linux-$ARCH.sh",
    "chmod +x /tmp/cmake.sh && /tmp/cmake.sh --exclude-subdir --skip-license --prefix=/usr/local",
    "ln -s /usr/local/bin/cmake /usr/local/bin/cmake3",
    f'curl -Ls -o /tmp/ninja.zip https://github.com/ninja-build/ninja/releases/download/v{NINJA_VERSION}/ninja-linux${{NINJA_ARCH:-}}.zip',
    "unzip /tmp/ninja.zip -d /usr/local/bin",
    "ln -s /usr/local/bin/ninja /usr/local/bin/ninja-build",
]

MAPPED_FILES = [
    ("python_abis.py", None, "ro"),
    ("twostage.cmake", None, "ro"),
    ("stage2-common.cmake", None, "ro"),
    ("build-twostage.sh", None, "ro"),
    ("package-twostage.sh", None, "ro"),
    ("packager.py", None, "ro"),
    ("version_extractor.py", None, "ro"),
    ("requirements.txt", None, "ro"),
    ("test-build.sh", None, "ro"),
]

# Read-only source directories mapped into /build.
MAPPED_SRC_DIRS = ["lldb-multipython"]

MAPPED_DIRS = ["llvm.twostage.build", "llvm.lldb.driver.build", "llvm.lldb.staging"]
ENV_VARS = ["NO_CCACHE", "NO_MULTIPYTHON_BUILDS"]

_current_proc = None
_current_container = None
_cleaning_up = False


def cleanup():
    global _cleaning_up
    if _cleaning_up:
        return
    _cleaning_up = True

    # Stop the container FIRST, via an independent `docker stop` subprocess.
    # This is the authoritative teardown and, crucially, does not touch
    # _current_proc's internal _waitpid_lock. cleanup() runs inside the signal
    # handler while the main thread is suspended mid-_current_proc.wait() (which
    # holds that lock): calling a *blocking* _current_proc.wait() here would
    # deadlock on the held lock and hang the abort forever. Stopping the
    # container makes the `docker run` client exit on its own.
    if _current_container:
        try:
            run(["docker", "stop", "-t", "3", _current_container],
                capture_output=True, timeout=15)
        except Exception:
            try:
                run(["docker", "kill", _current_container],
                    capture_output=True, timeout=10)
            except Exception:
                pass

    # Nudge the `docker run` client. poll() is non-blocking and terminate()
    # only sends a signal; we deliberately do NOT block-wait on it here.
    if _current_proc and _current_proc.poll() is None:
        _current_proc.terminate()

    _cleaning_up = False


def sighandler(signum, frame):
    cleanup()
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


def main():
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

    atexit.register(cleanup)
    signal.signal(signal.SIGINT, sighandler)
    signal.signal(signal.SIGTERM, sighandler)

    global _current_proc, _current_container
    for docker_img, docker_suffix in DOCKER_BASES.items():
        _current_container = f"karellen-llvm-{docker_suffix}"

        script_lines = ["set -eEux"] + INIT_SCRIPT + [
            f"groupadd -g {gid} {gname}",
            f"useradd {uname} -u {uid} -g {gid} -d {udir} -M -s /bin/bash",
            f"mkdir -p {udir}",
            f"chown {uname}:{gname} /build",
            f"chown {uname}:{gname} {udir}",
            f"chown {uname}:{gname} {ccache_dir}",
            f'export PYTHON_BIN="$(echo /opt/python/cp{PYTHON_VERSION}-cp{PYTHON_VERSION}-shared*)/bin"',
            f'export PATH="$PYTHON_BIN:$PATH"',
            "cd /build",
            f'for python_dir in $(ls -d {PYTHON_BUILD_GLOB} 2>/dev/null || true); do $python_dir/bin/python3 -m pip install --root-user-action ignore -r requirements.txt; done',
            f"su -m {uname} {run_script}",
        ]
        inner_script = " && ".join(script_lines)

        cmd_line = ["docker", "run", "--pull", "always", "--rm",
                    "--name", _current_container,
                    "--init"]

        for mf in MAPPED_FILES:
            cmd_line.extend(["-v", "%s:%s:%s" % (ap(mf[0]), mf[1] or jp("/build", mf[0]), mf[2])])
        for md in MAPPED_DIRS:
            local_dir = "%s.%s" % (md, docker_suffix)
            makedirs(local_dir, exist_ok=True)
            cmd_line.extend(["-v", "%s:%s" % (ap(local_dir), jp("/build", md))])
        cmd_line.extend(["-v", "%s:%s:ro" % (ap("llvm-project"), jp("/build", "llvm-project"))])
        for sd in MAPPED_SRC_DIRS:
            cmd_line.extend(["-v", "%s:%s:ro" % (ap(sd), jp("/build", sd))])
        cmd_line.extend(["-v", "%s:%s" % (ccache_dir, ccache_dir)])
        cmd_line.extend(["-v", "%s:%s" % (ap("ccache"), jp("/build", "ccache"))])
        cmd_line.extend(["-v", "%s:%s" % (ap("wheels"), jp("/build", "wheels"))])
        cmd_line.extend(["-v", "%s:%s" % (ap(".git"), jp("/build", ".git"))])
        if exists(".release"):
            cmd_line.extend(["-v", "%s:%s:ro" % (ap(".release"), jp("/build", ".release"))])

        for env in ENV_VARS:
            if env in environ:
                cmd_line.extend(["-e", f"{env}={environ[env]}"])

        cmd_line.extend([docker_img, "/bin/bash", "-c", inner_script])

        print(f"=== Building with {docker_img} ===", file=sys.stderr)
        _current_proc = Popen(cmd_line)
        return_code = _current_proc.wait()
        _current_proc = None
        _current_container = None

        if return_code:
            raise RuntimeError("Exited with %d" % return_code)


if __name__ == "__main__":
    main()
