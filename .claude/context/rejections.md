# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

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
