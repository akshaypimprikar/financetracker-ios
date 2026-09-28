import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import check_review_evidence as ev  # noqa: E402

HEAD = "a" * 40
OLD = "b" * 40
CARRY = [".claude/context/rejections.md"]


def verdict(state, sha, when):
    return {"body": f"## Review Agent verdict: {state}\n\nReviewed at {sha}\nRound 1\n", "submitted_at": when}


def changed_between_factory(mapping):
    """mapping: {sha: list of files changed sha..HEAD, or None when sha is not an ancestor}."""
    def changed_between(sha):
        return mapping.get(sha)
    return changed_between


class EvaluateTests(unittest.TestCase):
    def run_eval(self, items, body="", reviews=(), mapping=None):
        results = ev.evaluate(items, HEAD, body, list(reviews), CARRY, changed_between_factory(mapping or {}))
        return {name: ok for name, ok, _ in results}

    def test_gate_summary_at_head(self):
        self.assertTrue(self.run_eval(["gate_summary"], body=f"Gates run at {HEAD}")["gate_summary"])

    def test_gate_summary_missing(self):
        self.assertFalse(self.run_eval(["gate_summary"], body="no summary")["gate_summary"])

    def test_gate_summary_uses_last_occurrence(self):
        body = f"Gates run at {OLD}\n...\nGates run at {HEAD}"
        self.assertTrue(self.run_eval(["gate_summary"], body=body)["gate_summary"])

    def test_stale_sha_with_non_carryover_change_fails(self):
        r = self.run_eval(["gate_summary"], body=f"Gates run at {OLD}", mapping={OLD: ["App/Model.swift"]})
        self.assertFalse(r["gate_summary"])

    def test_ancestor_with_only_carryover_change_passes(self):
        r = self.run_eval(["gate_summary"], body=f"Gates run at {OLD}", mapping={OLD: CARRY})
        self.assertTrue(r["gate_summary"])

    def test_non_ancestor_sha_fails(self):
        r = self.run_eval(["gate_summary"], body=f"Gates run at {OLD}", mapping={OLD: None})
        self.assertFalse(r["gate_summary"])

    def test_verdict_approved_at_head(self):
        r = self.run_eval(["review_verdict"], reviews=[verdict("APPROVED", HEAD, "2026-09-28T10:00:00Z")])
        self.assertTrue(r["review_verdict"])

    def test_latest_verdict_wins(self):
        reviews = [verdict("APPROVED", HEAD, "2026-09-28T10:00:00Z"),
                   verdict("CHANGES REQUESTED", HEAD, "2026-09-28T11:00:00Z")]
        self.assertFalse(self.run_eval(["review_verdict"], reviews=reviews)["review_verdict"])

    def test_latest_verdict_wins_regardless_of_list_order(self):
        reviews = [verdict("APPROVED", HEAD, "2026-09-28T12:00:00Z"),
                   verdict("CHANGES REQUESTED", HEAD, "2026-09-28T11:00:00Z")]
        self.assertTrue(self.run_eval(["review_verdict"], reviews=reviews)["review_verdict"])

    def test_approved_confirm_verdict(self):
        body = f"## Review Agent verdict: APPROVED (confirm)\n\nReviewed at {HEAD}\nRound confirm\n"
        r = self.run_eval(["review_verdict"], reviews=[{"body": body, "submitted_at": "2026-09-28T10:00:00Z"}])
        self.assertTrue(r["review_verdict"])

    def test_verdict_without_sha_fails(self):
        r = self.run_eval(["review_verdict"], reviews=[{"body": "## Review Agent verdict: APPROVED\n",
                                                        "submitted_at": "2026-09-28T10:00:00Z"}])
        self.assertFalse(r["review_verdict"])

    def test_non_verdict_reviews_ignored(self):
        r = self.run_eval(["review_verdict"], reviews=[{"body": f"LGTM APPROVED Reviewed at {HEAD}",
                                                        "submitted_at": "2026-09-28T10:00:00Z"}])
        self.assertFalse(r["review_verdict"])

    def test_code_review_no_issues(self):
        r = self.run_eval(["code_review"], body=f"code-review: no issues at {HEAD}")
        self.assertTrue(r["code_review"])

    def test_code_review_comment_url(self):
        body = f"code-review: https://github.com/o/r/pull/1#issuecomment-1 at {HEAD}"
        self.assertTrue(self.run_eval(["code_review"], body=body)["code_review"])

    def test_code_review_missing_sha_fails(self):
        self.assertFalse(self.run_eval(["code_review"], body="code-review: no issues")["code_review"])

    def test_motivating_incident(self):
        self.assertTrue(self.run_eval(["motivating_incident"], body="Motivating incident: PR #130")["motivating_incident"])
        self.assertTrue(self.run_eval(["motivating_incident"], body="Motivating incident: none (dependency bump)")["motivating_incident"])
        self.assertFalse(self.run_eval(["motivating_incident"], body="Motivating incident:   ")["motivating_incident"])
        self.assertFalse(self.run_eval(["motivating_incident"], body="nothing")["motivating_incident"])

    def test_synced_from(self):
        self.assertTrue(self.run_eval(["synced_from"], body="Synced from: akshaypimprikar/financetracker-ios#132")["synced_from"])
        self.assertFalse(self.run_eval(["synced_from"], body="")["synced_from"])

    def test_no_items_passes(self):
        self.assertEqual(ev.evaluate([], HEAD, "", [], CARRY, changed_between_factory({})), [])

    def test_none_body_is_treated_as_empty(self):
        self.assertFalse(self.run_eval(["gate_summary"], body=None)["gate_summary"])


if __name__ == "__main__":
    unittest.main()
