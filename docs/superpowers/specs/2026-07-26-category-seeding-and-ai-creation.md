# Category Seeding & AI-Suggested Category Creation — Design Spec

**Date:** 2026-07-26
**Status:** Draft

## Overview

Extends the Foundation Models CSV categorization feature (spec 2026-07-19, PR #62, currently on hold pending this work) with changes surfaced during manual on-device verification of that PR and subsequent design discussion. This spec went through one real pivot worth recording: it originally proposed seeding a static default category taxonomy on first launch. That was rejected in favor of making category population emerge from AI suggestions during CSV import (or manual add), on the reasoning that a pre-populated list is an addon patching a cold-start problem, whereas AI-driven creation makes the Foundation Models feature the actual mechanism by which categories come to exist — more true to what this feature is for.

The final scope:
1. Let the model propose creating a brand-new category — not just matching an existing one — with a one-tap confirm, when nothing in the user's current list plausibly fits.
2. Visually mark the matched category inside the chip's `Menu` so accepting a suggestion doesn't require remembering the chip's label.
3. Fix `ImportViewModel`'s stale category/account list by refreshing on every `ImportSheet` appearance.
4. Device-aware empty-state handling in `AddBudgetSheet` (the one screen that's genuinely blocked by zero categories — see the correction under Decisions below).

No seeding. Items 1 and 3 are coupled: a category created mid-import must be immediately usable for the rest of that same import session without a relaunch.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Seeding — rejected | No default category taxonomy is created anywhere, ever, automatically | Rejected in favor of the AI-first framing above. The two features that seeding would have unblocked turned out to be one feature, not two — see the empty-state correction below — and that one screen gets targeted handling instead of a blanket pre-populated list every user has to live with or clean up. |
| Which screens are actually affected by zero categories | Audited via a full search of `Category` usage app-wide. **`AddTransactionSheet` is not blocked** — its category `Picker` already has an explicit `"Uncategorized"` option and `canAdd` never requires a category, so it works identically today whether or not any categories exist. **`AddBudgetSheet` is genuinely blocked** — `canAdd` requires `selectedCategoryID != nil`, and a budget conceptually can't target "Uncategorized." | This corrects an earlier (incorrect) assumption made during spec discussion that both screens were blocked. Only `AddBudgetSheet` needs new empty-state handling. |
| `AddBudgetSheet` empty-state, device-aware | On an Apple Intelligence-eligible device: empty state points at CSV import only ("Import a CSV to get AI-suggested categories, then come back to set a budget") — no manual-add path shown here, reinforcing that category creation is AI-driven on capable hardware. On an ineligible device: empty state offers a manual "Add Category" action (presents the existing `AddCategorySheet` inline), preserving today's actual behavior for hardware that can't run the AI path at all. | Matches the explicit choice: push the flagship AI-driven path on capable hardware, don't regress ineligible-hardware users who have no other route to a category. |
| Suggestion type shape | `CategorySuggestionResult` wrapper (see Domain Services) rather than adding a plain field directly onto the `@Generable` `CategorySuggestion` struct | `CategorySuggestion`'s `categoryName`/`confidence` are `@Guide`-annotated model output. Mixing a post-hoc-computed field into an `@Generable` struct's stored properties is unverified against the real macro's schema-synthesis behavior — safer to keep `CategorySuggestion` as pure model output and wrap it, matching the same DTO-boundary judgment already applied for `CategoryCandidate` earlier in this feature. |
| Match determination | `FoundationModelsCategorySuggester` computes the match once (already did this internally, previously discarding the result by returning `nil` on a miss) and exposes it via `CategorySuggestionResult.matchedCategoryID: UUID?` | Single source of truth for "does this match an existing category" — the View reads the result instead of re-deriving it via its own string comparison. |
| Empty-candidates behavior | `suggestCategory` no longer returns `nil` just because `candidates.isEmpty` — only `isAvailable` gates whether it's attempted at all | Without seeding, a brand-new user's first CSV import routinely has zero existing categories. The model must still be able to propose one from nothing rather than going silent — this is now the *primary* path, not a rare edge case. |
| "Uncategorized" handling | The model's literal `"Uncategorized"` fallback (per the existing `@Guide` description) still means **no suggestion at all** — `suggestCategory` returns `nil`, exactly as before. Never offered as a creatable category. | Preserves the existing fails-safe path for genuinely unmatched payees (verified live: "Unknown Payee" correctly produced no chip). Creating a category literally named "Uncategorized" would be nonsensical. |
| AI-create UX | One tap: chip's `Menu` shows `"Create '<name>'"` when `matchedCategoryID == nil`; tapping it creates the category (default icon `tag.fill`, color `#888888`, type `.expense`) **and** assigns it to that payee's row in the same action | Matches the existing one-tap accept/override interaction exactly — no new sheet, no form. `.expense` is fixed rather than model-inferred: `TransactionImportActor` hardcodes every imported `Transaction.type` to `.debit` today (a pre-existing, out-of-scope limitation), so `.expense` is the only value actually consistent with what CSV import produces. |
| Duplicate-category guard | `createAndAssignCategory` checks for an existing category with a case-insensitive matching name **before** creating; reuses it if found, only inserts if truly absent. Also trims and rejects an empty/whitespace-only name. | Without a seed baseline, this is no longer a rare edge case: `loadSuggestions()` computes suggestions for every unique payee in one batch, before the user has tapped anything. If a CSV has both "Starbucks" and "Peet's Coffee" and neither matches an existing category, both independently propose creating "Coffee & Dining" — accepting both without this guard would create two separate categories with the same name. |
| Rematch after create | After any category is created via `createAndAssignCategory`, re-run the (cheap, pure, no-model-call) match check against every other still-unconfirmed cached suggestion, updating `matchedCategoryID` where a name now matches. | Without this, a second payee's chip/menu would keep cosmetically saying `"Create 'Coffee & Dining'"` even after the first payee's tap already created that exact category — the duplicate-guard above would still prevent a second insert at tap time, but the label would be misleading until then. This keeps every pending suggestion's label accurate as categories come into existence mid-session. |
| Menu highlight for matched suggestion | Sparkle icon (same glyph as the chip, opacity from the same confidence-based `Theme.Chips` tokens) prefixed to the matched category's row inside the `Menu` | Reuses existing iconography/tokens exactly — no new design tokens, no `/design` cycle needed. Reverses the 2026-07-19 spec's original call not to distinguish the suggested row, based on live-testing feedback that the omission was real friction. |
| `ImportViewModel` refresh scope | `ImportSheet` calls `viewModel.load()` again in `.onAppear`, in addition to the existing app-launch `.task` call | Fixes the stale-list bug for the whole import flow — covers "added a category in Settings, then opened Import in the same session," and is a prerequisite for the AI-create flow to make sense at all without seeding. Scoped to `ImportSheet` only; the same staleness likely exists elsewhere (e.g. `BudgetViewModel`'s category list) — see Future Extension Points. |
| Device-awareness plumbing cost | `AddBudgetSheet`'s `BudgetViewModel` gains a new dependency on `CategorySuggesting.isAvailable` (or an equivalent boolean), which it doesn't have today — that's only wired into `ImportViewModel` currently. This means threading a new constructor parameter through `BudgetViewModel`, `ContentView`'s DI wiring, and every existing `BudgetViewModelTests` call site. | Called out explicitly because it's a real, non-trivial cost of the device-aware empty-state decision — the same shape of change as adding `categoryRepo` to `ImportViewModel` earlier in this feature, applied to a second ViewModel. `/plan` should size this as its own task. |

## Architecture

```
ImportSheet.onAppear  [NEW]
   │ viewModel.load()  — re-fetches accounts + categories fresh every time the sheet opens
   ▼
ImportViewModel (existing loadSuggestions() / setCategory(), unchanged)
   │ NEW: createAndAssignCategory(named:forPayee:)
   │   1. trim + reject empty name
   │   2. reuse existing category by case-insensitive name match, else create
   │   3. setCategory(...) to assign it to this payee's rows
   │   4. rematch all other pending suggestions against the updated category list
   ▼
CategoryRepositoryProtocol.save(_:)  — existing, unchanged

CategorySuggesting.suggestCategory(payee:candidates:) -> CategorySuggestionResult?  [CHANGED return type]
   ▼
FoundationModelsCategorySuggester
   │ unchanged model call; NEW: computes matchedCategoryID after generation,
   │ wraps in CategorySuggestionResult; still returns nil for unavailable/error/"Uncategorized";
   │ candidates.isEmpty no longer forces nil — model can propose from nothing
   ▼
ImportSheet.categoryChip / .categoryMenu  [CHANGED]
   │ matchedCategoryID != nil → sparkle-highlight that row in the Menu (existing accept flow)
   │ matchedCategoryID == nil → "Create '<name>'" row → createAndAssignCategory(...)

BudgetViewModel  [NEW dependency: CategorySuggesting.isAvailable]
   ▼
AddBudgetSheet  [NEW]
   │ unbudgetedCategories.isEmpty && isAvailable        → "Import a CSV to get AI-suggested categories"
   │ unbudgetedCategories.isEmpty && !isAvailable       → "Add Category" button → AddCategorySheet (existing, inline)
```

Files touched: `CategorySuggesting.swift`, `FoundationModelsCategorySuggester.swift`, `FakeCategorySuggesting` (test fixture), `ImportViewModel.swift`, `ImportSheet.swift`, `BudgetViewModel.swift`, `AddBudgetSheet.swift`, `ContentView.swift` (DI wiring for `BudgetViewModel`'s new dependency). No new files, no new `@Model` types.

## Data Models

No new or modified `@Model` types. AI-created categories are ordinary `Category` instances via the existing `Category(name:icon:colorHex:type:)` initializer — no schema change, no migration.

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
- Drop the `!candidates.isEmpty` guard; keep only `guard isAvailable else { return nil }`. The prompt's "Existing categories: ..." line is simply empty when `candidates` is empty — a valid prompt that lets the model propose freely.
- After a successful generation, check `categoryName.caseInsensitiveCompare("Uncategorized") == .orderedSame` → return `nil` (unchanged fails-safe path).
- Otherwise compute `matchedCategoryID = Self.matchedID(for: suggestion.categoryName, in: candidates)` and return `CategorySuggestionResult(suggestion: suggestion, matchedCategoryID: matchedCategoryID)`.
- Extract the matching logic into `private static func matchedID(for name: String, in candidates: [CategoryCandidate]) -> UUID? { candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id }` — pure, testable in isolation without live model output, closing part of the coverage gap the 2026-07-19 spec accepted.

`FinanceTracker/ViewModels/ImportViewModel.swift` — new method:

```swift
func createAndAssignCategory(named name: String, forPayee payee: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let category: Category
    if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        category = existing
    } else {
        category = Category(name: trimmed, type: .expense)
        try categoryRepo.save(category)
        categories.append(category)
    }
    setCategory(categoryID: category.id, forPayee: payee)
    rematchPendingSuggestions()
}

private func rematchPendingSuggestions() {
    for (payee, result) in suggestions where result.matchedCategoryID == nil {
        guard let match = categories.first(where: {
            $0.name.caseInsensitiveCompare(result.suggestion.categoryName) == .orderedSame
        }) else { continue }
        suggestions[payee] = CategorySuggestionResult(suggestion: result.suggestion, matchedCategoryID: match.id)
    }
}
```

`FinanceTracker/ViewModels/BudgetViewModel.swift` — new dependency and exposed property:

```swift
private let categorySuggester: any CategorySuggesting   // new init param, defaulted like ImportViewModel's

var suggestionsAvailable: Bool { categorySuggester.isAvailable }
```

## Navigation

No new screens. `AddBudgetSheet`'s empty-state branch (Apple Intelligence unavailable) presents the existing `AddCategorySheet` inline via `.sheet` — reusing the Settings flow, not a new screen. The chip's existing `Menu` gains one conditional row (`"Create '<name>'"`) and a sparkle prefix on a matched row — both additions to the already-existing `Menu`.

## Design

*Touches `ImportSheet`'s existing chip/`Menu` component and `AddBudgetSheet`'s empty state — no new visual component.*

- `docs/design-system.md`'s "Suggestion Chips" section already covers the chip and its confidence-opacity tokens (`Theme.Chips.confidenceHigh/Medium/Low`, `Theme.Typography.chipLabel`). The Menu-row sparkle highlight reuses these exact tokens.
- The `"Create '<name>'"` row is a plain `Button` inside the existing `Menu`, styled by the system.
- `AddBudgetSheet`'s empty-state message is plain text (`ContentUnavailableView` or similar, matching the existing Empty State pattern in `docs/design-system.md`) plus, on the ineligible-device branch, a standard button presenting `AddCategorySheet`.
- **No new tokens, no `/design` cycle required before `/feature`.**

## Future Extension Points

- App-wide fix for the stale-ViewModel-data pattern (a shared reactive category/account store, or a consistent refresh-on-appear applied to every ViewModel that reads categories/accounts) — this spec only fixes `ImportSheet`.
- `CategoryType` (income vs. expense) inference for AI-created categories — currently always `.expense`, tied to `TransactionImportActor` hardcoding `.debit`. Revisit together if CSV import ever supports credits.
- Icon/color inference for AI-created categories — currently fixed defaults (`tag.fill`, `#888888`); could use a curated name→icon heuristic later.
- Category-name consistency over time: each `suggestCategory` call uses a fresh `LanguageModelSession` with no memory of how other payees in the same (or a later) import were categorized. This is a **reasoned expectation, not something tested**: repeated imports could plausibly fragment into near-duplicate categories the exact case-insensitive match can't catch (e.g. "Coffee & Dining" vs. "Dining & Coffee"). No mitigation planned now beyond the exact-match dedup already in scope; revisit if real usage shows fragmentation.
- Confidence-threshold auto-accept (already deferred in the 2026-07-19 spec) — still out of scope.

## Testing Strategy

- **New pure-function coverage**: `matchedID(for:in:)` extracted from `FoundationModelsCategorySuggester` is unit-testable in isolation without live model output — closes part of the previously-accepted 0%-coverage gap on that file.
- **`FakeCategorySuggesting`**: update to return `CategorySuggestionResult?` (rename `suggestionsByPayee` → `resultsByPayee`); existing `ImportViewModelTests` call sites need the same rename.
- **`ImportViewModelTests`**: new tests for `createAndAssignCategory` —
  - creates and assigns when no matching category exists
  - reuses an existing category (case-insensitive) instead of creating a duplicate
  - rejects an empty/whitespace-only name (no-op, no category created)
  - a second payee's cached suggestion gets `matchedCategoryID` updated after a first payee's create — proves `rematchPendingSuggestions()` works without a new model call
- **`BudgetViewModelTests`**: new tests for `suggestionsAvailable` reflecting the injected `CategorySuggesting.isAvailable`.
- **Manual on-device verification required again** before `/release`: the `"Create '<name>'"` flow end-to-end, the rematch behavior with two payees mapping to the same new category in one CSV, and `AddBudgetSheet`'s empty state on both an eligible and an ineligible device/Simulator. Tooling for this is now established (local `Content-Disposition` download server + `cua-driver` pixel-click driving, per PR #62's verification pass).
