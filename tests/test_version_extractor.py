#!/usr/bin/env python3

"""Unit tests for version_extractor.py.

Run with `python -m unittest discover -s tests -t .` from the repository root.
"""

import unittest
from pathlib import Path
from subprocess import check_call, DEVNULL
from tempfile import TemporaryDirectory

from packaging.version import Version

import version_extractor

GIT_ISOLATION = ["-c", "commit.gpgsign=false",
                 "-c", "tag.gpgsign=false",
                 "-c", "user.email=test@example.invalid",
                 "-c", "user.name=Test",
                 "-c", "init.defaultBranch=master",
                 ]


def git(cwd: Path, *args):
    check_call(["git", *GIT_ISOLATION, *args], cwd=cwd, stdout=DEVNULL, stderr=DEVNULL)


class GitRepoTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        git(self.repo, "init")

    def commit(self, message="c"):
        git(self.repo, "commit", "--allow-empty", "-m", message)

    def release_file(self, value):
        f = self.root / f"release-{value}"
        f.write_text(str(value), encoding="utf-8")
        return f

    def version(self, release=0, mode="python"):
        return version_extractor.get_version(mode, self.repo,
                                             release_file=self.release_file(release))


class VersionOrderingTest(unittest.TestCase):
    """The invariants the scheme has to satisfy, stated as orderings.

    The release counter lives in the PEP 440 release segment, so the segment is
    the 4-tuple (major, minor, patch, release) compared lexicographically.
    """

    def assertIncreasing(self, versions):
        for lower, higher in zip(versions, versions[1:]):
            with self.subTest(lower=lower, higher=higher):
                self.assertLess(Version(lower), Version(higher))

    def test_counter_bump_outranks_the_published_version(self):
        # This is what makes a packaging-only rebuild releasable at all.
        self.assertIncreasing(["23.1.0.post45", "23.1.0.1.post45", "23.1.0.2.post45"])

    def test_upstream_commits_keep_increasing_under_a_fixed_counter(self):
        self.assertIncreasing(["23.1.0.1.post45", "23.1.0.1.post46", "23.1.0.1.post47"])

    def test_counter_may_reset_when_patch_minor_or_major_is_bumped(self):
        for bumped in ["23.1.1", "23.1.1.post3", "23.1.1rc1.post5", "23.2.0", "24.0.0rc1"]:
            with self.subTest(bumped=bumped):
                self.assertIncreasing(["23.1.0.9.post100", bumped])

    def test_counter_must_not_reset_when_only_an_rc_suffix_is_dropped(self):
        # rc3 -> final leaves x.y.z untouched, so the counter still dominates and
        # a reset would move the version backwards. Guards a real transition:
        # llvmorg-23.1.0-rc3 -> llvmorg-23.1.0.
        self.assertLess(Version("23.1.0"), Version("23.1.0.1rc3.post80"))
        self.assertIncreasing(["23.1.0.1rc3.post80", "23.1.0.1", "23.1.0.1.post45"])

    def test_counter_is_not_a_local_version(self):
        # PyPI MUST reject local versions, and it indexes on the public part.
        self.assertIsNone(Version("23.1.0.1.post45").local)
        self.assertEqual(Version("23.1.0.1.post45").public, "23.1.0.1.post45")
        self.assertEqual(Version("23.1.0.post45+1").public, "23.1.0.post45")

    def test_versions_are_not_prereleases(self):
        for v in ["23.1.0.post45", "23.1.0.1.post45", "23.1.0.1"]:
            with self.subTest(version=v):
                self.assertFalse(Version(v).is_prerelease)


class PythonVersionTest(GitRepoTestCase):
    """`-m python`: the wheel version, end to end against real repositories."""

    def test_final_tag_with_commits(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()
        self.commit()

        self.assertEqual(self.version(0), "23.1.0.post2")
        self.assertEqual(self.version(1), "23.1.0.1.post2")
        self.assertEqual(self.version(2), "23.1.0.2.post2")

    def test_exact_tag_no_commits(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")

        self.assertEqual(self.version(0), "23.1.0")
        self.assertEqual(self.version(1), "23.1.0.1")

    def test_rc_tag_with_commits(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0-rc3")
        self.commit()
        self.commit()
        self.commit()

        self.assertEqual(self.version(0), "23.1.0rc3.post3")
        # The counter goes into the release segment, before the rc marker.
        self.assertEqual(self.version(1), "23.1.0.1rc3.post3")

    def test_init_tag(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-24-init")
        self.commit()
        self.commit()

        self.assertEqual(self.version(0), "24.0.0.dev2")
        self.assertEqual(self.version(1), "24.0.0.1.dev2")

    def test_every_emitted_version_is_valid_pep440_and_ordered(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()
        self.commit()

        emitted = [self.version(r) for r in (0, 1, 2, 3)]
        for v in emitted:
            with self.subTest(version=v):
                self.assertIsNone(Version(v).local)
                self.assertFalse(Version(v).is_prerelease)
        for lower, higher in zip(emitted, emitted[1:]):
            self.assertLess(Version(lower), Version(higher))

    def test_carrying_the_counter_across_an_rc_being_dropped_moves_forward(self):
        # llvmorg-23.1.0-rc3 -> llvmorg-23.1.0 is not an X.Y.Z bump, so .release
        # is NOT reset and the emitted versions must still increase.
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0-rc3")
        self.commit()
        during_rc = self.version(2)

        git(self.repo, "tag", "llvmorg-23.1.0")
        at_final = self.version(2)

        self.commit()
        after_final = self.version(2)

        self.assertEqual([during_rc, at_final, after_final],
                         ["23.1.0.2rc3.post1", "23.1.0.2", "23.1.0.2.post1"])
        for lower, higher in zip([during_rc, at_final], [at_final, after_final]):
            self.assertLess(Version(lower), Version(higher))

    def test_missing_release_file_is_treated_as_zero(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()

        self.assertEqual(
            version_extractor.get_version("python", self.repo,
                                          release_file=self.root / "does-not-exist"),
            "23.1.0.post1")

    def test_empty_release_file_is_treated_as_zero(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()

        empty = self.root / "release-empty"
        empty.write_text("", encoding="utf-8")
        self.assertEqual(
            version_extractor.get_version("python", self.repo, release_file=empty),
            "23.1.0.post1")


class BaseModeTest(GitRepoTestCase):
    """`-m base` emits the X.Y.Z that scopes the .release counter.

    update.yml compares it before and after moving the submodule and rewrites
    .release to 0 when it changes, so these are the detection semantics.
    """

    def test_base_is_the_xyz_of_the_tag(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()

        self.assertEqual(self.version(0, "base"), "23.1.0")

    def test_rc_and_final_share_a_base_so_dropping_rc_triggers_no_reset(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0-rc3")
        self.commit()
        during_rc = self.version(0, "base")

        git(self.repo, "tag", "llvmorg-23.1.0")
        at_final = self.version(0, "base")

        self.assertEqual(during_rc, "23.1.0")
        self.assertEqual(at_final, "23.1.0")

    def test_base_changes_on_a_patch_bump_so_a_reset_is_triggered(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        before = self.version(0, "base")

        self.commit()
        git(self.repo, "tag", "llvmorg-23.1.1")
        after = self.version(0, "base")

        self.assertEqual(before, "23.1.0")
        self.assertEqual(after, "23.1.1")
        self.assertNotEqual(before, after)

    def test_base_ignores_the_release_counter(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-23.1.0")
        self.commit()

        for counter in (0, 1, 7):
            with self.subTest(counter=counter):
                self.assertEqual(self.version(counter, "base"), "23.1.0")

    def test_base_of_an_init_tag(self):
        self.commit("base")
        git(self.repo, "tag", "llvmorg-24-init")
        self.commit()

        self.assertEqual(self.version(0, "base"), "24.0.0")


if __name__ == "__main__":
    unittest.main()
