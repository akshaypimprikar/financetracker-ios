# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**FinanceTracker** — an iOS 26.4 personal finance app built with SwiftUI and SwiftData. Users track spending across multiple accounts (credit cards as liabilities), set monthly budgets per category, and import transactions from CSV exports.

## Build & Test Commands

All commands run from `/Users/akshaypimprikar/Desktop/FinanceTracker/FinanceTracker/` (the directory containing `FinanceTracker.xcodeproj`).

```bash
# Build
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'

# Run full test suite
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17'

# Run a single test suite (replace SuiteName with the @Suite struct name)
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/SuiteName

# Run a single test (replace SuiteName/testName)
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/SuiteName/testName
```

> **Simulator:** Always use `iPhone 17` — iOS 26.4 only ships with iPhone 17, not iPhone 16.

> **File inclusion:** This project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16). Any `.swift` file placed inside `FinanceTracker/`, `FinanceTrackerTests/`, or `FinanceTrackerUITests/` is **automatically compiled** — no `project.pbxproj` editing required.

## Architecture

**Pattern:** MVVM + Repository

### Layers (top → bottom)

```
Views (SwiftUI)
  ↓
ViewModels (@Observable)
  ↓
Domain Services (pure Swift — zero SwiftData imports)
  ↓
Repository Protocols (Foundation only)
  ↓
SwiftData Repositories (ModelContext injected)
  ↓
SwiftData @Model entities
```

### Layer Rules (enforced)

- **Views** contain no business logic
- **Domain Services** have **zero** SwiftData imports — 100% unit testable without a simulator
- **All money values** use `Decimal`, never `Double`
- **ViewModels** depend on repository protocols, never concrete SwiftData implementations

## Data Models (`FinanceTracker/Models/`)

| Model | Key fields |
|---|---|
| `Account` | `type: AccountType` (checking/savings/creditCard/cash/investment), `openingBalance: Decimal` |
| `Transaction` | `amount: Decimal`, `type: TransactionType` (debit/credit/transfer), `importHash: String?` |
| `Category` | `type: CategoryType` (income/expense) |
| `Budget` | `monthlyLimit: Decimal`, `month: Date` (always 1st of month) |
| `ImportRecord` | Audit log only — no FK to Transaction |

- `AccountType.creditCard` → liability (negative balance reduces net worth)
- `Transaction.importHash` = SHA256(date+amount+payee) for CSV dedup

## Domain Services (`FinanceTracker/Services/`)

| Service | Purpose |
|---|---|
| `BalanceService` | Computes account balance from `openingBalance` + transactions |
| `NetWorthService` | Sums all non-archived account balances (credit card debt is naturally negative) |
| `BudgetCalculationService` | Computes `BudgetProgress` (spent/limit/remaining/isOverBudget) |
| `CSVImportService` | Parses CSV, auto-detects delimiter, deduplicates via SHA256 hash |
| `NotificationService` | Fires local notifications at 80% and 100% of budget limit |

## Repository Protocols (`FinanceTracker/Repositories/Protocols/`)

All protocols import `Foundation` only. SwiftData implementations are in `FinanceTracker/Repositories/SwiftData/`.

## Test Targets

- `FinanceTrackerTests/` — unit + integration tests using Apple's `Testing` framework (`@Suite`, `@Test`, `#expect`)
- `FinanceTrackerUITests/` — UI automation via `XCTest`

**Test framework:** `import Testing` with `@Suite` / `@Test` / `#expect()` — NOT XCTest for unit tests.

## Navigation (Plan 2)

5-tab structure: **Dashboard · Transactions · Budgets · Accounts · Settings**
