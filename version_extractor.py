#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path
from subprocess import check_output
from typing import Union

GIT_LOG_RE = re.compile(r"([0-9a-f]+)(?:\s+\(tag: llvmorg-(.+)\))?\n")
LLVM_VERSION_RE = re.compile(r"(\d+).(\d+).(\d+)(?:-(rc\d+))?")

parser = argparse.ArgumentParser()

parser.add_argument("-m", "--mode", choices=["python", "cmake"], default="python")
parser.add_argument("-d", "--directory", type=Path, default=".")


def main():
    args = parser.parse_args()
    version = get_version(args.mode, args.directory)
    if not version:
        print("Something is wrong! Unable to find a version!", file=sys.stderr)
        return 1
    print(version)


def get_version(mode: Union[str, Path], git_dir: Union[str, Path]):
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
            if not tag:
                post_commits += 1
            else:
                # print(commit_id, , post_commits)
                major, minor, patch, rc = LLVM_VERSION_RE.findall(tag)[0]
                if mode == "python":
                    return (f"{major}.{minor}.{patch}"
                            f"{f'{rc}' if rc else ''}"
                            f"{f'.post{post_commits}' if post_commits else ''}"
                            )
                elif mode == "cmake":
                    return (f"-DLLVM_VERSION_MAJOR={major} "
                            f"-DLLVM_VERSION_MINOR={minor} "
                            f"-DLLVM_VERSION_PATCH={patch} "
                            # f"-DLLVM_VERSION_SUFFIX="
                            # f"{f'{rc}' if rc else ''}"
                            # f"{'-' if rc and post_commits else ''}"
                            # f"{f'post{post_commits}' if post_commits else ''}"
                            )
                else:
                    raise ValueError(f"mode: {mode}")

            continue_commit = commit_id
            commits_found += 1
        post_commits -= 1


if __name__ == "__main__":
    sys.exit(main())
