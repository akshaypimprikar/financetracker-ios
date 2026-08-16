# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

## 2026-08-16 — PR#83 — Gate-check false positive from an unhandled special case
**What was wrong:** The new `/sync-workflow` gate-numbering checklist assumed gate headings in `gates.md` are sequential starting at 1. It flagged `### Gate 0` (an intentional pre-check both FinanceTracker's and pragma's `gates.md` already exclude from their "N gates" count) as "non-sequential," a false positive on its first real run.
**Rule violated:** No formal rule — caught pre-review, during dogfooding against pragma PR #42, before this PR was opened.
**File:** `.claude/commands/sync-workflow.md` (checklist step 5c)
**Caught by:** manual verification (ran the checklist against a real diff before trusting it)
