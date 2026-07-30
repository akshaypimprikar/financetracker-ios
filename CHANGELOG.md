# Changelog

All notable changes to FinanceTracker are documented here.

---

## [Unreleased]

- Fix `CategoryNameMatching` being type-blind (`Category.type` never considered): (1) `isNearDuplicate` now requires both sides' `CategoryType` to match, so an Income category and an Expense category sharing a name (e.g. "Rent") are no longer treated as duplicates of each other; (2) `ImportViewModel.loadSuggestions` now excludes Income categories from AI-suggestion candidates entirely, since CSV import always creates `.debit` transactions — an Income category can no longer be suggested or cross-attached to an imported transaction; (3) `AddCategorySheet`'s manual duplicate-warning check is now type-scoped, so a user can create a same-named category of a different type without being incorrectly blocked
- CI: disable parallel testing (multiple simulator clones) for the UI Tests job — 3 consecutive PR #62 CI runs showed a different UI test failing each time alongside abnormal per-test durations (up to 431s) and repeated LLDB debugserver connection errors, consistent with clone contention on the shared `macos-26` runner rather than a test-logic bug. Unit tests are unaffected — this only touches `ui-tests.yml`
- Fix a flaky CI-only test: `cancelImportClearsPendingTransactionsToPreventStaleRetry` guessed a 50ms `Task.sleep` window to land inside an in-flight chunk write before cancelling, which occasionally missed under GitHub Actions' `macos-26` runner scheduling. `FakeTransactionImportWriting` now exposes `waitUntilChunksStarted(_:)`, a deterministic signal the test awaits instead of guessing
- Fix `code-review`-caught bugs in the category-seeding & AI-creation feature: (1) a partial mid-loop `categoryRepo.save` failure in `ImportViewModel.startImport` could leave an already-saved category permanently orphaned — now rolled back so the operation is all-or-nothing; (2) the suggestion-loading loop in `loadSuggestions` had no generation guard, so an abandoned session's in-flight model call could write a stale suggestion into a session the user has since started fresh — now generation-checked like `startImport`'s task; (3) `CategoryNameMatching.isNearDuplicate` treated any two connector-word-only names (e.g. "The", "For") as duplicates of each other, since both normalize to an empty token set; (4) `AddCategorySheet` persisted the untrimmed name even though validation used the trimmed one
- Complete `/gates` Gate 9's architecture-compliance port — the earlier consolidation of `/review`'s checklist into `/gates` dropped the Patterns checks (`@Model final class` + UUID id, relationship `deleteRule`, service statelessness, `Transaction.importHash` presence); added back with corrected greps (the naive stored-`var` pattern initially flagged computed properties as false positives)
- Remove auto-merge instruction from `/review`'s "Done when" — it now reports its verdict and stops. Add a CLAUDE.md "Merge rule": a PR merges only after `/review` APPROVED, `/test` passing, and `code-review:code-review` clean, and the user merges it themselves (GitHub blocks authors from approving their own PRs, so approval can't be the gate here)
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
- Add `Theme/Chips.swift` and a `chipLabel` typography token for the category-suggestion chip pattern (CSV import preview) — confidence shown via sparkle-icon opacity rather than separate icons or colors per level
- Add optional `categoryID` field to `ParsedTransaction`, defaulted so existing call sites are unaffected — carries a user-accepted category suggestion from CSV import preview through to persistence without entering the `importHash` dedup calculation
- Add `CategorySuggesting` Domain Service protocol and `CategorySuggestion`/`Confidence` `@Generable` types for on-device payee→category suggestion — `candidates` are passed as a Sendable `CategoryCandidate` DTO (id + name only), not the live `Category` model, so the protocol can safely be conformed to by an actor
- Add `FoundationModelsCategorySuggester` — the concrete on-device adapter, explicit `SystemLanguageModel` (zero network calls), fails safe to no suggestion on unavailable hardware, model error, or a non-matching category name
- Add `FakeCategorySuggesting` test fixture — mirrors `FakeTransactionImportWriting`'s actor-based call-tracking pattern for the new suggestion protocol
- Wire `CategorySuggesting` into `ImportViewModel` — `loadSuggestions()` (one call per unique payee, not per row) and `setCategory(categoryID:forPayee:)` (applies to every pending row sharing that payee); `reset()` now clears stale per-session suggestions, not just `pendingTransactions`
- `TransactionImportActor.save` resolves `ParsedTransaction.categoryID` to a `Category` and attaches it to each new `Transaction`; a stale/unresolvable id degrades to an uncategorized transaction rather than failing the chunk, and misses are cached alongside hits so a repeated stale id isn't re-fetched per row
- Render the category suggestion chip in `ImportSheet`'s preview step — sparkle-opacity-by-confidence when unconfirmed, plain capsule once the user has picked a category via the chip's `Menu`; accepting the model's suggestion and overriding it are the same tap, no separate accept affordance
- Add `CategoryNameMatching` — order-independent, connector-word-insensitive category name matching (token-set equality, not a similarity threshold) shared by the AI-suggestion match check, AI-create dedup, and manual category creation
- `CategorySuggesting.suggestCategory` now returns `CategorySuggestionResult` (the model's `CategorySuggestion` plus a `matchedCategoryID: UUID?` computed via `CategoryNameMatching`), instead of a plain `CategorySuggestion?`; `FoundationModelsCategorySuggester` no longer requires a non-empty candidate list — a brand-new user's first CSV import can now propose a category from nothing, since no categories are ever seeded
- Add `ImportViewModel.createAndAssignCategory(named:forPayee:)` — one tap creates (or reuses an existing near-duplicate of) the model's proposed category and assigns it to that payee's rows; also rematches every other still-unconfirmed cached suggestion against the newly created/reused category so a second payee's chip doesn't keep offering to "create" a category that already exists
- Fix `ImportSheet` only refreshing categories/accounts once at app launch — re-runs `viewModel.load()` in `.onAppear` so a category added in Settings (or a prior import session) shows up without an app relaunch
- `ImportSheet`'s category chip now shows a `"Create '<name>'"` row in its `Menu` when the model's suggestion has no existing-category match, and sparkle-highlights the matched row when it does — reversing the original spec's call not to distinguish the suggested row, based on live-testing feedback
- Add `CategoryViewModel.findNearDuplicate(named:)`, reusing `CategoryNameMatching`; `AddCategorySheet` now warns "A similar category already exists: '<name>'" and blocks Add when the entered name near-duplicates an existing category
- `BudgetViewModel` gains a `categorySuggester` dependency (defaulted) and `suggestionsAvailable`; `AddBudgetSheet`'s empty state is now device-aware — CSV-import-only messaging when Apple Intelligence suggestions are available, a manual "Add Category" fallback (presenting `AddCategorySheet` inline) when they aren't
- Fix `BudgetListView`'s toolbar Add button being disabled exactly when its own empty-state message needed to be shown, making that message unreachable — found live during manual on-device verification; the button is now always enabled and `AddBudgetSheet`'s internal empty-state branch handles every case
- Fix `ImportViewModel.createAndAssignCategory` persisting the new category immediately, before the CSV import it belonged to had actually completed — cancelling out of the preview screen after tapping "Create" left a real, unused category behind. New categories are now staged in `pendingNewCategories` (still fully usable in the chip/menu UI via `allCategories`) and only written to the store by `startImport()`, before the transaction chunks that reference them — found via user testing of the live verification build, not by any automated test

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
