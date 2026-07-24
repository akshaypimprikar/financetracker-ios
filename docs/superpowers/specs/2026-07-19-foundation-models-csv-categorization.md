# Foundation Models Spike — CSV Payee→Category Suggestion — Design Spec

**Date:** 2026-07-19
**Status:** Draft

## Overview

During CSV import, transactions land with no `Category` assigned — `TransactionImportActor.save(chunk:accountID:)` today always constructs each `Transaction` with `category: nil`. This spike adds an on-device, zero-network category suggestion for each imported payee, using Apple's `FoundationModels` framework (`SystemLanguageModel`, iOS 26+, A17 Pro/M1 and later). The user sees a suggested category next to each row in the existing CSV import preview step, can accept or override it per row, and the chosen category is persisted onto the `Transaction` at import time. This is explicitly scoped as a spike: prove the on-device suggestion pipeline works end-to-end (inference → constrained output → UI → persistence) on the narrowest safe slice of the app, without expanding into auto-categorization elsewhere.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Model access pattern | Explicit `SystemLanguageModel()` (default on-device system model), never the swappable multi-provider path | Pre-verified: the swappable path can reach Private Cloud Compute or third-party providers. This is a fintech app — zero-network-call is a hard privacy requirement, not a preference. |
| Structured output | `@Generable`-typed `CategorySuggestion` struct with a nested `@Generable enum Confidence` (compile-time schema, token-constrained) | Pre-verified: `@Generable` is confirmed reliable for constrained/enum-typed output. `Confidence` is a true compile-time enum, so it gets full guided-generation constraint guarantees. |
| Category name field inside `CategorySuggestion` | Guided free-text `categoryName: String` (via `@Guide`), matched post-hoc in Swift against the live `Category` list (case-insensitive exact match), not a hard-constrained enum of category names | `Category` is a user-editable SwiftData model — its name set changes at runtime, so it cannot be a compile-time `@Generable` enum. Apple's runtime-schema APIs (`DynamicGenerationSchema`) could hard-constrain this, but that wasn't part of the pre-verified research for this card. Treating it as guided text + a defensive post-hoc match is the pragmatic reconciliation: it stays inside the settled "`@Generable` macro, compile-time schema" decision, and a non-match just yields no suggestion (fails safe) rather than an invalid `Category`. **Flagged below as the one point where I extrapolated beyond the settled research — see Needs Owner Input.** |
| Where the suggestion pipeline plugs in | New `CategorySuggesting` domain-service protocol (zero SwiftData imports) + concrete `FoundationModelsCategorySuggester` adapter, called from `ImportViewModel` during the existing `.preview` step | Matches the existing `TransactionImportWriting`/`TransactionImportActor` pattern already used for the CSV import path: a narrow protocol seam lets `ImportViewModelTests` use a fake (no real model call needed to unit test the ViewModel), while the concrete on-device adapter is verified by hand/UI test on real hardware. Zero SwiftData imports in the protocol satisfies the Domain Service layer rule. |
| Does the accepted suggestion persist? | Yes — `ParsedTransaction` gains a new **mutable, defaulted** `categoryID: UUID?` field; `TransactionImportActor.save` resolves it to a `Category` and attaches it to the `Transaction` it creates | A suggestion that can't be saved is a demo, not a feature — CLAUDE.md's production standard applies to a spike PR the same as any other PR. The new field defaults to `nil` and is appended after the existing stored properties, so `CSVImportServiceTests` and every existing `ParsedTransaction(...)` call site keep compiling unchanged. `importHash` computation is untouched — category never enters the hash. |
| Suggestion granularity | One model call per **unique payee** in the pending batch, not per row | A CSV with 50 "Starbucks" rows should cost one inference call, not 50. Keeps latency bounded and independent of import size. |
| Availability / hardware gate | `FoundationModelsCategorySuggester.isAvailable` wraps `SystemLanguageModel.default.availability == .available`; when `false`, `ImportViewModel` skips suggestion loading entirely — no chips shown, no error surfaced, import flow behaves exactly as it does today | Pre-verified gate is `#available(iOS 26, *)` + hardware/model-availability check. Since the whole app already targets `IPHONEOS_DEPLOYMENT_TARGET = 26.4`, the OS-version half of the gate is always true at compile time here — the only real runtime gate is hardware/model availability (a 26.4 device can still lack Apple Intelligence, e.g. iPhone 15 base). Silent skip (vs. an explanatory banner) is a UX judgment call — see Needs Owner Input. |
| Third-party agent framework | None used | No entry found in `.claude/context/decisions.md` for a prior evaluation, but the instruction to avoid one is honored regardless — `FoundationModels` is used directly. |

## Architecture

```
ImportSheet (View)
   │ renders suggestion chip per pending row, forwards taps
   ▼
ImportViewModel (@Observable)
   │ depends on: CategoryRepositoryProtocol, CategorySuggesting (new), existing deps
   │ loadSuggestions() — after applyMapping(), for each unique payee in pendingTransactions
   ▼
CategorySuggesting (new Domain Service protocol, Services/, zero SwiftData imports)
   │ suggestCategory(payee:candidates:) async throws -> CategorySuggestion?
   ▼
FoundationModelsCategorySuggester (concrete adapter, Services/)
   │ explicit SystemLanguageModel(), @Generable CategorySuggestion output
   ▼
FoundationModels framework (on-device inference, zero network calls)

--- on accept/override ---

ImportViewModel.setCategory(categoryID:forPayee:) mutates pendingTransactions[i].categoryID
   ▼
ImportViewModel.startImport() — unchanged chunking/TaskGroup structure
   ▼
TransactionImportWriting.save(chunk:accountID:) — protocol signature unchanged
   ▼
TransactionImportActor.save — NEW: resolves categoryID -> Category (cached lookup,
   mirrors existing resolveAccount(id:) pattern), attaches to each new Transaction
```

Only two existing files change behavior: `ImportViewModel` (new deps + two new methods) and `TransactionImportActor.save` (attaches category when present). `CSVImportService.parse()` itself is untouched — parsing stays pure and payee/model-agnostic, matching the existing test suite exactly as-is.

## Data Models

```swift
// FinanceTracker/Services/CSVImportService.swift — MODIFIED
struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
    var categoryID: UUID? = nil   // NEW — mutable, defaulted; never affects importHash
}
```

```swift
// FinanceTracker/Services/CategorySuggesting.swift — NEW
import Foundation
import FoundationModels

@Generable
struct CategorySuggestion: Sendable {
    @Guide(description: "The single best-matching category name from the list of existing category names provided in the prompt. Must be copied exactly from that list, character-for-character, or the literal string \"Uncategorized\" if none plausibly fit.")
    let categoryName: String

    @Guide(description: "Confidence that this suggestion is correct")
    let confidence: Confidence

    @Generable
    enum Confidence: String, Sendable {
        case high, medium, low
    }
}
```

No changes to `Category`, `Transaction`, or `TransactionImportWriting`'s method signature — `TransactionImportWriting.save(chunk:accountID:)` is unchanged; only `TransactionImportActor`'s internal implementation gains a category-resolution step reading `parsed.categoryID`.

## Domain Services

```swift
// FinanceTracker/Services/CategorySuggesting.swift
protocol CategorySuggesting: Sendable {
    /// Backed by SystemLanguageModel.default.availability == .available.
    /// Checked once per import session (preview step), not per row.
    var isAvailable: Bool { get }

    /// Suggests a category for one payee from the given candidates.
    /// Returns nil if unavailable, if the model errors, or if its chosen
    /// categoryName doesn't case-insensitively match any candidate name
    /// (fails safe — no suggestion is always a valid outcome).
    func suggestCategory(payee: String, candidates: [Category]) async -> CategorySuggestion?
}
```

```swift
// FinanceTracker/Services/FoundationModelsCategorySuggester.swift — NEW, concrete adapter
// Zero SwiftData imports (Category is referenced as a plain type, matching the
// existing BudgetCalculationService precedent). Imports FoundationModels only.
struct FoundationModelsCategorySuggester: CategorySuggesting {
    var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    func suggestCategory(payee: String, candidates: [Category]) async -> CategorySuggestion? {
        guard isAvailable, !candidates.isEmpty else { return nil }
        // Builds a session with an explicit SystemLanguageModel() instance (never the
        // swappable provider), prompts with payee + candidate names, requests
        // CategorySuggestion.self as the generation type, and matches the returned
        // categoryName back to a candidate case-insensitively. Any thrown error or
        // non-matching name yields nil rather than propagating.
    }
}
```

`CategorySuggesting` has zero SwiftData imports (Domain Service rule). `FoundationModelsCategorySuggester` is the one concrete implementation the app ships; it is not itself unit-testable without real Apple Intelligence–eligible hardware — `ImportViewModelTests` exercises the ViewModel against a `FakeCategorySuggesting` instead, consistent with how `FakeTransactionImportWriting` is already used for the actor.

## Navigation

No new screens or sheets. The existing `ImportSheet.previewStep`'s "Transactions to import" rows each gain a category suggestion affordance (chip/badge showing the suggested name + a way to accept or pick a different category, e.g. a `Menu` populated from `CategoryRepositoryProtocol.fetchAll()`). No new navigation destination is introduced.

## Design

*This feature touches Views (`ImportSheet`'s preview row).*

- New visual component needed: a category-suggestion chip/badge (payee row accessory) showing a category name plus a confidence affordance, and a way to override it inline.
- `docs/design-system.md` was checked — it defines Card, Row, Sheet, Empty State, and Progress Bar patterns, but **no chip/badge token exists today**.
- **`/design "category suggestion chip"` must run before `/feature`** for this spec, per CLAUDE.md's rule that any new visual pattern needs a token before implementation. This spec intentionally does not invent the chip's visual spec.

## Future Extension Points

- Applying suggestions outside CSV import (e.g., a "categorize all uncategorized transactions" bulk action reusing `CategorySuggesting` against existing `Transaction` rows) — explicitly out of scope for this spike.
- Local payee→category memory (cache accepted suggestions per payee so repeat imports of the same payee skip the model call entirely) — stays privacy-consistent (all local) and is a natural follow-up, not built here.
- Confidence-threshold auto-accept (e.g., auto-fill `.high` confidence suggestions without a tap) — deferred; needs a product decision, not a technical one.
- Runtime-constrained category selection via `DynamicGenerationSchema` instead of guided-text + post-hoc match, if the free-text approach proves unreliable in practice during implementation.

## Testing Strategy

- **Unit (Domain Service):** none possible against the real `FoundationModelsCategorySuggester` in CI — it requires live Apple Intelligence–eligible hardware. This is the accepted cost of the spike; call out explicitly rather than silently skipping coverage.
- **Unit (ViewModel):** `ImportViewModelTests` gains cases using a new `FakeCategorySuggesting` (mirrors `FakeTransactionImportWriting`): suggestions populate after `applyMapping()`, `setCategory` mutates the correct `pendingTransactions` entry, `isAvailable == false` yields zero suggestion calls and an unchanged preview list.
- **Integration:** `TransactionImportActorTests` gains a case asserting that a chunk containing a non-nil `categoryID` produces `Transaction`s with `category` set, and that existing category-less chunks still produce `category == nil` (regression guard on today's behavior).
- **Manual/on-device verification:** required before `/release` — the real `FoundationModelsCategorySuggester` must be exercised with a real CSV to confirm the guided-text `categoryName` match behaves as expected in practice, since this is the one part of the design that extrapolates beyond the pre-verified research. Two ways to satisfy this, either is acceptable:
  1. A physical A17 Pro+ iPhone (or M1+ iPad).
  2. **iOS Simulator, provided the host Mac itself is Apple Intelligence-eligible (M1+) and has Apple Intelligence enabled in macOS System Settings.** The Simulator uses the host Mac's Neural Engine directly rather than emulating a device's, so `SystemLanguageModel` runs for real — confirmed on an M3 Pro Mac against the project's existing iPhone 17 Simulator target. Requires macOS Tahoe 26+, Xcode 26+, and the Simulator's iOS runtime at 26+. If a suggestion call silently returns nothing during this verification, check the host Mac's battery level and power mode before assuming the match logic is broken — the model can decline to run under low-power conditions independent of the app.
- **UI test:** optional; if added, must be gated to skip on ineligible simulators rather than fail (existing `UITestImportFlowTests.swift` pattern extended, not a new suite).

## Needs Owner Input

1. **Free-text `categoryName` vs. hard-constrained runtime schema.** The pre-verified research confirms `@Generable`'s *compile-time* enum path is reliable, but `Category` names are a runtime, user-editable list — a true hard constraint would need `DynamicGenerationSchema`, which wasn't part of the settled research. This spec's working assumption is guided free-text matched post-hoc (fails safe to "no suggestion" on a miss). If that's not an acceptable tradeoff for a spike meant to validate the full pattern, the plan should scope in evaluating `DynamicGenerationSchema` instead.
2. **Exact chip/badge UI surface for accept/override.** I assumed a suggestion chip per row with a `Menu` fallback to pick a different category, no new sheet/screen. `/design` needs to actually define this — I did not want to invent visual details that belong to that step.
3. **Fallback UX when the model/hardware gate fails.** I assumed a fully silent skip (no chips, no banner, no error) when `SystemLanguageModel.default.availability != .available`, matching "acts exactly like today" behavior. An alternative is a subtle one-line explainer ("Category suggestions need a newer device") — this is a product/UX call, not a technical one.
4. **Is persist-on-accept in scope for the spike, or is read-only display enough?** I chose persist-on-accept (Approach A below) on the basis that an inert suggestion is a weak deliverable, but if the intent of "spike" here is strictly a throwaway technical proof (no schema/behavior change to the import save path), a narrower Approach B is available and touches zero existing tested code.
5. **Suggestion call volume ceiling.** No cap is specified on unique-payee count per import batch. A CSV with hundreds of unique payees means hundreds of sequential on-device inference calls in the preview step — worth setting an explicit ceiling (and a "suggestions truncated" UI state) if that latency is unacceptable, but no number was in the pre-verified research to anchor a default.

## Approaches Considered (for the record)

1. **Chosen — ViewModel-orchestrated enrichment with persist-on-accept.** New `CategorySuggesting` protocol + `FoundationModelsCategorySuggester`, called from `ImportViewModel` in the existing preview step; accepted category flows through a new `ParsedTransaction.categoryID` field into `TransactionImportActor.save`, which now attaches `Transaction.category`. Fits existing MVVM+Repository layering and the `TransactionImportWriting` precedent exactly; moderate blast radius (touches the recently-stabilized async CSV import path from the 2026-07-15 spec, but additively — no signature breaks, tests stay green with a default value).
2. **Rejected — read-only suggestion display, no persistence.** Same suggestion pipeline, but chips are decorative only; nothing is saved. Zero blast radius on the tested import/save path, truest to a minimal "spike," but ships a feature with no effect — conflicts with the project's standing production-quality bar, and CSV-imported transactions still have no path to get a category post-import today.
3. **Rejected — separate post-import categorization review screen.** New screen shown after import completes, operating on already-persisted (uncategorized) `Transaction`s via existing repositories; zero changes to the parse/save pipeline at all. Cleanest isolation, and reusable beyond CSV import — but it's a new navigation surface and its own feature, which is more scope than a "spike" should carry, and it defers rather than proves the CSV-import integration this card is actually asking about.
