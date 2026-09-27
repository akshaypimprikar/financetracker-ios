# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

## 2026-08-18 — PR#99 — New junk-detection hooks self-matched their own stored command text
**What was wrong:** The `PreToolUse`/`SessionEnd` hooks added to detect leftover session-specific junk in `.claude/settings.json` grepped the *entire raw file* for the exact literal pattern (`/private/tmp/claude-`, `"pid":[0-9]`, etc.) that the hook's own `command` string — itself stored inside that same file — also contains verbatim. The hooks matched themselves on every single run, reporting "junk detected" unconditionally, including immediately after a clean prune, making the feature permanently useless. `/review` approved the PR before this was caught, since it only confirms gates/design/code-quality checks, not runtime behavior of new hook logic.
**Rule violated:** No formal rule — caught by `code-review:code-review`, independently across its shallow-bug-scan and code-comment-compliance passes.
**File:** `.claude/settings.json:170,180` (fixed by scoping the grep to `jq -r '.permissions.allow[]'` instead of the raw file, so the hooks' own command text under `.hooks` is never part of what gets scanned)
**Caught by:** code-review:code-review

## 2026-08-18 — PR#98 — DashboardViewModel.categorySpending duplicated a filter pass and reimplemented debit-summation instead of reusing BudgetCalculationService
**What was wrong:** The first draft of `categorySpending`'s aggregation re-scanned `allTransactions` with a near-duplicate predicate to `spendingThisMonth`'s existing filter (only adding `$0.category != nil`), and summed each category group's transactions with an inline `.reduce(Decimal.zero) { $0 + $1.amount }` instead of calling `BudgetCalculationService.totalSpent(transactions:)`, which the same class already holds as `budgetCalcService` and uses for `budgetProgresses` two lines later. Left as-is, "what counts as spending" would have lived in 3 places in one file, able to silently diverge.
**Rule violated:** No formal rule — caught pre-review by `/simplify`'s reuse, simplification, efficiency, and altitude agents (all 4 independently flagged variants of the same duplication).
**File:** `FinanceTracker/ViewModels/DashboardViewModel.swift:61-73` (now filters `allTransactions` once into `thisMonthDebits` and calls `budgetCalcService.totalSpent` for both `spendingThisMonth` and each category group)
**Caught by:** /simplify

## 2026-08-18 — PR#98 — DashboardView's two Glass Cards hand-rolled the same background+shadow recipe twice
**What was wrong:** `netWorthCard` and `spendingCard` each inlined an identical 5-statement `RoundedRectangle.fill(cardMaterial).overlay(RoundedRectangle.fill(tint))` + `.shadow(...)` block, differing only in corner-radius and tint tokens — duplication introduced by the diff itself (the file had no prior `.background(` shape composition to follow). All 4 `/simplify` agents flagged it as a reuse/simplification/altitude issue: a third glass card anywhere in the app would likely become a third copy-paste rather than a call into shared infrastructure.
**Rule violated:** No formal rule — caught pre-review by `/simplify`'s reuse, simplification, efficiency, and altitude agents (efficiency's specific shadow-rasterization suggestion was evaluated and skipped as speculative/unverified without profiling; the duplication finding was fixed).
**File:** `FinanceTracker/Views/Dashboard/DashboardView.swift` (extracted a private `View.glassCardBackground(cornerRadius:tint:)` modifier, both cards now call it)
**Caught by:** /simplify

## 2026-08-16 — PR#91 — @Observable stored cache/counter fields not marked @ObservationIgnored
**What was wrong:** `TransactionViewModel.filteredTransactions`'s new memoization added `cachedFilteredTransactions` and `filterComputeCount` as plain stored properties on an `@Observable` class. `filteredTransactions` reads `cachedFilteredTransactions` (registering it as an observation dependency) then writes to both it and `filterComputeCount` within the same call — a read-then-write of a tracked property in one call is a known `@Observable` footgun that can schedule a redundant re-render right after the one that just ran, partially defeating the point of memoizing.
**Rule violated:** No formal rule — caught pre-review by `/simplify`'s efficiency-angle agent.
**File:** `FinanceTracker/ViewModels/TransactionViewModel.swift:18-19` (now with `@ObservationIgnored`)
**Caught by:** /simplify

## 2026-08-16 — PR#91 — .task(id:) suggested by all 4 /simplify agents, would have introduced a double-load regression
**What was wrong:** `/simplify`'s 4 parallel review agents unanimously recommended replacing `BudgetListView`'s hand-rolled `@State Task`/cancel debounce with SwiftUI's `.task(id: viewModel.selectedMonth)`. Applied first, then caught before commit: `.task(id:)` also fires on initial view appearance, and this view already has a separate `.onAppear { viewModel.load() }` for the first load — combining both would double-load every time the screen opens. None of the 4 review agents could see this, since each was shown only the diff hunk, not the full file (the `.onAppear` line was outside the diff). Reverted to `.onChange` (which correctly does not fire on initial appearance) but kept the real bug the agents did catch: nothing cancelled the in-flight debounce `Task` on view disappear. Added `.onDisappear { loadTask?.cancel() }`.
**Rule violated:** No formal rule — caught via manual verification against the full file before committing, not by any review pass.
**File:** `FinanceTracker/Views/Budgets/BudgetListView.swift:9-27`
**Caught by:** manual verification

## 2026-08-16 — PR#82 — git log triple-dot used for a gating decision
**What was wrong:** `scripts/check_tdd_commit_order.py` used `git log develop...HEAD` (triple-dot) to build the commit list its RED-before-GREEN violation detection depends on. For `git log` (unlike `git diff`), triple-dot is symmetric difference, not "commits unique to HEAD" — once `develop` advances past the branch's fork point, `develop`-only commits leak into the list and corrupt the ordering check. Also: `/gates` Gate 5's CHANGELOG-repair fallback text still assumed one commit per task, stale against this same PR's new two-commit RED/GREEN structure.
**Rule violated:** No formal rule — caught pre-review by `code-review:code-review` (3 independent review passes converged on the git-log issue; one flagged the stale Gate 5 text).
**File:** `scripts/check_tdd_commit_order.py:29` (now `:35`); `.claude/commands/gates.md:61`
**Caught by:** code-review:code-review

## 2026-08-16 — PR#85 — feature-log.md entry ambiguous about which gate was ported to pragma
**What was wrong:** The v1.2.1 entry listed Gate 10 and Gate 11 together, then added a dangling clause "ported as a generic gate to the pragma template repo" with no clear subject. Read as applying to Gate 10, it's backwards: Gate 10 (duplication/abstraction-bloat heuristic) originated in pragma and was restored into FinanceTracker, the opposite direction. Only Gate 11 was actually ported to pragma.
**Rule violated:** No formal rule — caught pre-review by `code-review:code-review` (scored 75/100 confidence; below the auto-post threshold but confirmed real).
**File:** `.claude/context/feature-log.md:6`
**Caught by:** code-review:code-review

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

## 2026-08-19 — PR#100 — permissions.ask wildcards missing word boundary, one caused a real collision
**What was wrong:** The 9 new `permissions.ask` entries gating Agent Reach write actions (LinkedIn/Reddit/Twitter) all glued the trailing `*` directly onto the command with no space, breaking this file's unanimous existing convention (`Bash(<command> *)`, e.g. `Bash(gh pr *)`, `Bash(git merge *)`). One instance was a real, verified collision, not just a stylistic gap: `Bash(twitter follow*)` matched any command starting with the literal text "twitter follow", which includes the unrelated read-only commands `twitter followers` and `twitter following` — forcing an unnecessary approval prompt on reads, contradicting the PR's own claim that read-only calls are unaffected. `/review` approved the PR before this was caught, since it only checks architecture/design/code-quality against CLAUDE.md, not runtime prefix-match behavior of new permission rules.
**Rule violated:** No formal rule — caught by `code-review:code-review`, independently by two of five review agents (historical-context/rejections.md-history angle and code-comment/file-convention angle), converging on the same root cause from different directions.
**File:** `.claude/settings.json:135-144` and `~/.claude/settings.json` (global copy) — fixed by adding a space before the wildcard on all 9 entries, commit 88e6ce2
**Caught by:** code-review:code-review

## 2026-09-08 — PR#105 — Round 1: overclaim about Gate 9's diff scope
**What was wrong:** `parallel-review.md`'s Check 1, while porting pragma's converged fix, said Gate 9's commands "already use `git diff develop...HEAD`, the same scope this command needs," with no exception noted. Gate 9's UI-selector-listing command (`.claude/commands/gates.md:121-122`) actually scans all of `FinanceTrackerUITests/*.swift` unconditionally, not the branch diff like every other Gate 9 command — the framing gave no warning of that one exception.
**Rule violated:** No formal rule — pure docs/process content not covered by an actual CLAUDE.md architecture rule; caught on correctness grounds.
**File:** `.claude/commands/parallel-review.md`
**Caught by:** code-review pass (round 1, documented in PR#105 body — mirrors pragma PR#56's identical Round 1 entry, the upstream source of this fix)

## 2026-09-08 — PR#105 — Round 2: run-on sentence, ambiguous wording
**What was wrong:** Two more wording issues surfaced in the same file while porting: Check 1 was a single long run-on sentence covering three different checks and scoping rules in one breath, and `Done when`'s "combined verdict from the three above" was ambiguous — unclear whether it meant three checks or three possible verdict strings.
**Rule violated:** No formal rule — pure docs/process content not covered by an actual CLAUDE.md architecture rule; caught on correctness grounds.
**File:** `.claude/commands/parallel-review.md`
**Caught by:** code-review pass (round 2, documented in PR#105 body — mirrors pragma PR#56's identical Round 2 entry, the upstream source of this fix)

## 2026-09-08 — PR#105 — Round 3: duplication regression in the fallback wording
**What was wrong:** Round 2's own fix restated `/pr-followup`'s fallback warning string as an independently-authored copy with one word swapped, instead of referencing it — the exact duplication-drift pattern pragma's own rejections.md had already flagged as a repeat-violation risk on this same file (see pragma PR#55 Round 2/3/5, and pragma PR#56 Round 3). Fixed by replacing it with an explicit, mechanical substitution rule (take `/pr-followup`'s canonical string, swap `before merging` → `before /gates`), so there is no independently-maintained copy left to drift.
**Rule violated:** No formal rule — pure docs/process content not covered by an actual CLAUDE.md architecture rule; caught on correctness grounds. (Repeats a duplication pattern named in pragma's own rejections.md; caught and fixed pre-merge this time.)
**File:** `.claude/commands/parallel-review.md`
**Caught by:** code-review pass (round 3, documented in PR#105 body — mirrors pragma PR#56's identical Round 3 entry, the upstream source of this fix)

## 2026-09-25 — PR#126 — Incomplete instruction contract
**What was wrong:** Moving /review's judgment checks into a fresh-context subagent left two rules behind: only checklist FAILs had to reach the verdict (so the subagent's other defects could be dropped silently, contradicting the Isolated review block and CHANGELOG), and the subagent was never told that repeats of rejections.md/incidents.md entries are HIGH severity.
**Rule violated:** no formal rule, caught pre-merge
**File:** .claude/skills/review/SKILL.md:94-106
**Caught by:** this review (isolated subagent) and code-review:code-review, independently

## 2026-09-25 — PR#126 — Ambiguous subagent input scope
**What was wrong:** "Give it only" listed the diff and rule files but didn't say whether repo source beyond diff hunks is allowed, which checklist items like "functions do one thing" need.
**Rule violated:** no formal rule, caught pre-merge
**File:** .claude/skills/review/SKILL.md:90-99
**Caught by:** this review (isolated subagent)

## 2026-09-27 — PR#130 — Edited past log entries against the file's own rule
**What was wrong:** Changed "caught pre-merge" to "caught pre-review" in two PR#126 entries, although this file's header says "Never edit past entries", and "pre-merge" was accurate for issues a review found. The real gap was the template, which only worded case 2.
**Rule violated:** no formal rule, caught in review
**File:** .claude/context/rejections.md:85,91
**Caught by:** this review (isolated subagent)

## 2026-09-27 — PR#130 — False claim about another skill
**What was wrong:** feature/SKILL.md:27 said /parallel-review "gives its checks to no fresh-context subagent", but its Check 2 runs code-review:code-review, which uses separate review agents.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/feature/SKILL.md:27
**Caught by:** this review (isolated subagent)

## 2026-09-27 — PR#130 — Round 2: blocking rule still ambiguous for advisory items
**What was wrong:** The round 1 fix ("a HIGH finding blocks even on an advisory item") left a MEDIUM finding on an advisory item with opposite answers, and the APPROVED line still said "advisory FAILs do not" block with no exception.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:118-119, :155
**Caught by:** this review (isolated subagent, round 2)

## 2026-09-27 — PR#130 — Round 3: severity tiers undefined, so a required FAIL could stop blocking
**What was wrong:** Blocking depended only on HIGH/MEDIUM/LOW, but the tiers were never defined and a required checklist FAIL had no minimum severity. A FAIL rated LOW would not block, a regression from the old rule, where any non-advisory FAIL blocked.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:104, :119-122, :157
**Caught by:** this review (isolated subagent, round 3)

## 2026-09-27 — PR#130 — Round 4: the HIGH floor was implied, not stated
**What was wrong:** "Never below the floors in the severity scale" stated only the MEDIUM floor for required FAILs, so a HIGH repeat could be lowered to MEDIUM with a reason and stop blocking on an advisory item. That undid "HIGH always blocks".
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:125-126
**Caught by:** this review (isolated subagent, round 4)

## 2026-09-27 — PR#130 — Case 2 logging would duplicate earlier review rounds
**What was wrong:** Once a PR's body listed fixes under "Found in review and fixed", a final APPROVED /review would log them again under case 2, labeled "caught pre-review". But earlier /review rounds had already logged them under case 1 ("caught in review"). The duplicates would inflate the history that repeat detection reads.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:163-165
**Caught by:** code-review pass (code-review:code-review on PR#130)

## 2026-09-27 — PR#130 — Round 6: the case-2 skip rule was too narrow, and its label was timing-dependent
**What was wrong:** The skip rule only covered items logged by earlier /review rounds, so a fix logged by a code-review round would still be logged twice (a follow-up to this PR's "Case 2 logging would duplicate" entry). The case-2 label "caught pre-review" was wrong for code-review rounds that run after /review.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:170, :175
**Caught by:** this review (isolated subagent, round 6)

## 2026-09-27 — PR#130 — Round 8: the skip rule covered only case 2
**What was wrong:** The "already has an entry" skip applied only to case 2, so a later CHANGES REQUESTED round that found a still-unfixed issue would log it again under case 1.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:168-169, :179
**Caught by:** this review (isolated subagent, round 8)

## 2026-09-27 — PR#130 — Round 9: skip condition out of step, and regressions could be skipped
**What was wrong:** After round 8 extended the skip to case 1, the "skip this step only if" line still required logging any CHANGES REQUESTED issue, which contradicted the skip. "Already has an entry" also didn't separate an unfixed issue (skip it) from a regression of a fixed one (log it).
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:171-173, :183
**Caught by:** this review (isolated subagent, round 9)

## 2026-09-27 — PR#130 — Round 10: the skip condition's wording inverted its intent
**What was wrong:** "Skip an item that already has an entry and has not been fixed since" can never skip a case-2 item, because those are fixes by definition. A final APPROVED review would log every earlier-round finding again.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:171-172
**Caught by:** this review (isolated subagent, round 10)

## 2026-09-27 — PR#130 — Round 11: the skip line required logging that no case asks for
**What was wrong:** "Skip this step only if every issue this review found … already has an entry" ignored that case 1 logs only on CHANGES REQUESTED. An APPROVED review with only non-blocking findings could never skip, which invited logging no case requires.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:184-185
**Caught by:** this review (isolated subagent, round 11)

## 2026-09-27 — PR#130 — Repeat rule and case-1 logging turned non-blocking findings into blocking HIGHs
**What was wrong:** The repeat rule counted this PR's own earlier-round entries, so an unfixed LOW logged in one round became a HIGH repeat the next round and blocked. Case 1 logged every finding, including non-blocking and dismissed ones, which filled repeat history with non-violations.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:102-104, :168
**Caught by:** code-review pass (code-review:code-review on PR#130)

## 2026-09-27 — PR#130 — Round 13: case 1 stopped logging gate-verification failures
**What was wrong:** Narrowing case 1 to "accepted findings that block" (a code-review fix) dropped CHANGES REQUESTED verdicts caused only by gate-verification failures (a stale SHA, a TODO hit, a missing CHANGELOG entry, TDD order), which the old "log each issue found here" covered.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:170-172
**Caught by:** this review (isolated subagent, round 13)

## 2026-09-27 — PR#130 — Round 14: the regression half of the repeat rule had no enforcer
**What was wrong:** The subagent can't see the PR body, and code-review or non-blocking fixes aren't in rejections.md until case 2 runs. So a mid-PR regression of such a fix looked new, and nothing told the session (the only party that sees the body) to check. The regression exception also pointed at an entry that might not exist yet.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:102-104, :175-178
**Caught by:** this review (isolated subagent, round 14)

## 2026-09-27 — PR#130 — Round 15: the subagent was asked to rate regressions it couldn't see
**What was wrong:** The subagent's repeat rule included "comes back after being fixed earlier in this PR", but without the PR body or history it couldn't tell a regression from a still-unfixed item. The session's backstop checked only the PR body, not this PR's own rejections.md entries.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:102-105, :129-131
**Caught by:** this review (isolated subagent, round 15)

## 2026-09-27 — PR#130 — Round 16: the subagent couldn't tell which entries were this PR's
**What was wrong:** The subagent was told "Entries for this PR are not repeats" but was never given the PR number, and it is barred from gh pr view and gh api.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md (subagent inputs)
**Caught by:** this review (isolated subagent, round 16)

## 2026-09-27 — PR#130 — Round 17: the same-PR exemption missed incidents.md
**What was wrong:** "Entries for this PR are not repeats" could only be applied to rejections.md, which carries PR numbers. incidents.md entries carry none, and /feature writes them during the PR, so an unfixed doubt-driven finding would be rated a blocking HIGH repeat.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:103-105
**Caught by:** this review (isolated subagent, round 17)

## 2026-09-27 — PR#130 — Case 2 logged non-blocking fixes into repeat history
**What was wrong:** Case 2 logged every fix the PR body listed, whatever its severity, so a fixed LOW (for example a wrap-width nit) would enter rejections.md and make the same slip in a later PR a blocking HIGH repeat.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:180; .claude/context/rejections.md (this PR's entries)
**Caught by:** code-review pass (code-review:code-review on PR#130)

## 2026-09-27 — PR#130 — Round 19: regressions of LOW fixes were still raised to a blocking HIGH
**What was wrong:** The session's regression check and the HIGH floor covered any fix that came back, including a fixed LOW, so a returning style nit would block APPROVED and enter repeat history. That contradicted case 2 and the CHANGELOG. Now only a regression of a blocking fix is raised.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:128, :131-135
**Caught by:** this review (isolated subagent, round 19)

## 2026-09-27 — PR#130 — Round 25: incidents.md entries had no severity for the regression check
**What was wrong:** The session's regression check compared findings with this PR's incidents.md entries but raised only returning "blocking" fixes, and incidents.md entries carry no severity, so the check could never fire or had to guess. incidents.md records real bugs, so its entries now count as blocking fixes.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:132-135
**Caught by:** this review (isolated subagent, round 25)

## 2026-09-27 — PR#130 — Round 26: PR-body fixes had no severity for the regression check or case 2
**What was wrong:** The regression check and case 2 act only on blocking fixes, but a fix listed in the PR body carries no severity, and nothing told the session how to rate one. Whether a returning fix was raised, or a fix was logged, depended on a guess.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:115-119, :176
**Caught by:** this review (isolated subagent, round 26)

## 2026-09-27 — PR#130 — Older style-only entries still made repeats blocking HIGHs
**What was wrong:** This PR stops logging LOW items, but rejections.md already holds style-only entries from earlier PRs (for example "run-on sentence"). The repeat rule rated any match HIGH with no way to lower it, so a later style slip would still block and be logged again. A repeat of a wording- or style-only entry now keeps its own severity.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:103
**Caught by:** code-review pass (code-review:code-review on PR#130)

## 2026-09-27 — PR#130 — Round 28: the HIGH floor overrode the style-only repeat exception
**What was wrong:** The floors sentence said "a repeat … stays HIGH" with no exception, which contradicted the new rule that a repeat of a wording- or style-only entry keeps its own severity. A session applying the floor could raise a style repeat to a blocking HIGH.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md (severity floors)
**Caught by:** this review (isolated subagent, round 28)

## 2026-09-27 — PR#130 — Regression check ignored this PR's incidents.md entries
**What was wrong:** The session's regression check compared findings only with the PR body and this PR's rejections.md entries. A regression of a fix recorded in an incidents.md entry that this PR added (for example by /feature's doubt-driven review) was never raised to HIGH.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:131
**Caught by:** code-review pass (code-review:code-review on PR#130, after round 24)

## 2026-09-27 — PR#130 — APPROVED unreachable when a gate is NOT VERIFIED
**What was wrong:** APPROVED required "every gate-verification check passes", but a NOT VERIFIED script or an unconfigured gates CI job is never a pass and was not listed as CHANGES REQUESTED either, so the reviewer had to guess. They are now visible notes that do not block on their own.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:178
**Caught by:** code-review pass (code-review:code-review on PR#130, after round 29)

## 2026-09-27 — PR#130 — The isolated reviewer could read this PR's own log entries
**What was wrong:** The subagent read the PR branch's rejections.md and got the PR number, so it could find this PR's round-by-round entries, which retell the implementer's account of the change. The PR's diff carried the same entries. It now gets the base branch's rejections.md and a diff without it, and the session checks that the log only appends.
**Rule violated:** no formal rule, caught before this review
**File:** .claude/skills/review/SKILL.md:95-100
**Caught by:** code-review pass (code-review:code-review on PR#130, after round 31)

## 2026-09-27 — PR#130 — Round 32: the new append-only check had no failure outcome
**What was wrong:** The session's check that rejections.md only appends did not say what a failure meant: it was not a gate-verification check, a subagent finding or a case-1 item, so a PR that edits past log entries could still be APPROVED. A failure is now a failed gate-verification check (CHANGES REQUESTED).
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:125-126
**Caught by:** this review (isolated subagent, round 32)

## 2026-09-27 — PR#130 — Round 33: this PR's incidents.md entries still reached the isolated reviewer
**What was wrong:** Only this PR's rejections.md entries were withheld. Its incidents.md entries, which /feature writes during the PR, still reached the subagent through the diff and the branch copy, which leaked the implementer's account. Both logs are now given as base-branch copies, with a diff that leaves both out.
**Rule violated:** no formal rule, caught in review
**File:** .claude/skills/review/SKILL.md:93-106
**Caught by:** this review (isolated subagent, round 33)
