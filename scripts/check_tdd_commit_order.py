#!/usr/bin/env python3
"""
Verifies the RED step is reconstructable from git history: for every new
ViewModel/Service/Repository file added on this branch, its test file must
have been added in a strictly earlier commit — never the same commit, never
a later one. A test bundled into the same commit as its implementation is
unverifiable as "written and watched failing before the code existed."

Usage: python3 scripts/check_tdd_commit_order.py [base_ref]
  base_ref defaults to 'develop'
"""
import subprocess
import sys

BASE_REF = sys.argv[1] if len(sys.argv) > 1 else "develop"

SCOPED_PREFIXES = (
    "FinanceTracker/ViewModels/",
    "FinanceTracker/Services/",
    "FinanceTracker/Repositories/SwiftData/",
)


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def commit_list():
    out = run("git", "log", f"{BASE_REF}...HEAD", "--reverse", "--pretty=format:%H")
    return [line for line in out.splitlines() if line]


def added_files(sha):
    out = run("git", "show", "--diff-filter=A", "--name-only", "--pretty=format:", sha)
    return [line for line in out.splitlines() if line]


def all_test_files():
    out = run("git", "ls-tree", "-r", "--name-only", "HEAD", "--", "FinanceTrackerTests/")
    return [line for line in out.splitlines() if line]


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
        if not f.startswith(SCOPED_PREFIXES) or not f.endswith(".swift"):
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
    print("No new ViewModel/Service/Repository files with matching tests on this branch — skipping.")
else:
    print(f"RED-before-GREEN commit order OK — {checked} file(s) checked.")
sys.exit(0)
