# Correctness Review Post-Mortem

**Date:** 2026-05-18  
**Scope:** Full four-layer review (Services → Repositories → ViewModels → Views)  
**PRs:** [#27 fix/correctness](https://github.com/akshaypimprikar/financetracker-ios/pull/27), [#28 fix/ux](https://github.com/akshaypimprikar/financetracker-ios/pull/28)

---

## What Was Found

### High Severity

| # | Location | Issue |
|---|----------|-------|
| 1 | `BalanceService.runningBalance` | Anchor point and first post-transaction point share the same `Date`, producing a duplicate chart ID and causing SwiftUI Charts to silently drop a data point |
| 2 | `ImportSheet.fileImporter` | `stopAccessingSecurityScopedResource()` not called when `String(contentsOf:)` throws — OS-level resource leak that can prevent future file access in the same session |
| 3 | `BudgetCalculationService.progress` | Duplicated the debit-filter/reduce logic from `totalSpent()`, meaning a future fix to one copy would silently diverge from the other |
| 4 | `BudgetViewModel.add` | No duplicate-budget guard — a second call with the same category+month created a second `Budget` row, causing the UI to display two progress bars for one category |
| 5 | `AccountDetailView`, `BudgetDetailView` | Charts used `id: \.date` / `id: \.month` (non-stable, non-unique `Date`) — fragile; any two points landing on the same date cause SwiftUI Charts to merge or drop marks |

### Medium Severity

| # | Location | Issue |
|---|----------|-------|
| 6 | `BudgetViewModel.load()`, `add()` | Force-unwrap `!` on `Calendar.date(from:)` and `Calendar.date(byAdding:)` — will crash on any locale where Calendar returns nil |
| 7 | `AccountDetailView.body`, `BudgetDetailView.body` | `viewModel.transactions(for:)`, `runningBalanceData(for:)`, and `monthlySpendingHistory(for:)` called directly in `body` — triggers N repository queries per render frame |
| 8 | `AccountViewModel.runningBalanceData` | Converted `Decimal→Double` inside the ViewModel, leaking chart-rendering concerns into the domain layer |
| 9 | `BudgetDetailView` | Delete button called `try? viewModel.delete(budget)` with no `dismiss()` — user left on a screen for a deleted object |
| 10 | `AddTransactionSheet` | `canAdd` did not check `selectedToAccount != nil` for transfers — a transfer with no destination could be saved |
| 11 | `BudgetListView`, `BudgetDetailView`, `ImportSheet` | Hardcoded `"USD"` in every currency formatter — all non-USD users saw wrong currency symbol |

### Low Severity

| # | Location | Issue |
|---|----------|-------|
| 12 | `BudgetCalculationService` | `MonthlySpendingPoint` declared but never consumed — dead code with no test coverage |
| 13 | `TransactionListView` | No empty state — blank list when no transactions match filter or none exist yet |
| 14 | `BalanceServiceTests`, `BudgetCalculationServiceTests` | Each file defined a private `makeContainer()` duplicating the shared `TestHelpers` helper — test code divergence risk |
| 15 | Various | All mutations behind `try?` with no user-visible error feedback |

---

## Why These Issues Occurred

### 1. Layer-boundary drift under feature pressure

The charts feature (PR #26) was implemented quickly. The correct pattern — stable UUIDs as chart IDs, Decimal kept at the service layer, Double conversion only at the render site — was documented in the architecture but not enforced. Under time pressure to ship the visual feature, the easiest path (anonymous tuples, `id: \.date`, Decimal→Double in the VM) was taken. There was no layer-boundary lint rule to catch it.

**Pattern:** When a feature spans multiple layers for the first time (charts require data from services, through VMs, to views), the boundary rules are most at risk of being violated precisely at integration points.

### 2. Missing negative-path tests for new flows

The duplicate-budget bug (#4) persisted because `add()` was only tested for the happy path. No test exercised calling `add()` twice with the same category. The guard was not written because the failure mode was not imagined.

**Pattern:** CRUD operations on shared entities (budgets, categories) need tests that call the same operation twice — the second call is often the first to reveal missing deduplication logic.

### 3. Security-scoped resources not treated as explicit acquire/release pairs

The `ImportSheet` file-access bug (#2) resulted from treating `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` like a simple flag rather than a paired acquire/release that must be released even on error paths. The pattern `guard start(), let data = try? ...; stop()` looks correct but drops the `stop()` call when `try?` returns nil.

**Pattern:** Any acquire/release pair (`open`/`close`, `lock`/`unlock`, `start`/`stop`) must use `defer` immediately after the acquire. Not after the dependent work succeeds.

### 4. Duplicate logic without a shared source of truth

`BudgetCalculationService.progress()` and `totalSpent()` both contained the same debit-filter/reduce. This happened because `progress()` was written first, `totalSpent()` was added later as a public utility, and the original implementation was not updated to delegate. Each function had its own tests, so the divergence was not visible.

**Pattern:** When a new public function extracts logic that already exists inline elsewhere, the original inline code should be replaced with a call to the new function in the same commit — not left to rot.

### 5. Force-unwraps used as "this can't fail" shortcuts

`Calendar.date(from:)` and `Calendar.date(byAdding:)` return optionals for good reason — they can fail on edge locales. The force-unwraps were written with implicit confidence that "Calendar never fails for normal dates." That confidence is usually correct but is untestable and fragile.

**Pattern:** Force-unwrapping stdlib optionals that return `nil` on edge input is a category of latent bug that is invisible in testing but can crash in the wild for users with non-default locale or calendar settings.

### 6. View body computing derived data on every render

SwiftUI re-evaluates `body` frequently — on any `@Observable` property change, on focus change, on system events. When `body` calls functions that query a repository, the app executes database reads on every frame. This was not caught in code review because it looks correct: the data is always fresh. The performance cost is only visible under profiling.

**Pattern:** Any repository call or N-item computation that does not belong to a reactive `@Observable` property must be moved to `onAppear` (for one-time load) or into the ViewModel's `load()` path (for reactive updates).

---

## How to Prevent These Issues Going Forward

### Rule 1: Stable, typed IDs for all collection data passed to SwiftUI

Any struct passed to `ForEach`, `Chart`, or similar must be `Identifiable` with a `UUID id`. Anonymous tuples and `Date` are not valid IDs. Add this to the spec template and review checklist.

> **Checklist item:** "Does every array passed to `ForEach`/`Chart` use `id: \.id` with a UUID?"

### Rule 2: `defer` is mandatory for any security-scoped resource

The moment `startAccessingSecurityScopedResource()` returns `true`, the very next line must be `defer { url.stopAccessingSecurityScopedResource() }`. No exceptions. This is a candidate for a code-review bot rule.

> **Checklist item:** "Does every `startAccessingSecurityScopedResource()` call have an immediate `defer` for `stop`?"

### Rule 3: When extracting shared logic, delete the original inline copy in the same PR

If `totalSpent()` is extracted from `progress()`, `progress()` must call `totalSpent()` in the same commit. Never leave both alive.

> **Checklist item:** "Did this PR introduce a new utility function? If so, does every prior call site now use it?"

### Rule 4: No force-unwrap on stdlib optionals — use `guard let` with a meaningful fallback

`Calendar`, `DateFormatter`, `NumberFormatter` all return optionals on edge cases. Use `guard let ... else { return }` or `?? fallback`. Reserve `!` only for values that are provably non-nil by construction (e.g., a literal string passed to a regex).

> **Checklist item:** "Does this PR introduce any `!` unwrap on a stdlib optional-returning call?"

### Rule 5: Repository calls belong in `onAppear` or `load()`, never in `body`

Write this rule in CLAUDE.md. Views must only read from `@Observable` stored properties. If a function queries a repository, it must be called in `onAppear` or from the ViewModel's `load()` path, with results stored in `@State` or `@Observable` properties.

> **CLAUDE.md addition:** "Views read stored `@Observable` properties only — never call repository or service methods from `body`."

### Rule 6: Every mutation has a second-call test

For any function that writes to the repository, write a test that calls it twice. The second call must either succeed (idempotent) or throw a documented error. If neither behavior is tested, the duplicate case is untested.

> **Checklist item:** "For every `save`/`add`/`create` function, is there a test that calls it twice?"

### Rule 7: Currency is locale-derived, never hardcoded

Use `Locale.current.currency?.identifier ?? "USD"` as the default. For account-specific amounts, use `account.currency`. No view should contain the string literal `"USD"`.

> **Checklist item:** "Does this PR contain the string literal `\"USD\"`? If so, replace with a locale or account currency."

### Rule 8: Add security resource handling and paired acquire/release to the `/review` agent checklist

The `/review` agent should scan for:
- `startAccessingSecurityScopedResource` without an immediately following `defer`
- Any `open`/`close`, `lock`/`unlock` pattern where the release is not in a `defer`

---

## Process Changes

| Change | Owner | When |
|--------|-------|------|
| Add rules 1–7 above as checklist items in `/review` agent prompt | `/spec` next feature | Before next feature PR |
| Add rule 5 (no repo calls in body) to CLAUDE.md | Now | Done |
| Add `defer` requirement to `/review` security section | Next `/review` update | Before next feature PR |
| Add second-call test to standard test template in `/test` agent | Next test run | Before next feature PR |

---

## What Worked Well

- **Layered architecture made the review tractable.** Because Domain Services have zero SwiftData imports, every service bug was unit-testable without a simulator. The four-layer split made it easy to categorize which issues were data-correctness vs. rendering/UX.
- **`#expect` / Swift Testing made failure modes clear.** The `#expect(throws:)` API allowed precise duplicate-budget testing without boilerplate.
- **Splitting into two PRs was the right call.** The correctness fixes (Services/Repositories) are mergeable independently of the UX fixes (ViewModels/Views), and each PR has a focused diff that is easier to review.
