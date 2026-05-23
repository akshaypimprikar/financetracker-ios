# Changelog

All notable changes to FinanceTracker are documented here.

---

## [Unreleased]

### Fixed
- **Chart UI tests** — corrected accessibility identifiers (`add-*-confirm`, `*-field`), removed wrong navigation assumption (tab switch preserves `AccountDetailView` in `NavigationStack`), skipped redundant Picker interaction in budget test (`onAppear` auto-selects first category)

### Added
- **`/design` agent** — bootstrap and extend modes; establishes `FinanceTracker/Theme/` token system before UI features are built; enforced via `/spec` (Design section) and `/review` (design compliance checklist)
- **Theme token system** — `Colors.swift`, `Spacing.swift`, `Typography.swift` with semantic tokens; all existing views refactored to use tokens
- **`Theme/Charts.swift`** — chart visualisation tokens: `balanceLine`, `balanceAreaFill`, `spendingBar`, `gridLine`, `minHeight`, `lineStrokeWidth`
- **`docs/design-system.md`** — canonical token reference and component pattern guide, now including Data Visualisation section with balance line and spending bar chart patterns
- **Theme unit tests** — 15 tests covering all color and spacing token values
- **PR checks CI** — GitHub Actions workflow running full test suite on every PR, with coverage enforcement (fail <60%, warn <80%)
- **Coverage enforcement** — `xccov` check in CI reports per-file line coverage; blocks PRs below 60%, warns below 80%
- **Pre-push git hook** — blocks direct pushes to `develop`/`main` and pushes to already-merged PR branches

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
