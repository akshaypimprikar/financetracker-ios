# Category Seeding & AI-Suggested Category Creation — Design Spec

**Date:** 2026-07-26
**Status:** Draft

## Overview

Extends the Foundation Models CSV categorization feature (spec 2026-07-19, PR #62, currently on hold pending this work) with four changes surfaced during manual on-device verification of that PR: (1) seed a starter category taxonomy on first launch so suggestions never start from a completely empty candidate list, (2) let the model propose creating a brand-new category — not just matching an existing one — with a one-tap confirm, (3) visually mark the suggested category inside the chip's `Menu` so accepting it doesn't require remembering the chip's label, and (4) fix `ImportViewModel`'s stale category/account list by refreshing on every `ImportSheet` appearance. Items 2 and 4 are coupled: a category created mid-import must be immediately usable for the rest of that same import session without a relaunch.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Seed trigger | Idempotent: seed only when `categoryRepo.fetchAll()` is empty, checked every app launch — not a one-time "has seeded" flag | No new persisted flag needed. Also self-heals if a user deletes every category — an empty category list is a degraded state worth recovering from, not a state to preserve. |
| Where seeding runs | `CategoryViewModel.seedDefaultsIfNeeded()`, called from `FinanceTrackerTabView`'s existing `.task` right after `categoryVM.load()` | Matches the existing app-initialization pattern exactly — no new lifecycle hook, no new service. |
| Seed list | 11 categories, `.expense`: Coffee & Dining, Groceries, Shopping, Transport, Entertainment, Utilities, Rent & Housing, Healthcare, Subscriptions, Travel; `.income`: Income | Covers the realistic CSV-import case. Deliberately expense-heavy: `TransactionImportActor.save` hardcodes every imported `Transaction.type` to `.debit` today (a pre-existing, out-of-scope limitation), so expense categories are what this flow actually needs. No "Transfer" category — `CategoryType` only has `.income`/`.expense` cases; a transfer-type category doesn't exist as a concept in this model. |
| Suggestion type shape | New wrapper `CategorySuggestionResult` (see Domain Services) rather than adding a plain field directly onto the `@Generable` `CategorySuggestion` struct | `CategorySuggestion`'s `categoryName`/`confidence` are `@Guide`-annotated model output. Mixing a post-hoc-computed field into an `@Generable` struct's stored properties is unverified against the real macro's schema-synthesis behavior — safer to keep `CategorySuggestion` as pure model output and wrap it, matching the same DTO-boundary judgment already applied for `CategoryCandidate` earlier in this feature. |
| Match determination | `FoundationModelsCategorySuggester` computes the match once (already did this internally, previously discarding the result by returning `nil` on a miss) and exposes it via `CategorySuggestionResult.matchedCategoryID: UUID?` | Single source of truth for "does this match an existing category" — the View reads the result instead of re-deriving it via its own string comparison (would duplicate logic already computed once, same category of issue as the `CategoryCandidate` Sendable fix). |
| Empty-candidates behavior | `suggestCategory` no longer returns `nil` just because `candidates.isEmpty` — only `isAvailable` gates whether it's attempted at all | With seed categories, `candidates.isEmpty` is now rare (only after a user deletes every category), but when it happens the model can still propose a brand-new category name from nothing rather than going silent. |
| "Uncategorized" handling | The model's literal `"Uncategorized"` fallback (per the existing `@Guide` description) still means **no suggestion at all** — `suggestCategory` returns `nil`, exactly as before. Never offered as a creatable category. | Preserves the existing fails-safe path for genuinely unmatched payees (verified live: "Unknown Payee" correctly produced no chip). Creating a category literally named "Uncategorized" would be nonsensical. |
| AI-create UX | One tap: chip's `Menu` shows `"Create '<name>'"` when `matchedCategoryID == nil`; tapping it creates the category (default icon `tag.fill`, color `#888888`, type `.expense`) **and** assigns it to that payee's row in the same action | Matches the existing one-tap accept/override interaction exactly — no new sheet, no form. `.expense` is fixed rather than model-inferred, consistent with the seed list's reasoning (imported transactions are always `.debit` today). |
| Menu highlight for matched suggestion | Sparkle icon (same glyph as the chip, opacity from the same confidence-based `Theme.Chips` tokens) prefixed to the matched category's row inside the `Menu` | Reuses existing iconography/tokens exactly — no new design tokens, no `/design` cycle needed. Reverses the 2026-07-19 spec's original call not to distinguish the suggested row, based on live-testing feedback that the omission was real friction. |
| `ImportViewModel` refresh scope | `ImportSheet` calls `viewModel.load()` again in `.onAppear`, in addition to the existing app-launch `.task` call | Fixes the stale-list bug for the whole import flow, not just the AI-create path — covers "added a category in Settings, then opened Import in the same session" too. Scoped to `ImportSheet` only; the same staleness likely exists elsewhere in the app (e.g. `BudgetViewModel`'s category list), but a full app-wide fix is out of scope here — see Future Extension Points. |

## Architecture

```
FinanceTrackerTabView.task
   │ categoryVM.load() → categoryVM.seedDefaultsIfNeeded()  [NEW]
   ▼
CategoryViewModel.seedDefaultsIfNeeded()  [NEW]
   │ if categories.isEmpty: save() each of the 11 defaults, then reload

ImportSheet.onAppear  [NEW]
   │ viewModel.load()  — re-fetches accounts + categories fresh every time the sheet opens
   ▼
ImportViewModel (existing loadSuggestions() / setCategory(), unchanged)
   │ NEW: createAndAssignCategory(named:forPayee:)
   ▼
CategoryRepositoryProtocol.save(_:)  — existing, unchanged

CategorySuggesting.suggestCategory(payee:candidates:) -> CategorySuggestionResult?  [CHANGED return type]
   ▼
FoundationModelsCategorySuggester
   │ unchanged model call; NEW: computes matchedCategoryID after generation,
   │ wraps in CategorySuggestionResult; still returns nil for unavailable/error/"Uncategorized"
   ▼
ImportSheet.categoryChip / .categoryMenu  [CHANGED]
   │ matchedCategoryID != nil → sparkle-highlight that row in the Menu (existing accept flow)
   │ matchedCategoryID == nil → "Create '<name>'" row → createAndAssignCategory(...)
```

Only `CategorySuggesting.swift`, `FoundationModelsCategorySuggester.swift`, `FakeCategorySuggesting` (test fixture), `ImportViewModel.swift`, `ImportSheet.swift`, and `CategoryViewModel.swift` change. No new files beyond the seed-list constant (can live in `CategoryViewModel.swift` alongside `seedDefaultsIfNeeded()` — no new type needed for 11 literal values).

## Data Models

No new or modified `@Model` types. Seeded and AI-created categories are ordinary `Category` instances via the existing `Category(name:icon:colorHex:type:)` initializer — no schema change, no migration.

## Domain Services

`FinanceTracker/Services/CategorySuggesting.swift` — signature change:

```swift
protocol CategorySuggesting: Sendable {
    var isAvailable: Bool { get }

    /// Suggests a category for one payee from the given candidates. Returns nil if
    /// unavailable, if the model errors, or if its raw suggestion is the literal
    /// "Uncategorized" fallback (no plausible match, not even a proposal). Otherwise
    /// always returns a result — matchedCategoryID is nil when the suggested name
    /// doesn't match any candidate, meaning "propose creating this," not "no suggestion."
    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult?
}

/// Domain-level wrapper pairing the model's raw @Generable output with the
/// post-hoc match determination against the caller's actual candidates.
struct CategorySuggestionResult: Sendable {
    let suggestion: CategorySuggestion
    let matchedCategoryID: UUID?
}
```

`CategorySuggestion` itself (the `@Generable` struct) is unchanged — still just `categoryName`/`confidence`.

`FinanceTracker/Services/FoundationModelsCategorySuggester.swift` — behavior change in `suggestCategory`:
- Drop the `!candidates.isEmpty` guard; keep only `guard isAvailable else { return nil }`.
- After a successful generation, check `categoryName.caseInsensitiveCompare("Uncategorized") == .orderedSame` → return `nil` (unchanged fails-safe path).
- Otherwise compute `matchedCategoryID = candidates.first(where: { $0.name.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame })?.id` and return `CategorySuggestionResult(suggestion: suggestion, matchedCategoryID: matchedCategoryID)` — no longer discards a non-match, returns it as a creation proposal instead.
- The matching logic should be extracted into a small `private static func matchedID(for name: String, in candidates: [CategoryCandidate]) -> UUID?` pure function — testable in isolation without live model output, closing part of the coverage gap the 2026-07-19 spec accepted (`FoundationModelsCategorySuggester` itself still can't be unit-tested end-to-end in CI, same hardware limitation as before).

`FinanceTracker/ViewModels/CategoryViewModel.swift` — new method:

```swift
func seedDefaultsIfNeeded() throws {
    guard categories.isEmpty else { return }
    for (name, type) in Self.defaultCategories {
        try categoryRepo.save(Category(name: name, type: type))
    }
    try load()
}

private static let defaultCategories: [(name: String, type: CategoryType)] = [
    ("Coffee & Dining", .expense), ("Groceries", .expense), ("Shopping", .expense),
    ("Transport", .expense), ("Entertainment", .expense), ("Utilities", .expense),
    ("Rent & Housing", .expense), ("Healthcare", .expense), ("Subscriptions", .expense),
    ("Travel", .expense), ("Income", .income),
]
```

`FinanceTracker/ViewModels/ImportViewModel.swift` — new method:

```swift
func createAndAssignCategory(named name: String, forPayee payee: String) throws {
    let category = Category(name: name, type: .expense)
    try categoryRepo.save(category)
    categories.append(category)
    setCategory(categoryID: category.id, forPayee: payee)
}
```

## Navigation

No new screens or sheets. The chip's existing `Menu` gains one conditional row (`"Create '<name>'"`) and, when the suggestion matches an existing category, a sparkle prefix on that category's row. Both are additions to the already-existing `Menu`, not a new presentation.

## Design

*Touches `ImportSheet`'s existing chip/`Menu` component only — no new visual component.*

- `docs/design-system.md`'s "Suggestion Chips" section already covers the chip and its confidence-opacity tokens (`Theme.Chips.confidenceHigh/Medium/Low`, `Theme.Typography.chipLabel`). The Menu-row sparkle highlight reuses these exact tokens — same glyph, same opacity source.
- The `"Create '<name>'"` row is a plain `Button` inside the existing `Menu`, styled by the system (matching how the existing category rows already render with no custom styling).
- **No new tokens, no `/design` cycle required before `/feature`.**

## Future Extension Points

- App-wide fix for the stale-ViewModel-data pattern (a shared reactive category/account store, or a consistent refresh-on-appear applied to every ViewModel that reads categories/accounts) — this spec only fixes `ImportSheet`. `BudgetViewModel` and others likely have the same gap.
- `CategoryType` (income vs. expense) inference for AI-created categories — currently always `.expense`, tied to `TransactionImportActor` hardcoding `.debit` for every imported transaction. Revisit together if CSV import ever supports credits.
- Icon/color inference for AI-created categories — currently fixed defaults (`tag.fill`, `#888888`); could use a curated name→icon heuristic later.
- Confidence-threshold auto-accept (already deferred in the 2026-07-19 spec) — still out of scope.

## Testing Strategy

- **`CategoryViewModelTests`**: `seedDefaultsIfNeededCreatesElevenDefaultsWhenEmpty`, `seedDefaultsIfNeededDoesNothingWhenCategoriesAlreadyExist`.
- **New pure-function coverage**: extracting `matchedID(for:in:)` from `FoundationModelsCategorySuggester` makes the case-insensitive matching logic itself unit-testable without live model output — new test target for this, closing part of the previously-accepted 0%-coverage gap on that file.
- **`FakeCategorySuggesting`**: update to return `CategorySuggestionResult?` (rename `suggestionsByPayee` → `resultsByPayee`); existing `ImportViewModelTests` call sites need the same rename.
- **`ImportViewModelTests`**: new tests for `createAndAssignCategory` — appends to `categories`, calls `setCategory` for the given payee, persists via `categoryRepo`. Regression test that a second payee's chip can immediately reference the newly created category within the same session (proves the coupling with item 4 works).
- **Manual on-device verification required again** before `/release`, same as the 2026-07-19 spec's Task 9 — this time covering: seed categories appear on a fresh install, a "Create '<name>'" flow actually creates and assigns a usable category, and the newly created category is immediately available for a second unique payee in the same import without relaunching. Tooling for this is now established (local `Content-Disposition` download server + `cua-driver` pixel-click driving, per PR #62's verification pass) — should be materially faster this time.
