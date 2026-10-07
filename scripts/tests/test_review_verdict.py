import io
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import review_verdict as rv  # noqa: E402


def f(sev, **kw):
    return dict(id=kw.pop("id", "x"), severity=sev, **kw)


class DecideTests(unittest.TestCase):
    def test_high_always_blocks(self):
        self.assertEqual(rv.decide([f("HIGH", advisory=True)])["verdict"], "CHANGES REQUESTED")

    def test_medium_in_diff_blocks(self):
        self.assertEqual(rv.decide([f("MEDIUM", in_diff=True)])["blocking"], ["x"])

    def test_medium_outside_diff_gets_issue(self):
        r = rv.decide([f("MEDIUM")])
        self.assertEqual((r["verdict"], r["issues"]), ("APPROVED", ["x"]))

    def test_advisory_medium_never_blocks(self):
        self.assertEqual(rv.decide([f("MEDIUM", in_diff=True, advisory=True)])["verdict"], "APPROVED")

    def test_medium_exceptions_block(self):
        self.assertEqual(rv.decide([f("MEDIUM", depends_on_unchanged=True)])["verdict"], "CHANGES REQUESTED")
        self.assertEqual(rv.decide([f("MEDIUM", guard_bypass=True)])["verdict"], "CHANGES REQUESTED")

    def test_low_never_blocks(self):
        self.assertEqual(rv.decide([f("LOW", in_diff=True)])["verdict"], "APPROVED")

    def test_dismissed_ignored(self):
        r = rv.decide([f("HIGH", dismissed=True)])
        self.assertEqual((r["verdict"], r["blocking"], r["issues"]), ("APPROVED", [], []))

    def test_no_findings_approved(self):
        self.assertEqual(rv.decide([])["verdict"], "APPROVED")


class MainTests(unittest.TestCase):
    def run_main(self, text):
        with mock.patch("sys.stdin", io.StringIO(text)):
            return rv.main()

    def test_bad_severity_exits_2(self):
        self.assertEqual(self.run_main('[{"id": "a", "severity": "SEVERE"}]'), 2)

    def test_non_list_exits_2(self):
        self.assertEqual(self.run_main("{}"), 2)

    def test_invalid_json_exits_2(self):
        self.assertEqual(self.run_main("{not json"), 2)

    def test_valid_exits_0(self):
        self.assertEqual(self.run_main("[]"), 0)


if __name__ == "__main__":
    unittest.main()
