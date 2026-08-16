# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

## 2026-08-16 — PR#83 — Gate-check false positive from an unhandled special case
**What was wrong:** The new `/sync-workflow` gate-numbering checklist assumed gate headings in `gates.md` are sequential starting at 1. It flagged `### Gate 0` (an intentional pre-check both FinanceTracker's and pragma's `gates.md` already exclude from their "N gates" count) as "non-sequential," a false positive on its first real run.
**Rule violated:** No formal rule — caught pre-review, during dogfooding against pragma PR #42, before this PR was opened.
**File:** `.claude/commands/sync-workflow.md` (checklist step 5c)
**Caught by:** manual verification (ran the checklist against a real diff before trusting it)

## 2026-08-16 — PR#83 — Self-review checklist referenced staging before it happened, and one check was case-sensitive
**What was wrong:** Step 5's self-review checklist claimed to run "against the staged diff," but `git add` only happened in the later step 6 — so step 5a's `git diff --cached` ran against nothing staged on first use. Separately, step 5c's gate-count consistency grep was case-sensitive and missed the capitalized `All N gates` line in `gates.md`'s "Done when" section — the exact line that's historically gone stale (commits `ddb58f0`, `1137aea`) — while step 5a in the same PR already used case-insensitive matching, making it an internal inconsistency.
**Rule violated:** No formal rule — caught pre-review by `code-review:code-review` (both issues scored 100/100 confidence).
**File:** `.claude/commands/sync-workflow.md` (step 5 intro; step 5c)
**Caught by:** code-review:code-review
