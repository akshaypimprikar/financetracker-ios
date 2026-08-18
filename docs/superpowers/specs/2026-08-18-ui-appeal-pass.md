# UI Appeal Pass — Design Spec

**Date:** 2026-08-18
**Status:** Draft

## Overview

A targeted round of UI fixes and appeal improvements identified during a HIG-alignment review of the current app (screenshots + code audit, both empty-state and demo-seeded). Scope: fix the Accounts tab's missing empty state, fix a copy bug in account type display, add a spending-by-category chart to the Dashboard, extend category-based coloring to budget progress bars, and wire `DashboardView`'s hero cards up to the `Theme.Glass` material tokens added in PR #95. No new screens, models, or services — this is view/viewmodel-layer work that reuses existing tokens and mechanisms wherever precedent exists.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Accounts empty state | `ContentUnavailableView`, same component pattern already used in Transactions/Budgets | Consistency with the documented Empty State pattern in `design-system.md`; no new component |
| "Creditcard" copy fix | New `AccountType.displayName` computed property, replacing `.rawValue.capitalized` at both call sites | Centralizes the fix at the model layer next to the existing `isLiability` computed property; both `AccountRow` and `AccountDetailView` consume the same source instead of duplicating a switch |
| Dashboard category chart | Inline aggregation in `DashboardViewModel.load()`, `BarMark` chart reusing `Theme.Charts.spendingBar` (uniform color, not per-category) | Matches the existing inline-aggregation precedent (`spendingThisMonth` is already a plain filter+reduce in the ViewModel, not a Domain Service) — a group-and-sum is not complex enough to justify a new service. Uniform bar color keeps it visually consistent with `BudgetDetailView`'s existing single-hue spending chart rather than introducing a second, conflicting color convention for "spending" visualizations |
| Category-colored progress bars | `Color(hex: category.colorHex)` applied to `BudgetProgressCard` (Dashboard), `BudgetListView`, and `BudgetDetailView` — confirmed in-scope for all three, not Dashboard-only | Reuses the exact mechanism `AccountRow` already uses for `account.colorHex`; user confirmed "everywhere" scope over chat rather than Dashboard-only |
| Glass card adoption | `DashboardView`'s `netWorthCard`/`spendingCard` rewritten to consume `Theme.Glass.cardMaterial`/`.netWorthTint`/`.spendingTint`/shadow tokens per the documented component pattern | Tokens already approved and merged via PR #95 (design/glass-cards); this spec's job is wiring the one view that consumes them |
| Legacy flat-tint tokens | `Theme.Colors.netWorthCardBackground`/`spendingCardBackground` removed from `Colors.swift` and their `docs/design-system.md` entries, once `DashboardView` no longer references them | They become genuinely dead code the moment this lands — `DashboardView` was their only consumer (confirmed by grep before PR #95 was opened) |

## Architecture

Pure View/ViewModel/Model layer work — no new SwiftData models, no new Domain Services, no new Repository protocols.

- **Models:** `Account.swift` — add `AccountType.displayName`
- **ViewModels:** `DashboardViewModel.swift` — add category-spending aggregation to `load()`
- **Views:** `AccountListView.swift` (empty state), `AccountRow` (same file) + `AccountDetailView.swift` (both consume `displayName`), `DashboardView.swift` (chart + Glass cards), `BudgetListView.swift` + `BudgetDetailView.swift` (category-colored progress tint)
- **Theme:** `Colors.swift` (remove 2 now-dead tokens), `docs/design-system.md` (remove their entries, update Card section)

## Data Models

`FinanceTracker/Models/Account.swift` — add alongside the existing `isLiability`:

```swift
enum AccountType: String, Codable, CaseIterable {
    case checking, savings, creditCard, cash, investment

    var isLiability: Bool { self == .creditCard }

    var displayName: String {
        switch self {
        case .checking:   return "Checking"
        case .savings:    return "Savings"
        case .creditCard: return "Credit Card"
        case .cash:       return "Cash"
        case .investment: return "Investment"
        }
    }
}
```

No `@Model` changes — `Account` itself is untouched.

## Domain Services

None new, none modified.

## Navigation

No new screens, sheets, or navigation changes.

## Design

*All items reuse existing tokens — no new `Theme/` category is introduced, so `/design` does not need to run again before `/feature`.*

1. **Accounts empty state** — `ContentUnavailableView("No Accounts Yet", systemImage: "building.columns", description: Text("Tap + to add your first account."))`, shown when `viewModel.accounts` is empty. Matches the documented Empty State pattern exactly (same shape as Transactions'/Budgets' existing empty states).
2. **"Credit Card" copy fix** — no visual component; `AccountRow` and `AccountDetailView`'s Type row switch from `account.type.rawValue.capitalized` to `account.type.displayName`.
3. **Dashboard category spending chart** — new `Chart` section in `DashboardView`, one `BarMark` per category with nonzero spend this month, `.foregroundStyle(Theme.Charts.spendingBar)`, `.frame(minHeight: Theme.Charts.minHeight)`, `.padding(.horizontal, Theme.Spacing.cardPadding)` — identical composition to `BudgetDetailView`'s existing spending chart, just a different grouping axis (category instead of month). Hidden entirely when there's no spend this month, same conditional-section pattern already used for Budgets/Recent Transactions on this screen.
4. **Category-colored progress bars** — `ProgressView.tint(...)` in `BudgetProgressCard` (Dashboard), `BudgetListView`, and `BudgetDetailView` changes from `progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive` to `progress.isOverBudget ? Theme.Colors.destructive : (Color(hex: budget.category.colorHex) ?? Theme.Colors.primaryInteractive)` — over-budget red always wins; the fallback to `primaryInteractive` mirrors `AccountRow`'s existing `Color(hex:) ?? Theme.Colors.primaryInteractive` null-coalescing pattern for a malformed hex string.
5. **Glass cards** — `DashboardView.netWorthCard`/`.spendingCard` rewritten per the "Glass Cards" component pattern already documented in `design-system.md` (added by PR #95):
   ```swift
   .background(
       RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge)
           .fill(Theme.Glass.cardMaterial)
           .overlay(
               RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge)
                   .fill(Theme.Glass.netWorthTint) // .spendingTint for the spending card
           )
   )
   .shadow(color: Theme.Glass.cardShadowColor, radius: Theme.Glass.cardShadowRadius, y: Theme.Glass.cardShadowY)
   ```
   Replaces the current flat `.background(Theme.Colors.netWorthCardBackground)` / `.clipShape(...)`. `Theme.Typography.amountDisplay`'s `.rounded` revision (already merged in PR #95) applies automatically — no DashboardView change needed for that part, it's already wired to the token.

**Blocking dependency:** PR #95 (`design/glass-cards`, adds `Theme.Glass` + revises `amountDisplay`) must merge to `develop` before item 5 (and the legacy-token removal) can build. Items 1–4 have no dependency on it and can proceed independently. `/plan` should sequence item 5 last, or `/feature` should branch off `design/glass-cards` instead of `develop` if #95 is still unmerged when implementation starts, rebasing onto `develop` once it lands.

## Future Extension Points

- Dark Mode visual QA — not performed during this spec's research (screenshots were light-mode only); `Theme.Glass.cardMaterial` adapts automatically, but the tint gradients and category hex colors haven't been visually verified in Dark Mode. Flagged for manual check during `/gates` or before merge, not blocking the spec.
- Extending the Glass Card treatment beyond Dashboard (e.g. Accounts' Net Worth summary row) — deferred, out of scope for this pass.
- Category-colored icons on transaction rows (beyond the account-colored icons `AccountRow` already has) — deferred, not part of the approved scope.

## Testing Strategy

- **Unit (`Testing` framework):**
  - `AccountType.displayName` — exhaustive case coverage (one `@Test` per case, or a parameterized `@Test(arguments:)` over `AccountType.allCases`) verifying no case falls through to a raw-value-derived string.
  - `DashboardViewModel` category-spending aggregation — new test(s) in `DashboardViewModelTests.swift` alongside existing `spendingThisMonthSumsDebitsOnly`/`loadComputesNetWorth`: groups debit transactions by category correctly, excludes credit/transfer transactions, respects the current-month date boundary, empty when no categorized spend exists this month.
- **Integration:** none needed — no repository or SwiftData changes.
- **UI (`XCTest`):** new Accounts empty-state UI test mirroring the existing Transactions/Budgets empty-state coverage pattern (likely alongside `UITestAccountFlowTests` or `UITestSmokeTests`) — verifies "No Accounts Yet" renders when the account list is empty.
- **Theme tokens:** no new tokens introduced by this spec, so no new `ThemeTokenTests` entries needed (PR #95 already covers `Theme.Glass` and the `amountDisplay` revision).
- **Manual/visual:** build + run with `--seedscreenshots`, screenshot Dashboard/Accounts/Budgets in both light and Dark Mode before merge, per the Dark Mode gap noted above.
