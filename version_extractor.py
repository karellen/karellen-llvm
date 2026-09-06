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

def read_release(release_file: Union[str, Path]) -> int:
    """Return the packager release counter, or 0 if unset.

    The counter is the 4th component of the PEP 440 release segment, so it
    outranks `.postN` and is only correct for the LLVM base version it was set
    against. It MUST go back to 0 when X.Y.Z is bumped -- otherwise the next
    upstream commit yields a version sorting below the previous release. The
    auto-update workflow does that reset when it moves the submodule; see
    CLAUDE.md, "Versioning".
    """
    if not exists(release_file):
        return 0
    with open(release_file, "rt") as f:
        return int(f.read().strip() or 0)


parser = argparse.ArgumentParser()

parser.add_argument("-m", "--mode", choices=["python", "cmake", "tag", "is-tag", "base"],
                    default="python")
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


def get_version(mode: Union[str, Path], git_dir: Union[str, Path], skip_current_tag: bool = False,
                release_file: Union[str, Path] = ".release"):
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
                    release = read_release(release_file)
                    # The counter is a 4th component of the release segment, not a
                    # local version (`+N`): PyPI MUST reject local versions. See
                    # read_release above and CLAUDE.md, "Versioning".
                    return (f"{major}.{minor}.{patch}"
                            f"{f'.{release}' if release else ''}"
                            f"{f'{rc}' if rc else ''}"
                            f"{f'.post{post_commits}' if post_commits else ''}"
                            )
                elif mode == "base":
                    # X.Y.Z alone: the scope of the .release counter. A change here
                    # is what requires .release to be reset back to 0.
                    return f"{major}.{minor}.{patch}"
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
