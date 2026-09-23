#!/usr/bin/env python3
"""
Verifies the RED step is reconstructable from git history: for every new
ViewModel/Service/Repository file added on this branch, its test file must
have been added in a strictly earlier commit — never the same commit, never
a later one. A test bundled into the same commit as its implementation is
unverifiable as "written and watched failing before the code existed" —
nothing distinguishes that from writing both together and never running the
test red.

Usage: python3 scripts/check_tdd_commit_order.py [base_ref]
  base_ref defaults to 'develop'
"""
import subprocess
import sys

BASE_REF = sys.argv[1] if len(sys.argv) > 1 else "develop"

# Path segments (not full prefixes) so this doesn't depend on the app's root
# folder name being repeated in the match. Repositories/SwiftData/ only —
# not all of Repositories/ — since the sibling Repositories/Protocols/ layer
# has no 1:1 <Type>.swift -> <Type>Tests.swift convention (a protocol
# declaration isn't tested directly, only its concrete implementations are);
# broadening to all of Repositories/ would flag protocol files as violations
# for having no matching test.
SCOPED_LAYER_DIRS = ("/ViewModels/", "/Services/", "/Repositories/SwiftData/")
TEST_ROOT = "FinanceTrackerTests/"

# core.quotepath=false: without it, git wraps any path containing a
# non-ASCII byte in literal quotes and octal-escapes it (e.g.
# "café.swift" -> "\"caf\\303\\251.swift\""), corrupting every basename
# comparison below for that file — verified empirically, not assumed.
# Shared by every git call below via explicit unpacking, not a run()
# that silently discards and replaces its first argument.
GIT_BASE_ARGS = ("git", "-c", "core.quotepath=false")


def run(*args):
    # errors="replace": non-UTF-8 bytes in a commit message or path must not
    # crash this script outright — decode what's decodable, substitute the rest.
    return subprocess.run(
        args, capture_output=True, text=True, errors="replace", check=True,
    ).stdout


def commit_list():
    # Double-dot, not triple-dot: git log's triple-dot is symmetric difference
    # (commits on either side, not just HEAD's), unlike git diff's triple-dot
    # (merge-base diff). Triple-dot here would pull in develop-only commits
    # whenever develop advances after this branch was cut, corrupting the
    # commit ordering this script's violation detection depends on.
    out = run(*GIT_BASE_ARGS, "log", f"{BASE_REF}..HEAD", "--reverse", "--pretty=format:%H")
    return [line for line in out.splitlines() if line]


def added_files(sha):
    out = run(*GIT_BASE_ARGS, "show", "--diff-filter=A", "--name-only", "--pretty=format:", sha)
    return [line for line in out.splitlines() if line]


def all_test_files():
    out = run(*GIT_BASE_ARGS, "ls-tree", "-r", "--name-only", "HEAD", "--", TEST_ROOT)
    return [line for line in out.splitlines() if line]


def repo_has_any_scoped_file():
    # Repo-wide, not just this branch's diff: distinguishes "this branch
    # legitimately touches no scoped layer today" from "SCOPED_LAYER_DIRS no
    # longer matches this project's actual layer folders" — the latter must
    # not look like a clean pass.
    out = run(*GIT_BASE_ARGS, "ls-tree", "-r", "--name-only", "HEAD")
    return any(any(seg in line for seg in SCOPED_LAYER_DIRS) for line in out.splitlines())


commits = commit_list()
if not commits:
    print(f"No commits ahead of {BASE_REF} — nothing to check.")
    sys.exit(0)

test_files_by_basename = {}
for path in all_test_files():
    test_files_by_basename.setdefault(path.rsplit("/", 1)[-1], path)

first_added_index = {}
added_per_commit = []
for i, sha in enumerate(commits):
    files = added_files(sha)
    added_per_commit.append(files)
    for f in files:
        first_added_index.setdefault(f, i)

violations = []
checked = 0
for i, files in enumerate(added_per_commit):
    for f in files:
        if not any(seg in f for seg in SCOPED_LAYER_DIRS) or not f.endswith(".swift") or TEST_ROOT in f:
            continue
        base = f.rsplit("/", 1)[-1]
        test_basename = base[: -len(".swift")] + "Tests.swift"
        test_path = test_files_by_basename.get(test_basename)
        if test_path is None:
            continue  # no matching test file at all — Gate 6 (coverage) catches this, not Gate 11
        test_index = first_added_index.get(test_path)
        if test_index is None:
            continue  # test file predates this branch — not a new-file case
        checked += 1
        if test_index == i:
            violations.append(
                f"{f} — test file {test_path} committed in the SAME commit "
                f"({commits[i][:8]}) — red step not separately verifiable"
            )
        elif test_index > i:
            violations.append(
                f"{f} — test file {test_path} committed AFTER implementation "
                f"({commits[test_index][:8]} follows {commits[i][:8]}) — tests-after, not TDD"
            )

if violations:
    print(f"\n=== RED-before-GREEN commit order: {len(violations)} violation(s) ===\n")
    for v in violations:
        print(f"  [FAIL] {v}")
    print()
    sys.exit(1)

if checked == 0:
    if not repo_has_any_scoped_file():
        print(
            f"WARNING: no file anywhere in this repo matches SCOPED_LAYER_DIRS {SCOPED_LAYER_DIRS} — "
            "these layer folders may have been renamed or moved. Update SCOPED_LAYER_DIRS at the top "
            "of this file before trusting this gate; until then, every run will silently no-op instead "
            "of checking anything."
        )
        sys.exit(2)
    print("No new ViewModel/Service/Repository files with matching tests on this branch — skipping.")
else:
    print(f"RED-before-GREEN commit order OK — {checked} file(s) checked.")
sys.exit(0)
