"""Gate 0's build-relevance pathspec must keep matching project-file changes.

Both copies of the pathspec in .claude/skills/gates/SKILL.md (Gate 0 and the
importHash golden-test skip under Gate 9) are run against a scratch git repo,
so dropping a pattern, or the two copies drifting apart, fails here instead of
silently skipping build and test (#158).
"""
import os
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SKILL = os.path.join(ROOT, ".claude", "skills", "gates", "SKILL.md")
WORKFLOWS = os.path.join(ROOT, ".github", "workflows")
PATHSPEC = re.compile(r"git diff develop\.\.\.HEAD --name-only -- ('\*\.swift'[^|\n]*?)\s*(?:\||$)", re.M)

BUILD_RELEVANT = [
    "App.xcodeproj/project.pbxproj",
    "App.xcodeproj/project.xcproj",
    "App.xcodeproj/xcshareddata/xcschemes/App.xcscheme",
    "App.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings",
    "App.xcworkspace/contents.xcworkspacedata",
    "App/Thing.swift",
    "App/Info.plist",
    "Config/Debug.xcconfig",
    "App.xctestplan",
]
NOT_BUILD_RELEVANT = ["docs/notes.md", "README.md"]


def pathspecs():
    with open(SKILL) as f:
        # Gates 3-13 grep '*.swift' alone; only the build-relevance pathspec lists more.
        return [m.group(1).strip() for m in PATHSPEC.finditer(f.read()) if m.group(1).strip() != "'*.swift'"]


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def changed(spec, path):
    """Files Gate 0 lists when a branch off develop changes only `path`."""
    with tempfile.TemporaryDirectory() as d:
        git(d, "init", "-q", "-b", "develop")
        git(d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "base")
        git(d, "checkout", "-q", "-b", "fix/x")
        full = os.path.join(d, path)
        os.makedirs(os.path.dirname(full) or d, exist_ok=True)
        with open(full, "w") as f:
            f.write("x\n")
        git(d, "add", "-A")
        git(d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "change")
        return git(d, "diff", "develop...HEAD", "--name-only", "--", *shlex.split(spec)).split()


class Gate0PathspecTests(unittest.TestCase):
    def test_both_copies_present_and_identical(self):
        specs = pathspecs()
        self.assertEqual(len(specs), 2, specs)
        self.assertEqual(specs[0], specs[1])

    def test_project_and_build_inputs_listed(self):
        spec = pathspecs()[0]
        for path in BUILD_RELEVANT:
            with self.subTest(path=path):
                self.assertEqual(changed(spec, path), [path])

    def test_docs_only_change_lists_nothing(self):
        spec = pathspecs()[0]
        for path in NOT_BUILD_RELEVANT:
            with self.subTest(path=path):
                self.assertEqual(changed(spec, path), [])


class WorkflowPathFilterTests(unittest.TestCase):
    def test_app_workflows_trigger_on_project_bundle(self):
        for name in ("pr-checks.yml", "ui-tests.yml", "concurrency-advisory.yml"):
            with self.subTest(workflow=name), open(os.path.join(WORKFLOWS, name)) as f:
                text = f.read()
                self.assertEqual(text.count("- 'FinanceTracker/**'"), text.count("- 'FinanceTracker.xcodeproj/**'"))
                self.assertIn("- 'FinanceTracker.xcodeproj/**'", text)


if __name__ == "__main__":
    unittest.main()
