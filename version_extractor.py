#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path
from subprocess import check_output
from typing import Union
from os.path import exists

GIT_LOG_RE = re.compile(r"([0-9a-f]+)(?:\s+\(tag: llvmorg-(.+)\))?\n")
LLVM_VERSION_RE = re.compile(r"(\d+).(\d+).(\d+)(?:-(rc\d+))?")

parser = argparse.ArgumentParser()

parser.add_argument("-m", "--mode", choices=["python", "cmake", "tag", "is-tag"], default="python")
parser.add_argument("-d", "--directory", type=Path, default=".")
parser.add_argument("--skip-current-tag", action="store_true", default=False,
                    help="disregard the first tag if it's on a current commit")


def main():
    args = parser.parse_args()
    version = get_version(args.mode, args.directory, skip_current_tag=args.skip_current_tag)
    if not version and args.mode != "is-tag":
        print("Something is wrong! Unable to find a version!", file=sys.stderr)
        return 1
    if version:
        print(version)


def get_version(mode: Union[str, Path], git_dir: Union[str, Path], skip_current_tag:bool = False):
    start_commit = "HEAD"
    continue_commit = start_commit
    post_commits = 0
    commits_found = 2

    while commits_found > 1:
        commits_found = 0
        out = check_output(
            ["git", "log", "--pretty=%H%d", "-n100", "--decorate-refs=refs/tags", "--decorate=short", continue_commit],
            text=True, cwd=git_dir)
        for commit_id, tag in GIT_LOG_RE.findall(out):
            # print(commit_id, tag, post_commits)
            if not tag or skip_current_tag and not post_commits:
                post_commits += 1
            else:
                init_tag = False
                if tag.endswith("-init"):
                    init_tag = True
                    major = tag[:-5]
                    minor = patch = 0
                    rc = f".dev{post_commits}"
                    post_commits = 0
                else:
                    major, minor, patch, rc = LLVM_VERSION_RE.findall(tag)[0]

                if mode == "python":
                    release = 0
                    if exists(".release"):
                        with open(".release", "rt") as f:
                            release = int(f.read().strip() or 0)
                    return (f"{major}.{minor}.{patch}"
                            f"{f'{rc}' if rc else ''}"
                            f"{f'.post{post_commits}' if post_commits else ''}"
                            f"{f'+{release}' if release else ''}"
                            )
                elif mode == "cmake":
                    return (f"-DLLVM_VERSION_MAJOR={major} "
                            f"-DLLVM_VERSION_MINOR={minor} "
                            f"-DLLVM_VERSION_PATCH={patch} "
                            )
                elif mode == "tag":
                    if init_tag:
                        return f"llvmorg-{major}-init"
                    else:
                        return f"llvmorg-{major}.{minor}.{patch}{f'-{rc}' if rc else ''}"
                elif mode == "is-tag":
                    if not post_commits:
                        return "1"
                    return f""
                else:
                    raise ValueError(f"mode: {mode}")

            continue_commit = commit_id
            commits_found += 1
        post_commits -= 1


if __name__ == "__main__":
    sys.exit(main())
