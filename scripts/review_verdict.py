#!/usr/bin/env python3
"""Decide which review findings block a PR and print the verdict.

Reads a JSON list of findings on stdin. Each finding has `id` and `severity`
(HIGH, MEDIUM or LOW), and optional booleans, all default false:
  dismissed            quoted code disproves it; ignored here
  advisory             the checklist item is marked (advisory)
  in_diff              a defect in lines the PR adds or changes
  depends_on_unchanged unchanged code the PR's change needs to work
  guard_bypass         names a concrete input or sequence that bypasses a guard in
                       .claude/hooks/, gates, review or scripts/check_*

Rules (the same ones review/SKILL.md "Merge its output" describes):
  HIGH    always blocks, on any item
  MEDIUM  blocks unless advisory, and only when in_diff, depends_on_unchanged or guard_bypass
  LOW     never blocks
A finding that does not block gets an issue instead.

Output: {"verdict": "APPROVED"|"CHANGES REQUESTED", "blocking": [ids], "issues": [ids]}
Usage: review_verdict.py < findings.json
Exit codes: 0 verdict printed, 2 bad input.
"""
import json
import sys

SEVERITIES = ("HIGH", "MEDIUM", "LOW")


def blocks(f):
    if f["severity"] == "HIGH":
        return True
    if f["severity"] == "MEDIUM":
        return not f.get("advisory") and bool(
            f.get("in_diff") or f.get("depends_on_unchanged") or f.get("guard_bypass"))
    return False


def decide(findings):
    blocking, issues = [], []
    for f in findings:
        if f.get("dismissed"):
            continue
        (blocking if blocks(f) else issues).append(f["id"])
    return {"verdict": "CHANGES REQUESTED" if blocking else "APPROVED", "blocking": blocking, "issues": issues}


def main(argv=None):
    try:
        findings = json.load(sys.stdin)
        if not isinstance(findings, list):
            raise ValueError("input must be a JSON list")
        for f in findings:
            if not isinstance(f, dict) or "id" not in f or f.get("severity") not in SEVERITIES:
                raise ValueError(f"bad finding {f!r}: needs 'id' and severity one of {SEVERITIES}")
        print(json.dumps(decide(findings)))
        return 0
    except ValueError as e:
        print(f"review_verdict: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
