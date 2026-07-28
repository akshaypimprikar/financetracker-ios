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
5. **Near-duplicate category matching** — a shared `CategoryNameMatching` utility, replacing exact-string comparison everywhere a category name gets checked against the existing list: the AI-suggestion match check, the AI-create dedup check, and (new) the manual "Add Category" flow in Settings, which today has no duplicate checking at all.

No seeding. Items 1 and 3 are coupled: a category created mid-import must be immediately usable for the rest of that same import session without a relaunch. Item 5 applies uniformly across both AI-driven and manual category creation — it's not specific to either device-capability path.

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
| Duplicate matching: exact vs. near-duplicate | New shared `CategoryNameMatching.isNearDuplicate(_:_:)` utility, replacing every ad-hoc case-insensitive string compare in this feature. Normalizes each name to a lowercased, punctuation-stripped, connector-word-dropped (`"and"`, `"the"`, `"of"`, `"for"`, `"a"`, `"an"`) **token set**, then compares sets for exact equality — order-independent, so `"Coffee & Dining"` and `"Dining & Coffee"` normalize to the same set and match. | Catches the motivating case (word-order/connector variation) without the false-positive risk of a similarity threshold: `"Travel"` → `{travel}` and `"Travel Insurance"` → `{travel, insurance}` are different sets, so they correctly do **not** match despite one containing the other as a substring. A threshold-based approach (edit distance, Jaccard similarity) would need a tuned cutoff and risks exactly this kind of false merge in a finance app, where silently combining two categories the user meant to keep separate is worse than occasionally missing a true near-duplicate. Real typos (`"Grocerys"`) and true synonyms (`"Dining"` vs. `"Restaurants"`) are **not** caught by this — token-set equality only, not fuzzy spelling correction. Documented as a residual, accepted gap in Future Extension Points. |
| Where `CategoryNameMatching` is used | Three call sites, previously three separate ad-hoc comparisons: `FoundationModelsCategorySuggester`'s match check (AI suggestion vs. existing categories), `ImportViewModel.createAndAssignCategory`'s dedup check (AI-create vs. existing categories), and `CategoryViewModel.findNearDuplicate` (new — manual "Add Category" vs. existing categories). | One shared, independently testable utility instead of three copies that could silently drift apart. |
| Manual "Add Category" duplicate handling | `AddCategorySheet` shows an inline warning below the Name field when the entered name is a near-duplicate of an existing category (`"A similar category already exists: '<existing name>'"`), and disables the "Add" button while it's showing — a block, not just a warning the user can dismiss. | Extends this spec's scope to a screen that's existed since before any of this feature was built, and has never had duplicate checking. Blocking (not just warning-and-allowing) matches how `canAdd`-style validation already gates every other "Add" button in this codebase (`AddTransactionSheet`, `AddBudgetSheet`) — consistent with existing convention rather than a new interaction pattern. |
| Duplicate-category guard (AI-create) | `createAndAssignCategory` checks for an existing near-duplicate **before** creating; reuses it if found, only inserts if truly absent. Also trims and rejects an empty/whitespace-only name. | Without a seed baseline, this is no longer a rare edge case: `loadSuggestions()` computes suggestions for every unique payee in one batch, before the user has tapped anything. If a CSV has both "Starbucks" and "Peet's Coffee" and neither matches an existing category, both independently propose creating "Coffee & Dining" — accepting both without this guard would create two separate categories with the same name. |
| Rematch after create | After any category is created via `createAndAssignCategory`, re-run the (cheap, pure, no-model-call) near-duplicate check against every other still-unconfirmed cached suggestion, updating `matchedCategoryID` where a name now matches. | Without this, a second payee's chip/menu would keep cosmetically saying `"Create 'Coffee & Dining'"` even after the first payee's tap already created that exact category — the duplicate-guard above would still prevent a second insert at tap time, but the label would be misleading until then. This keeps every pending suggestion's label accurate as categories come into existence mid-session. |
| Menu highlight for matched suggestion | Sparkle icon (same glyph as the chip, opacity from the same confidence-based `Theme.Chips` tokens) prefixed to the matched category's row inside the `Menu` | Reuses existing iconography/tokens exactly — no new design tokens, no `/design` cycle needed. Reverses the 2026-07-19 spec's original call not to distinguish the suggested row, based on live-testing feedback that the omission was real friction. |
| `ImportViewModel` refresh scope | `ImportSheet` calls `viewModel.load()` again in `.onAppear`, in addition to the existing app-launch `.task` call | Fixes the stale-list bug for the whole import flow — covers "added a category in Settings, then opened Import in the same session," and is a prerequisite for the AI-create flow to make sense at all without seeding. Scoped to `ImportSheet` only; the same staleness likely exists elsewhere (e.g. `BudgetViewModel`'s category list) — see Future Extension Points. |
| Device-awareness plumbing cost | `AddBudgetSheet`'s `BudgetViewModel` gains a new dependency on `CategorySuggesting.isAvailable` (or an equivalent boolean), which it doesn't have today — that's only wired into `ImportViewModel` currently. This means threading a new constructor parameter through `BudgetViewModel`, `ContentView`'s DI wiring, and every existing `BudgetViewModelTests` call site. | Called out explicitly because it's a real, non-trivial cost of the device-aware empty-state decision — the same shape of change as adding `categoryRepo` to `ImportViewModel` earlier in this feature, applied to a second ViewModel. `/plan` should size this as its own task. |

## Architecture

```
CategoryNameMatching.isNearDuplicate(_:_:)  [NEW — shared utility, no dependencies]
   ▲ used by all three call sites below

ImportSheet.onAppear  [NEW]
   │ viewModel.load()  — re-fetches accounts + categories fresh every time the sheet opens
   ▼
ImportViewModel (existing loadSuggestions() / setCategory(), unchanged)
   │ NEW: createAndAssignCategory(named:forPayee:)
   │   1. trim + reject empty name
   │   2. reuse existing category via CategoryNameMatching.isNearDuplicate, else create
   │   3. setCategory(...) to assign it to this payee's rows
   │   4. rematch all other pending suggestions against the updated category list
   ▼
CategoryRepositoryProtocol.save(_:)  — existing, unchanged

CategorySuggesting.suggestCategory(payee:candidates:) -> CategorySuggestionResult?  [CHANGED return type]
   ▼
FoundationModelsCategorySuggester
   │ unchanged model call; NEW: computes matchedCategoryID via CategoryNameMatching after
   │ generation, wraps in CategorySuggestionResult; still returns nil for unavailable/error/
   │ "Uncategorized"; candidates.isEmpty no longer forces nil — model can propose from nothing
   ▼
ImportSheet.categoryChip / .categoryMenu  [CHANGED]
   │ matchedCategoryID != nil → sparkle-highlight that row in the Menu (existing accept flow)
   │ matchedCategoryID == nil → "Create '<name>'" row → createAndAssignCategory(...)

CategoryViewModel  [NEW: findNearDuplicate(named:)]
   ▼
AddCategorySheet  [NEW]
   │ name near-duplicates an existing category → inline warning, "Add" disabled

BudgetViewModel  [NEW dependency: CategorySuggesting.isAvailable]
   ▼
AddBudgetSheet  [NEW]
   │ unbudgetedCategories.isEmpty && isAvailable        → "Import a CSV to get AI-suggested categories"
   │ unbudgetedCategories.isEmpty && !isAvailable       → "Add Category" button → AddCategorySheet (existing, inline)
```

Files touched: `CategoryNameMatching.swift` (new), `CategorySuggesting.swift`, `FoundationModelsCategorySuggester.swift`, `FakeCategorySuggesting` (test fixture), `ImportViewModel.swift`, `ImportSheet.swift`, `CategoryViewModel.swift`, `AddCategorySheet.swift`, `BudgetViewModel.swift`, `AddBudgetSheet.swift`, `ContentView.swift` (DI wiring for `BudgetViewModel`'s new dependency). One new file, no new `@Model` types.

## Data Models

No new or modified `@Model` types. AI-created categories are ordinary `Category` instances via the existing `Category(name:icon:colorHex:type:)` initializer — no schema change, no migration.

## Domain Services

`FinanceTracker/Services/CategoryNameMatching.swift` — new file, shared utility, zero SwiftData imports:

```swift
import Foundation

/// Order-independent, connector-word-insensitive category name matching. Two names
/// are considered the same category if their normalized token sets are exactly equal
/// — catches word-order and connector variations ("Coffee & Dining" vs "Dining & Coffee"
/// vs "Coffee and Dining") without the false-positive risk of a broader similarity
/// threshold: "Travel" and "Travel Insurance" have different token sets, so they are
/// correctly NOT treated as duplicates despite one containing the other. Does not catch
/// typos or synonyms — token-set equality only, not fuzzy spelling correction.
enum CategoryNameMatching {
    private static let connectors: Set<String> = ["and", "the", "of", "for", "a", "an"]

    static func isNearDuplicate(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTokens(lhs) == normalizedTokens(rhs)
    }

    private static func normalizedTokens(_ name: String) -> Set<String> {
        Set(
            name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !connectors.contains($0) }
        )
    }
}
```

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
- Otherwise compute `matchedCategoryID = candidates.first(where: { CategoryNameMatching.isNearDuplicate($0.name, suggestion.categoryName) })?.id` and return `CategorySuggestionResult(suggestion: suggestion, matchedCategoryID: matchedCategoryID)`.

`FinanceTracker/ViewModels/ImportViewModel.swift` — new method:

```swift
func createAndAssignCategory(named name: String, forPayee payee: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let category: Category
    if let existing = categories.first(where: { CategoryNameMatching.isNearDuplicate($0.name, trimmed) }) {
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
            CategoryNameMatching.isNearDuplicate($0.name, result.suggestion.categoryName)
        }) else { continue }
        suggestions[payee] = CategorySuggestionResult(suggestion: result.suggestion, matchedCategoryID: match.id)
    }
}
```

`FinanceTracker/ViewModels/CategoryViewModel.swift` — new method:

```swift
func findNearDuplicate(named name: String) -> Category? {
    categories.first(where: { CategoryNameMatching.isNearDuplicate($0.name, name) })
}
```

`FinanceTracker/ViewModels/BudgetViewModel.swift` — new dependency and exposed property:

```swift
private let categorySuggester: any CategorySuggesting   // new init param, defaulted like ImportViewModel's

var suggestionsAvailable: Bool { categorySuggester.isAvailable }
```

## Navigation

No new screens. `AddBudgetSheet`'s empty-state branch (Apple Intelligence unavailable) presents the existing `AddCategorySheet` inline via `.sheet` — reusing the Settings flow, not a new screen. The chip's existing `Menu` gains one conditional row (`"Create '<name>'"`) and a sparkle prefix on a matched row — both additions to the already-existing `Menu`. `AddCategorySheet` gains an inline validation message — no new presentation, same sheet.

## Design

*Touches `ImportSheet`'s existing chip/`Menu` component, `AddBudgetSheet`'s empty state, and `AddCategorySheet`'s form validation — no new visual component.*

- `docs/design-system.md`'s "Suggestion Chips" section already covers the chip and its confidence-opacity tokens (`Theme.Chips.confidenceHigh/Medium/Low`, `Theme.Typography.chipLabel`). The Menu-row sparkle highlight reuses these exact tokens.
- The `"Create '<name>'"` row is a plain `Button` inside the existing `Menu`, styled by the system.
- `AddBudgetSheet`'s empty-state message is plain text (`ContentUnavailableView` or similar, matching the existing Empty State pattern in `docs/design-system.md`) plus, on the ineligible-device branch, a standard button presenting `AddCategorySheet`.
- `AddCategorySheet`'s duplicate warning is inline `Text` styled as a standard form validation message (`.foregroundStyle(Theme.Colors.destructive)`, matching how the rest of the app signals a blocking validation state), placed below the Name field.
- **No new tokens, no `/design` cycle required before `/feature`.**

## Future Extension Points

- App-wide fix for the stale-ViewModel-data pattern (a shared reactive category/account store, or a consistent refresh-on-appear applied to every ViewModel that reads categories/accounts) — this spec only fixes `ImportSheet`.
- `CategoryType` (income vs. expense) inference for AI-created categories — currently always `.expense`, tied to `TransactionImportActor` hardcoding `.debit`. Revisit together if CSV import ever supports credits.
- Icon/color inference for AI-created categories — currently fixed defaults (`tag.fill`, `#888888`); could use a curated name→icon heuristic later.
- Category-name consistency over time, residual gap even with `CategoryNameMatching`: each `suggestCategory` call uses a fresh `LanguageModelSession` with no memory of how other payees in the same (or a later) import were categorized, and `CategoryNameMatching` only catches token-set-equal variations, not true typos ("Grocerys") or synonyms ("Dining" vs. "Restaurants"). This is a **reasoned expectation, not something tested**: revisit only if real usage shows fragmentation the token-set match can't catch.
- Confidence-threshold auto-accept (already deferred in the 2026-07-19 spec) — still out of scope.

## Testing Strategy

- **`CategoryNameMatchingTests`** (new suite, pure functions, no live model needed): exact match; case difference; word-order swap ("Coffee & Dining" vs. "Dining & Coffee"); connector variation ("Coffee & Dining" vs. "Coffee and Dining"); punctuation/whitespace noise; **negative cases** — "Travel" vs. "Travel Insurance" must NOT match, "Shopping" vs. "Online Shopping" must NOT match, two unrelated names must NOT match. The negative cases matter as much as the positive ones here — this utility's whole value proposition is not over-matching.
- **`FoundationModelsCategorySuggester`**: the match-check call site now delegates to `CategoryNameMatching` — no separate test needed for the delegation itself beyond what `CategoryNameMatchingTests` already covers, closing part of the previously-accepted 0%-coverage gap on that file.
- **`FakeCategorySuggesting`**: update to return `CategorySuggestionResult?` (rename `suggestionsByPayee` → `resultsByPayee`); existing `ImportViewModelTests` call sites need the same rename.
- **`ImportViewModelTests`**: new tests for `createAndAssignCategory` —
  - creates and assigns when no near-duplicate category exists
  - reuses an existing category (including a near-duplicate, not just exact match) instead of creating a duplicate
  - rejects an empty/whitespace-only name (no-op, no category created)
  - a second payee's cached suggestion gets `matchedCategoryID` updated after a first payee's create — proves `rematchPendingSuggestions()` works without a new model call
- **`CategoryViewModelTests`**: new tests for `findNearDuplicate` — returns the existing category on a near-duplicate name, `nil` when nothing matches.
- **`BudgetViewModelTests`**: new tests for `suggestionsAvailable` reflecting the injected `CategorySuggesting.isAvailable`.
- **Manual on-device verification required again** before `/release`: the `"Create '<name>'"` flow end-to-end, the rematch behavior with two payees mapping to the same new category in one CSV, `AddBudgetSheet`'s empty state on both an eligible and an ineligible device/Simulator, and `AddCategorySheet`'s duplicate warning blocking a near-duplicate manual entry. Tooling for this is now established (local `Content-Disposition` download server + `cua-driver` pixel-click driving, per PR #62's verification pass).
