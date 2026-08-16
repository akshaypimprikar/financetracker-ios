# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

## 2026-08-16 — PR#82 — git log triple-dot used for a gating decision
**What was wrong:** `scripts/check_tdd_commit_order.py` used `git log develop...HEAD` (triple-dot) to build the commit list its RED-before-GREEN violation detection depends on. For `git log` (unlike `git diff`), triple-dot is symmetric difference, not "commits unique to HEAD" — once `develop` advances past the branch's fork point, `develop`-only commits leak into the list and corrupt the ordering check. Also: `/gates` Gate 5's CHANGELOG-repair fallback text still assumed one commit per task, stale against this same PR's new two-commit RED/GREEN structure.
**Rule violated:** No formal rule — caught pre-review by `code-review:code-review` (3 independent review passes converged on the git-log issue; one flagged the stale Gate 5 text).
**File:** `scripts/check_tdd_commit_order.py:29` (now `:35`); `.claude/commands/gates.md:61`
**Caught by:** code-review:code-review
