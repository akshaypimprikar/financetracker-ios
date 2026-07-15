# CSV Import Async Migration — Design Spec

**Date:** 2026-07-15
**Status:** Draft

## Overview

The CSV import path (`CSVImportService` → `ImportViewModel` → `SwiftDataTransactionRepository`) is fully synchronous today and runs entirely on the main actor. Two problems compound on any non-trivial import: `applyMapping()` checks each parsed row for a duplicate via `existsWithHash(_:)`, and each call does an *unfiltered* fetch of every `Transaction` in the store, filtered in memory — O(N×M) fetches for N parsed rows against M existing transactions. `confirmImport()` then inserts and calls `context.save()` once per transaction — O(N) individual saves. Both block the main thread for the whole operation, and neither can be cancelled if the user navigates away mid-import.

This spec replaces both paths with an async pipeline backed by a new `@ModelActor`: a single batched fetch replaces the per-row dedup scan, saves are chunked (200-500 records per `save()` call), the whole operation is cancellable via `TaskGroup` structured concurrency, and `ImportSheet` gets a live progress bar. `CSVImportService.parse()` and `deduplicated()` are pure, `Sendable`-safe functions already and are unchanged.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Dedup scan | Fix now, same PR | Same class of problem (O(N×M) main-thread fetch) as the save-batching bug; touching this code path twice would be wasted work. Confirmed with user 2026-07-15. |
| Progress UI | Real percentage progress bar | Matches the design already sketched in the Career board's `@ModelActor` writeup card; user chose this over a minimal spinner-only UI. |
| Concurrency shape | `TaskGroup` with actor-serialized children | Each chunk is a `group.addTask`, awaited via `for try await`. Writes still serialize on the single `@ModelActor` (single-writer-per-container), but cancellation propagates automatically to any not-yet-started chunk. Rejected: plain sequential `Task` (doesn't literally satisfy the backlog's "TaskGroup" requirement); fully pipelined parse+save overlap (real perf win, but adds concurrent-parsing complexity not needed to fix the audited bug — flagged as a Future Extension Point instead). |
| Progress signal | TaskGroup completion stream, not a literal `AsyncStream` on the actor | Iterating `for try await count in group` as chunks complete *is* an async stream of progress events. Adding a second `AsyncStream<Double>` on the actor on top of TaskGroup would be two concurrency patterns doing the same job. `progress: Double` on `ImportViewModel` is computed from the TaskGroup's completions. |
| Actor boundary | New `TransactionImportActor: ModelActor` in `Repositories/SwiftData/`, behind a new `TransactionImportWriting` protocol in `Repositories/Protocols/` | Not placed in `Services/` — Domain Services must have zero SwiftData imports (invariant #3), and `@ModelActor` requires `import SwiftData`. Protocol boundary keeps `ImportViewModel` depending on an abstraction, per invariant #4, and enables a test fake without a real `ModelContainer`. |
| DTO crossing the actor boundary | Reuse existing `ParsedTransaction` (mark `Sendable`) | Already a plain struct of `Date`/`Decimal`/`String` — no `@Model` types. No new DTO type needed. |
| Account correlation | `PersistentIdentifier`, not live `Account` | Per invariant/constraint #3 — `ImportViewModel` passes `selectedAccount!.persistentModelID`; the actor resolves it locally via `modelContext.model(for:)`, never receives or returns a live `Account`. |
| `ImportRecord` write | Stays on the existing `@MainActor` `importRecordRepo`, after the actor's TaskGroup completes | Sequential (not concurrent) access to two different `ModelContext` instances is safe; only *concurrent* access to the same context is the actual hazard. Keeps this write untouched and simple. |
| `TransactionRepositoryProtocol.existsWithHash` | Left in place, unused by import after this change | Still covered by its own repository-level unit tests and may be useful for a future single-item duplicate check (e.g. manual entry). Not deprecated — just no longer on the import hot path. |

## Architecture

```
ImportSheet (View)
  → ImportViewModel (@Observable, @MainActor default isolation)
      .applyMapping(_:) async throws        — parses CSV (sync, pure), then ONE await to
                                                importWriter.existingHashes() (was: N calls)
      .startImport(filename:) 
          → Task { withThrowingTaskGroup ... }  — stored as `importTask` for cancellation
              → chunk 1..k: group.addTask { try await importWriter.save(chunk:accountID:) }
              → for try await in group: update `progress`
          → importRecordRepo.save(record)   — unchanged, @MainActor, after TaskGroup completes
      .cancelImport()                        — importTask?.cancel()
  → TransactionImportWriting (protocol, Sendable)
      → TransactionImportActor (@ModelActor) — Repositories/SwiftData/
          .existingHashes() async throws -> Set<String>   — ONE fetch, in-memory Set
          .save(chunk: [ParsedTransaction], accountID: PersistentIdentifier) async throws
                                              — resolve Account via persistentModelID,
                                                insert chunk, ONE context.save() per chunk
```

`CSVImportService` (Domain Service, zero SwiftData imports) is unchanged — `parse()` and `deduplicated()` remain synchronous pure functions.

`FinanceTrackerApp.swift` gains a `TransactionImportActor` instance, constructed alongside `sharedModelContainer` in `init()` (constraint: never inside `ContentView` or a `@MainActor` ViewModel), threaded down through `ContentView` → `FinanceTrackerTabView` → `ImportViewModel.init`.

## Data Models

No new `@Model` types and no schema change. `ParsedTransaction` (currently in `CSVImportService.swift`) gains explicit `Sendable` conformance:

```swift
struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
}
```

## Domain Services

`CSVImportService` — unchanged (still zero SwiftData imports, still synchronous, still pure).

New protocol, `FinanceTracker/Repositories/Protocols/TransactionImportWriting.swift`:

```swift
protocol TransactionImportWriting: Sendable {
    func existingHashes() async throws -> Set<String>
    func save(chunk: [ParsedTransaction], accountID: PersistentIdentifier) async throws
}

enum TransactionImportError: Error {
    case accountNotFound
}
```

New actor, `FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift`:

```swift
@ModelActor
actor TransactionImportActor: TransactionImportWriting {
    func existingHashes() async throws -> Set<String> {
        let all = try modelContext.fetch(FetchDescriptor<Transaction>())
        return Set(all.compactMap(\.importHash))
    }

    func save(chunk: [ParsedTransaction], accountID: PersistentIdentifier) async throws {
        try Task.checkCancellation()
        guard let account = modelContext.model(for: accountID) as? Account else {
            throw TransactionImportError.accountNotFound
        }
        for parsed in chunk {
            let tx = Transaction(
                date: parsed.date, amount: parsed.amount, payee: parsed.payee,
                type: .debit, importHash: parsed.importHash, account: account
            )
            modelContext.insert(tx)
        }
        try modelContext.save()   // ONE save() per chunk, not per row
    }
}
```

`ImportViewModel` changes (`FinanceTracker/ViewModels/ImportViewModel.swift`):

```swift
@Observable
final class ImportViewModel {
    // existing stored properties unchanged, plus:
    private(set) var progress: Double = 0
    private(set) var isImporting = false
    private var importTask: Task<Void, Error>?

    private let importWriter: any TransactionImportWriting   // new dependency

    // applyMapping becomes async — one await replaces the N-call existsWithHash loop
    func applyMapping(_ mapping: ColumnMapping) async throws {
        let parsed = try importService.parse(csv: rawCSVText, mapping: mapping)
        let existingHashes = try await importWriter.existingHashes()
        let deduped = importService.deduplicated(parsed: parsed, existingHashes: existingHashes)
        pendingTransactions = deduped
        skippedCount = parsed.count - deduped.count
        step = .preview
    }

    func startImport(filename: String = "import.csv") {
        guard let account = selectedAccount else { return }
        let accountID = account.persistentModelID
        let items = pendingTransactions
        isImporting = true
        progress = 0
        importTask = Task {
            defer { isImporting = false }
            let chunks = items.chunked(into: 300)   // 200-500 range; 300 chosen as midpoint
            var completed = 0
            try await withThrowingTaskGroup(of: Int.self) { group in
                for chunk in chunks {
                    group.addTask { [importWriter] in
                        try await importWriter.save(chunk: chunk, accountID: accountID)
                        return chunk.count
                    }
                }
                for try await count in group {
                    completed += count
                    self.progress = Double(completed) / Double(items.count)
                }
            }
            let record = ImportRecord(filename: filename, transactionCount: items.count)
            try importRecordRepo.save(record)
            reset()
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }
}
```

`confirmImport()` is removed, replaced by `startImport()` + `cancelImport()`. `chunked(into:)` is a small `Array` extension (new file or inline private helper — implementation detail for `/feature`).

Bundled in the same PR (verified against current code 2026-07-15):
- `Task(name: "CSV import chunk \(index)")` on each `group.addTask` child — SE-0469, zero risk, surfaces in Instruments/LLDB.
- `@concurrent` audit on `Task {}` blocks in ViewModels, primarily `ImportViewModel`'s new `Task { }` in `startImport()` — since it performs `await importWriter.save(...)` immediately (no main-thread work first), mark the TaskGroup body `@concurrent` if profiling shows it holding a main-thread token unnecessarily; verify with Instruments during `/feature`, don't guess.
- `/gates` addition: grep `TransactionImportActor.swift` for `@MainActor` on the actor declaration (must be absent) and for any stored property typed as a `@Model` class (must be absent — only `ModelContext`/`ModelContainer`-typed members from the `@ModelActor` macro are allowed).
- `/gates` addition: grep confirms `context.save()` appears exactly once in `TransactionImportActor.swift`, outside any `for` loop over individual rows (chunk-level save, not row-level).

## Navigation

No new screens. `ImportSheet.swift` changes within the existing 3-step flow:

- **Column mapping step:** "Parse & Preview" button becomes `Task { try? await viewModel.applyMapping(mapping) }`.
- **Preview step:** "Import N Transactions" button becomes `Task { viewModel.startImport() }` (fire-and-forget from the View's perspective — `ImportViewModel` owns the task handle). While `viewModel.isImporting`, replace the button with a determinate `ProgressView(value: viewModel.progress)` + a "Cancel" button calling `viewModel.cancelImport()`.
- **Toolbar Cancel button + swipe-to-dismiss:** both must call `viewModel.cancelImport()` before `dismiss()` if `isImporting` is true, so navigating away mid-import actually cancels the in-flight `TaskGroup` rather than leaving it running detached.

## Design

Minor, additive-only change to `ImportSheet`'s preview step — a determinate `ProgressView` and a state-swapped button, both using existing `Theme` tokens already in use elsewhere in this file (`Theme.Spacing`, `Theme.Colors`, `Theme.Typography`). No new visual pattern — `docs/design-system.md` already covers determinate progress indicators (used in the CSV import sheet gallery per `/design` bootstrap). `/design` does not need to run before `/feature`.

## Future Extension Points

- **Fully pipelined parse+save overlap** (chunk N+1 parses concurrently while chunk N is mid-save via the actor) — real performance win, deliberately deferred: it doesn't fix the audited bug, and it adds concurrent-CPU-work complexity that isn't warranted for a bug-fix-scoped PR. Revisit if a future profiling pass shows the sequential parse-then-import-all-at-once step is itself a bottleneck for very large files.
- `TransactionImportActor.existingHashes()` returning ALL hashes in the store scales linearly with total transaction count, not import size. Fine at current data volumes; if it ever becomes a problem, narrow the fetch to only hashes matching the imported date range.
- Foundation Models CSV payee→category suggestion (separate backlog item, explicitly out of scope here) plugs in at `applyMapping()` or the preview step, operating on the same `ParsedTransaction` DTOs this spec introduces `Sendable` conformance for.

## Testing Strategy

- **Unit (Domain Service):** `CSVImportServiceTests.swift` — unchanged, `parse`/`deduplicated`/`importHash` are untouched pure functions.
- **Unit (ViewModel):** `ImportViewModelTests.swift` — update to `async throws` test functions for `applyMapping`/`startImport`. Add a `FakeTransactionImportWriting: TransactionImportWriting` test double (in-memory `Set<String>` + array of saved chunks) so ViewModel tests don't need a real `ModelContainer` for the import-writing path — existing tests already use a real in-memory container for the other repos, so this fake specifically isolates cancellation/chunking/progress assertions from actor/SwiftData plumbing.
- **New tests to add:** cancellation mid-import (start a large import, cancel after the first chunk, assert `pendingTransactions` reflects only what was saved and no partial chunk was persisted); progress reaches exactly 1.0 on completion; `existingHashes()` dedup produces identical results to the old per-row `existsWithHash` loop (regression-guard the behavior change, not just the performance change); account-not-found throws `TransactionImportError.accountNotFound` and doesn't crash.
- **Integration (Repository/Actor):** new `TransactionImportActorTests.swift` using the existing `ios-swiftdata-test-fixture` in-memory `ModelContainer` pattern — verify exactly one `context.save()` per chunk (not per row) by asserting on save-call count via a test-only counting wrapper, or by asserting chunk-boundary transaction counts after each `save(chunk:)` call.
- **UI test:** no existing CSV import UI test flow in `FinanceTrackerUITests` (confirmed 2026-07-15) — this PR is a reasonable place to add a first one, since the async progress bar is a new, easily-verified visual state. Use the `tapWhenEnabled` pattern from `reference_swiftdata_uitest_gotchas` for the button-tap-to-async-completion timing; confirm the progress bar becomes visible during import and disappears on completion.
- **`/gates`:** the two new grep-based checks described above (actor isolation shape, chunk-level `save()`).
