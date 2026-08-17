# Re-render Cleanup Pass — Design Spec

**Date:** 2026-08-16
**Status:** Draft

## Overview

A batch of 5 View/ViewModel-layer performance fixes, all sourced from the same Instruments profiling session (2026-06-04) recorded in `Project Actions.md`'s backlog. The original card described 8 fixes; this spec re-verifies every claim against the current codebase before scoping work, since the codebase has moved since that profiling session. Two of the original 8 items turned out to already be fixed (`BudgetViewModel.unbudgetedCategories` is already a cached stored property, not recomputed per access) and one follow-on item (`AddBudgetSheet`'s "3 separate reads") turns out not to be a real cost given that finding. A third item (`TransactionListView`'s redundant `filteredTransactions` access) is resolved automatically once the ViewModel-side memoization fix lands, with no separate View-side change needed. Net scope: 5 fixes, one PR.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Scope | 5 confirmed fixes, not the original 8 | Direct code reading (not just the backlog card's description) found `unbudgetedCategories` already cached, and the "3 separate reads" follow-on item has no cost once that's true. Re-verified against `AddBudgetSheet.swift` and `BudgetViewModel.swift` directly. |
| `TransactionViewModel.filteredTransactions` memoization | Stored cache invalidated via `didSet` on the three inputs (`transactions`, `searchText`, `selectedAccount`) | Simpler than a separate dirty-flag property — no risk of the flag and the cache drifting out of sync, since invalidation is structurally tied to the only three places the cache can go stale. |
| `BudgetListView`'s `.onChange(selectedMonth)` | Debounce via a cancelled-and-restarted `Task` with a 150ms delay before calling `viewModel.load()` | `load()` is synchronous (3 repo fetches + O(N×M) progress calc); a real debounce requires an actual delay, not just cancellation, since there's no async work to cancel mid-flight otherwise. 150ms matches typical UI debounce windows. |
| `AccountListView`'s duplicate `netWorth()` calls | Compute once into a local `let` at the top of `body`, reuse for both the value display and the color comparison | View-only fix, no `AccountViewModel` API change — `netWorth()`'s existing signature and behavior are unchanged, so `AccountViewModelTests` needs no changes. |
| `BudgetDetailView` / `TransactionDetailView` `@Bindable` → plain `let` | Drop `@Bindable` where no `$viewModel.x` binding exists | Correction to the original card's framing: `@Bindable` vs. plain `let` does **not** change `@Observable`'s tracking granularity (that's per-property regardless of wrapper) — this is a correctness/clarity cleanup (removes an unused two-way-binding capability), not a re-render fix. Framed accurately in this spec so `/plan` doesn't inherit the original card's incorrect mechanism. |

## Architecture

Views + ViewModels layer only. No Domain Service, Repository Protocol, or `@Model` changes. Every fix is contained within existing View or ViewModel files — no new files.

## Data Models

None — no `@Model` changes.

## Domain Services

None — no Domain Service changes. All 5 fixes stay above the repository boundary.

## Navigation

None — no new screens, sheets, or navigation changes.

## Design

N/A — no new visual components, no `Theme` token changes. Purely internal performance/clarity work with no visible UI difference.

## Future Extension Points

- **SE-0506 Advanced Observation Tracking** (separate backlog item, `#p1`) — targets `BudgetSummaryViewModel` with `withObservationTracking(options:)` to narrow observation to exactly the properties each view reads. Distinct from this pass: that's a new observation *technique* applied to one ViewModel; this pass is mechanical caching/dedup fixes across several existing Views/ViewModels. Sequenced separately, own spec.

## Testing Strategy

- **`TransactionViewModel.filteredTransactions` memoization** — unit test asserting identical output before/after the change for the same inputs (filtering + sorting semantics unchanged), plus three tests confirming the cache invalidates correctly when `transactions`, `searchText`, and `selectedAccount` each change independently.
- **`AccountListView` duplicate `netWorth()` call** — View-only fix; per CLAUDE.md, Views contain no business logic and aren't unit tested directly. `AccountViewModelTests` already covers `netWorth()` correctness and needs no changes since the ViewModel's public API/behavior is unchanged. Verified manually in-app during `/feature`'s `verify` step (net worth displays correctly, color still reflects sign).
- **`BudgetListView` debounce** — timing-based View behavior is not meaningfully unit-testable. `BudgetViewModelTests` already covers `load()` correctness and needs no changes. Verified manually: rapid month changes in the picker don't produce stale or dropped budget data once the debounce settles.
- **`@Bindable` → `let` changes (`BudgetDetailView`, `TransactionDetailView`)** — no behavior change. Verified by successful compilation and the full existing test suite passing with zero regressions (`/gates` Gate 2).
