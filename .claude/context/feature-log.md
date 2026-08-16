# Feature Log

<!-- Append one entry per release. Never edit past entries. -->

## v1.2.1 — 2026-08-16
**Features added:** `/gates` Gate 10 (restored generic duplication/abstraction-bloat heuristic) and Gate 11 (RED-before-GREEN commit order — `/feature` now commits the failing test and its implementation separately, `scripts/check_tdd_commit_order.py` verifies the order from git history rather than trusting agent self-report); ported as a generic gate to the pragma template repo; README screenshots via a new `--seedscreenshots`/`--starttab` demo-data launch path
**Key files changed:** `.claude/commands/feature.md`, `.claude/commands/gates.md`, `.claude/commands/plan.md`, `.claude/commands/sync-workflow.md`, `.claude/commands/review.md`, `scripts/check_tdd_commit_order.py`, `.claude/settings.json`, `.claude/context/rejections.md`, `FinanceTracker/Debug/DemoDataSeeder.swift`
**Key architectural decisions:** RED and GREEN are separate, independently-committed steps per task (not squashed), specifically so git history itself is the audit trail for TDD discipline rather than an agent's narration of having followed it; `check_tdd_commit_order.py` uses `git log develop..HEAD` (double-dot) not triple-dot, since triple-dot's symmetric-difference semantics for `git log` (distinct from `git diff`) would silently include unrelated commits from an advancing base branch

## v1.2.0 — 2026-07-31
**Features added:** On-device CSV category suggestions (`CategorySuggesting`, `FoundationModelsCategorySuggester`, `CategoryNameMatching`, suggestion chips + one-tap category creation in `ImportSheet`); `TransactionImportActor` chunked/cancellable CSV import writes with progress bar and audit-trail-preserving partial-failure handling; versioned SwiftData schema (`SchemaV1` + no-op migration plan); device-aware Budget empty state; persistent memory layer (`.claude/context/`) wired into all agent commands; `/parallel-review`, `/pr-followup`, `/gates` Gate 8/9
**Key files changed:** `ImportViewModel.swift`, `ImportSheet.swift`, `TransactionImportActor.swift`, `CategorySuggesting.swift`, `FoundationModelsCategorySuggester.swift`, `CategoryNameMatching.swift`, `BudgetViewModel.swift`, `AddBudgetSheet.swift`, `.claude/commands/gates.md`, `.claude/context/`
**Key architectural decisions:** `CategorySuggesting` candidates passed as a Sendable DTO (not the live `@Model` type) so an actor can conform to the protocol; new categories staged in-memory until import actually completes, not persisted immediately on creation
