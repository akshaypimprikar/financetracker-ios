# Changelog

All notable changes to FinanceTracker are documented here.

---

## [Unreleased]

### Added
- Multi-agent workflow: 8 slash commands in `.claude/commands/` (`/spec`, `/plan`, `/feature`, `/test`, `/review`, `/bugfix`, `/release`, `/sync-workflow`)
- Agent Workflow section in `CLAUDE.md` documenting the pipeline and per-agent enforcement rules
- `.gitignore` covering Xcode derived data, `.DS_Store`, Claude local files, and plugin cache

### Fixed
- Removed nested duplicate Xcode project structure that caused `PBXFileSystemSynchronizedRootGroup` to compile every Swift file twice
- Updated CLAUDE.md build directory from nested `FinanceTracker/FinanceTracker/` to the git root

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
