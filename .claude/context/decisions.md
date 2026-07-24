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
