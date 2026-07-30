# PR Followup Agent

Auto-chains `/review` then `/test` immediately after a PR is opened — the two
pipeline stages that can run without a human trigger.

`code-review:code-review` is deliberately excluded: it has
`disable-model-invocation` set and does not appear in the agent-invocable skill
list at all, so no agent-driven path — this command included — can trigger it
(confirmed 2026-07-30, on FinanceTracker PRs #67-#70). It must be run manually.

## Trigger
Invoked right after `gh pr create` succeeds, or manually against an existing
PR: `/pr-followup 71` or `/pr-followup fix/some-branch`.

## Process
1. Run `/review <PR>`.
2. If the verdict is **CHANGES REQUESTED**, stop — do not run `/test` until the
   issues are addressed and the branch is re-reviewed.
3. If the verdict is **APPROVED**, run `/test <PR>`.
4. Report both verdicts, then print exactly this line:
   `⚠️ code-review:code-review still needs to run manually — it can't be triggered by an agent. Run it yourself before merging.`

## Done when
`/review` and `/test` have both reported and the code-review reminder has been
printed. Do not merge — per CLAUDE.md's Merge rule, merging is the user's call
once all three (review, test, code-review) are clean.
