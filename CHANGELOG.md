# Changelog

All notable changes to FinanceTracker are documented here.

---

## [Unreleased]

- Add `/goal` usage tips to `/gates` and `/test` — manual autonomous fix-loop for failing build/test gates, with a deterministic-condition warning
- Add `/parallel-review` command — runs `/review`'s architecture checklist and `code-review:code-review` in parallel after `/feature`, before `/gates`, so PR-stage `/review` passes on the first try
- Wrap all `@Model` types in `SchemaV1: VersionedSchema` with a no-op `FinanceTrackerMigrationPlan` to prevent silent data corruption on future model changes
- Add `.claude/context/` directory with invariants, decisions, rejections, feature-log seed files
- Wire context read preambles into all 8 agent command files (spec, plan, feature, review, gates, bugfix, release, test)
- Wire context write postambles into /spec (decisions.md), /review (rejections.md), /gates (invariants.md candidates), /release (feature-log.md)
- Skip Gates 1 (build) and 2 (test suite) when no Swift files changed — mirrors existing Gate 6/7 conditional pattern
- Add `TransactionImportActor` (`@ModelActor`) and `TransactionImportWriting` protocol for chunked, cancellable CSV import writes, replacing the per-row `existsWithHash` scan and per-row `save()`
- Migrate `ImportViewModel` to the async `TransactionImportActor` pipeline — `TaskGroup`-driven chunked saves, cancellation, and progress reporting; fixes a data-duplication bug where cancelling or retrying an import could re-send already-persisted rows
- Add a determinate progress bar and cancel button to `ImportSheet` during CSV import, plus a first UI test for the import entry point
- Add `/gates` Gate 8 verifying `TransactionImportActor`'s concurrency shape (no `@MainActor` isolation, no `@Model` type crossing its public boundary, exactly one chunked `save()`)
- Fix CSV import silently losing the audit trail on partial failure, misreporting a fully-successful import as a total failure when only the bookkeeping record save throws, and leaving a silent failure state with no error message — `ImportViewModel` now writes a best-effort `ImportRecord` for whatever partially completed, distinguishes a bookkeeping-only failure from a data failure, surfaces both via an alert in `ImportSheet`, and guards all of it with a generation token so a cancelled-but-still-unwinding import can't clobber a session the user has since started fresh

---

## [1.1.0] — 2026-05-23

### Added
- **Charts** — running balance line chart on Account detail; month-over-month spending bar chart on Budget detail; both gated on data presence
- **Theme token system** — `Colors.swift`, `Spacing.swift`, `Typography.swift` with semantic tokens; all existing views refactored to use tokens
- **`Theme/Charts.swift`** — chart visualisation tokens: `balanceLine`, `balanceAreaFill`, `spendingBar`, `gridLine`, `minHeight`, `lineStrokeWidth`
- **`docs/design-system.md`** — canonical token reference and component pattern guide, including Data Visualisation section
- **Theme unit tests** — 15 tests covering all color and spacing token values
- **`/design` agent** — bootstrap and extend modes; establishes `Theme/` token system before UI features; enforced via `/spec` and `/review`
- **PR checks CI** — GitHub Actions workflow with coverage enforcement (fail <60%, warn <80%) and path-filtered triggers
- **UI tests CI** — separate workflow blocking PRs on `UITestChartsTests` failures; `pull_request` trigger added so broken tests can no longer reach `develop`
- **Coverage enforcement** — `xccov` check reports per-file line coverage
- **Pre-push git hook** — blocks direct pushes to `develop`/`main` and already-merged PR branches
- **Pipeline tooling** — `/gates`, `/pipeline-review`, `/status` commands; CHANGELOG rule in `/bugfix`; cross-repo shell safety rule in CLAUDE.md

### Fixed
- **Correctness** — `BalanceService` anchor offset; `CSVImportService` negative amounts and date-only hash; `BudgetViewModel` duplicate detection; `TransactionRepository` transfer fetch; `BudgetRepository` sort order
- **Chart UI tests** — corrected accessibility identifiers, removed wrong NavigationStack navigation assumption, skipped redundant Picker interaction in budget test
- **All UI tests** — increased timeouts from 3s to 10s and added navigation bar existence checks before button taps; 3s was consistently too short for CI runners
- **UX** — rendering and interaction correctness across ViewModels and Views

---

## [1.0.0] — 2026-05-11

### Added
- **Multi-agent workflow** — 8 slash commands (`/spec`, `/plan`, `/feature`, `/test`, `/review`, `/bugfix`, `/release`, `/sync-workflow`) defining a full spec → plan → TDD → PR → release pipeline
- **UI tests** — 6 XCUITest flows covering tab navigation, add account, add transaction, add budget, and add category; `--uitesting` launch arg switches SwiftData to in-memory store for clean isolation
- **Accessibility identifiers** — 13 identifiers across 8 view files for stable test targeting
- **Gitflow** — `develop` integration branch; `feature/*`, `fix/*`, `spec/*` → `develop`; `release/*` → `main` via PR
- **README** — project overview, pipeline diagram, architecture summary, repo structure guide
- `.gitignore` covering Xcode derived data, `.DS_Store`, Claude local files, and plugin cache
- `CLAUDE.md` trimmed to 44 lines with always-on architecture rules and agent pipeline

### Fixed
- Removed nested duplicate Xcode project structure that caused `PBXFileSystemSynchronizedRootGroup` to compile every Swift file twice

---

## [0.2.0] — 2026-05-08

### Added
- **CSV Import** — 3-step import flow (file picker → column mapping → preview/confirm) with SHA256 deduplication
- **`ImportViewModel`** — state machine managing the 3-step import process
- **`ImportSheet`** — SwiftUI sheet for the full import flow
- **`ImportRecordRepositoryProtocol`** + **`SwiftDataImportRecordRepository`** — audit log persistence
- **Budgets tab** — `BudgetViewModel`, `BudgetListView`, `AddBudgetSheet`, `BudgetDetailView` with month selection and progress tracking
- **Settings tab** — `CategoryViewModel`, `SettingsView`, `AddCategorySheet` for managing expense/income categories
- All 6 ViewModels wired into `ContentView` via repository injection
- Tests for `ImportViewModel` (4), `BudgetViewModel` (4)

### Fixed
- `AddTransactionSheet` Picker tags switched from `Category?` to `UUID?` to avoid `Hashable` conformance conflict on `@Model` types

---

## [0.1.0] — 2026-05-07

### Added
- **Foundation** — full MVVM + Repository architecture
- **Data models** — `Account`, `Transaction`, `Category`, `Budget`, `ImportRecord` (`@Model`)
- **Domain services** — `BalanceService`, `NetWorthService`, `BudgetCalculationService`, `CSVImportService`, `NotificationService`
- **Repository protocols** — `AccountRepositoryProtocol`, `TransactionRepositoryProtocol`, `CategoryRepositoryProtocol`, `BudgetRepositoryProtocol`, `ImportRecordRepositoryProtocol`
- **SwiftData repositories** — implementations for all 5 protocols
- **ViewModels** — `AccountViewModel`, `TransactionViewModel`, `DashboardViewModel`
- **Core screens** — Dashboard, Transaction list + detail, Account list + add sheet, Add Transaction sheet
- **5-tab navigation** — Dashboard · Transactions · Budgets · Accounts · Settings (`TabView` + `NavigationStack`)
- Unit and integration tests for all Domain Services and repository implementations
