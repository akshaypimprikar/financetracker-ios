# Feature Log

<!-- Append one entry per release. Never edit past entries. -->

## v1.2.0 — 2026-07-31
**Features added:** On-device CSV category suggestions (`CategorySuggesting`, `FoundationModelsCategorySuggester`, `CategoryNameMatching`, suggestion chips + one-tap category creation in `ImportSheet`); `TransactionImportActor` chunked/cancellable CSV import writes with progress bar and audit-trail-preserving partial-failure handling; versioned SwiftData schema (`SchemaV1` + no-op migration plan); device-aware Budget empty state; persistent memory layer (`.claude/context/`) wired into all agent commands; `/parallel-review`, `/pr-followup`, `/gates` Gate 8/9
**Key files changed:** `ImportViewModel.swift`, `ImportSheet.swift`, `TransactionImportActor.swift`, `CategorySuggesting.swift`, `FoundationModelsCategorySuggester.swift`, `CategoryNameMatching.swift`, `BudgetViewModel.swift`, `AddBudgetSheet.swift`, `.claude/commands/gates.md`, `.claude/context/`
**Key architectural decisions:** `CategorySuggesting` candidates passed as a Sendable DTO (not the live `@Model` type) so an actor can conform to the protocol; new categories staged in-memory until import actually completes, not persisted immediately on creation
