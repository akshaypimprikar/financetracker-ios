# Agent Decision Log

<!-- Append one entry per spec run. Never edit past entries. -->

## 2026-07-15 — CSV Import Async Migration
**Approaches considered:** (1) plain sequential cancellable `Task`, no `TaskGroup`; (2) `TaskGroup` with actor-serialized chunk children (writes still serialize on the single `@ModelActor`, cancellation propagates automatically to unstarted chunks); (3) fully pipelined `TaskGroup` where each child also parses/hashes its own chunk concurrently, overlapping CPU work with the actor's in-flight save.
**Chosen:** (2) — `TaskGroup` with actor-serialized children, plus fixing the previously-unscoped O(N×M) `existsWithHash` dedup scan in the same PR, plus a real percentage progress bar computed from the `TaskGroup`'s completion stream (no separate `AsyncStream` type needed).
**Reason:** Satisfies the audited bug (main-thread blocking on both the dedup scan and the per-row save) and the backlog's literal "TaskGroup" requirement without the added concurrent-parsing complexity of full pipelining, which doesn't fix a documented problem and was deferred as a Future Extension Point instead.

## 2026-07-19 — Foundation Models Spike: CSV Payee→Category Suggestion
**Approaches considered:** (1) `ImportViewModel`-orchestrated enrichment via a new `CategorySuggesting` domain-service protocol + `FoundationModelsCategorySuggester` adapter, with accepted suggestions persisted onto `Transaction.category` through a new mutable `ParsedTransaction.categoryID` field consumed by `TransactionImportActor.save`; (2) same suggestion pipeline but read-only display, no persistence changes to the import/save path; (3) a separate post-import categorization review screen operating on already-persisted transactions, with zero changes to the CSV parse/save pipeline.
**Chosen:** (1) — ViewModel-orchestrated enrichment with persist-on-accept.
**Reason:** Matches the existing `TransactionImportWriting`/`TransactionImportActor` protocol-seam precedent, keeps `CSVImportServiceTests` and all `ParsedTransaction` call sites compiling unchanged via a defaulted field, and avoids shipping an inert suggestion with no effect on the actual transaction record.

## 2026-07-21 — Foundation Models Spike: Owner Sign-Off on Needs Owner Input
Resolves the 5 open items from the 2026-07-19 spec (PR #56, merged). `/plan` should treat these as settled, not re-raise them:
1. **Free-text `categoryName` vs. hard-constrained runtime schema:** Ship the spec's free-text + post-hoc match as designed. `DynamicGenerationSchema` evaluation is *not* in scope for this spike — tracked separately as a Future Extension Point, revisit only if the free-text match proves unreliable in manual on-device testing.
2. **Chip/badge UI surface:** No decision needed here — stays deferred to `/design "category suggestion chip"`, which must run before `/feature` per the spec.
3. **Fallback UX on unavailable hardware:** Silent skip, as the spec assumed. No banner.
4. **Persist-on-accept vs. read-only:** Persist-on-accept (Approach A in the spec) — confirmed in scope for this spike.
5. **Suggestion call-volume ceiling:** No cap for this spike. Revisit only if manual on-device testing shows unacceptable latency on large unique-payee counts.

## 2026-07-26 — Category Seeding & AI-Suggested Category Creation
**Approaches considered:** (1) extend `CategorySuggestion` (the `@Generable` struct) directly with a plain `matchedCategoryID: UUID?` field; (2) wrap it in a new `CategorySuggestionResult` domain type, leaving `CategorySuggestion` as pure model output; (3) drop match-tracking entirely and have the View re-derive existing-vs-new by comparing the suggestion's name against its own category list at render/tap time.
**Chosen:** (2) — `CategorySuggestionResult` wrapper.
**Reason:** Mixing a post-hoc-computed field into an `@Generable` struct's stored properties is unverified against the real macro's schema-synthesis behavior — safer to keep `CategorySuggestion` as pure `@Guide`-annotated model output. The suggester already computes the match once internally (previously discarding it by returning `nil` on a miss); wrapping preserves a single source of truth for that determination rather than having the View re-derive it, matching the same DTO-boundary judgment already applied for `CategoryCandidate` earlier in this feature. Also folds in: seed category taxonomy on first launch (idempotent on an empty category list), one-tap AI-suggested category creation with fixed `.expense` type and default icon/color, a Menu-row sparkle highlight for the matched suggestion, and refreshing `ImportViewModel`'s categories/accounts on every `ImportSheet` appearance to fix the stale-list bug found during PR #62's manual verification.
