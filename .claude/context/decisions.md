# Agent Decision Log

<!-- Append one entry per spec run. Never edit past entries. -->

## 2026-07-15 — CSV Import Async Migration
**Approaches considered:** (1) plain sequential cancellable `Task`, no `TaskGroup`; (2) `TaskGroup` with actor-serialized chunk children (writes still serialize on the single `@ModelActor`, cancellation propagates automatically to unstarted chunks); (3) fully pipelined `TaskGroup` where each child also parses/hashes its own chunk concurrently, overlapping CPU work with the actor's in-flight save.
**Chosen:** (2) — `TaskGroup` with actor-serialized children, plus fixing the previously-unscoped O(N×M) `existsWithHash` dedup scan in the same PR, plus a real percentage progress bar computed from the `TaskGroup`'s completion stream (no separate `AsyncStream` type needed).
**Reason:** Satisfies the audited bug (main-thread blocking on both the dedup scan and the per-row save) and the backlog's literal "TaskGroup" requirement without the added concurrent-parsing complexity of full pipelining, which doesn't fix a documented problem and was deferred as a Future Extension Point instead.
