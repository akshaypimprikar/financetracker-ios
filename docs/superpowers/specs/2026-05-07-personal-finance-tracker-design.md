# Personal Finance Tracker — Design Spec

**Date:** 2026-05-07  
**Status:** Approved  

---

## Overview

An iOS 26.4 personal finance app built with SwiftUI and SwiftData. Users track spending across multiple accounts (including credit cards as liabilities), set monthly budgets per category, and import transactions from CSV exports. The architecture is designed to swap the local SwiftData backend for a custom network backend in the future, and to eventually support ML-driven transaction recommendations.

---

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Transaction entry | Manual + CSV import | Bank sync deferred; import layer designed as a strategy so `BankSyncStrategy` can be added later |
| Account model | Multi-account, credit cards as liabilities | Double-entry awareness: net worth = assets − liabilities |
| Budgeting | Simple monthly budgets per category | Straightforward UX, testable business logic |
| Persistence | SwiftData local (iOS only) | Repository pattern abstracts storage so a network backend can be swapped in without touching ViewModels or services |
| Recurring transactions | Manual entry only now | App stores enough transaction metadata (payee, amount, date patterns) for a future ML recommendation layer |
| Data sync | None (local only) | iCloud CloudKit is a candidate future step before custom backend |

---

## Architecture

**Pattern:** MVVM + Repository

### Layers (top to bottom)

```
┌──────────────────────────────────────────────┐
│  Presentation — SwiftUI Views                │
│  DashboardView · TransactionListView         │
│  AddTransactionView · BudgetView             │
│  AccountsView · ImportView · SettingsView    │
├──────────────────────────────────────────────┤
│  ViewModel — @Observable classes             │
│  DashboardViewModel · TransactionViewModel   │
│  BudgetViewModel · AccountViewModel          │
│  ImportViewModel                             │
├──────────────────────────────────────────────┤
│  Domain Services — Pure Swift                │
│  BudgetCalculationService                    │
│  BalanceService · NetWorthService            │
│  CSVImportService · NotificationService      │
│  (no SwiftData imports — 100% unit testable) │
├──────────────────────────────────────────────┤
│  Repository — Protocol + SwiftData impl      │
│  AccountRepositoryProtocol                   │
│  TransactionRepositoryProtocol               │
│  BudgetRepositoryProtocol                    │
│  CategoryRepositoryProtocol                  │
│                                              │
│  Today: SwiftData*Repository implementations │
│  Future: Network*Repository / BankSync /ML   │
├──────────────────────────────────────────────┤
│  Data Models — SwiftData @Model              │
│  Account · Transaction · Category            │
│  Budget · ImportRecord                       │
└──────────────────────────────────────────────┘
```

**Layer rules (enforced by Review Agent):**
- Views contain no business logic
- Domain Services have zero SwiftData imports
- All money values use `Decimal`, never `Double`
- ViewModels depend on repository protocols, never concrete implementations

---

## Data Models

### Account
```swift
@Model class Account {
    var id: UUID
    var name: String
    var type: AccountType       // checking | savings | creditCard | cash | investment
    var currency: String        // ISO 4217, e.g. "USD" — display only, no conversion
    var colorHex: String
    var icon: String
    var isArchived: Bool
    var openingBalance: Decimal // set once at creation; BalanceService adds this to transaction sum
    @Relationship(deleteRule: .cascade) var transactions: [Transaction]
}
```
- `AccountType.creditCard` → liability (subtracted in net worth)
- All other types → asset (added in net worth)
- **Multi-currency:** all math is single-currency (no FX conversion). Currency field is for display labelling only. Multi-currency support is explicitly deferred.

### Transaction
```swift
@Model class Transaction {
    var id: UUID
    var date: Date
    var amount: Decimal
    var payee: String
    var notes: String?
    var type: TransactionType   // debit | credit | transfer
    var importHash: String?     // SHA256(date+amount+payee) for CSV dedup
    @Relationship var account: Account
    @Relationship var toAccount: Account?   // set only for transfer type
    @Relationship var category: Category?  // nullable — uncategorized allowed
}
```
- Transfers: `account` = source, `toAccount` = destination, no category needed
- Credit card payment = transfer from checking → creditCard (reduces liability)
- `importHash` prevents duplicate rows when same CSV is imported twice
- Payee + amount + date retained for future ML pattern analysis

### Category
```swift
@Model class Category {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var type: CategoryType      // income | expense
    @Relationship(deleteRule: .nullify) var transactions: [Transaction]
    @Relationship var budgets: [Budget]
}
```

### Budget
```swift
@Model class Budget {
    var id: UUID
    var monthlyLimit: Decimal
    var month: Date             // always the 1st of the month — used as key
    @Relationship var category: Category
}
```
- `BudgetCalculationService` joins Budget + Transactions filtered by category + month
- No direct relationship from Budget to Transaction — computed on read

### ImportRecord
```swift
@Model class ImportRecord {
    var id: UUID
    var filename: String
    var importedAt: Date
    var transactionCount: Int
    var source: String          // "CSV" today, "OFX" / "BankSync" later
}
```
- Audit trail only — no FK to Transaction (imports are immutable logs)

---

## Domain Services

### BudgetCalculationService
- `spending(for category: Category, in month: Date, transactions: [Transaction]) -> Decimal`
- `progress(budget: Budget, transactions: [Transaction]) -> BudgetProgress`
- `BudgetProgress`: spent, limit, remaining, isOverBudget
- Pure functions — no I/O, no side effects. Takes values, returns values.

### BalanceService
- `balance(for account: Account) -> Decimal`
- Sums all transaction amounts for the account respecting debit/credit/transfer direction

### NetWorthService
- `netWorth(accounts: [Account]) -> Decimal`
- Assets: sum of balances where type ≠ creditCard
- Liabilities: sum of balances where type == creditCard
- Net worth = assets − liabilities

### CSVImportService
- `parse(csv: String, mapping: ColumnMapping) -> [ParsedTransaction]`
- `deduplicatedRows(parsed: [ParsedTransaction], existing: [Transaction]) -> [ParsedTransaction]`
- `importHash(date: Date, amount: Decimal, payee: String) -> String`
- `ColumnMapping`: maps CSV column indices to date / amount / payee fields
- Auto-detects delimiter (comma, semicolon, tab)

### NotificationService
- `scheduleBudgetAlert(budget: Budget, progress: BudgetProgress)`
- Fires local notification at 80% and 100% of monthly limit
- Clears stale notifications when budget is updated
- **Trigger:** called by `BudgetViewModel` after every transaction save and after every CSV import completes. `NotificationService` is stateless — ViewModel passes current progress, service decides whether to fire.

---

## Navigation Structure

**Tab bar:** Dashboard · Transactions · Budgets · Accounts · Settings

### Dashboard Tab
- `DashboardView`: net worth total, spending this month, budget progress cards, recent 5 transactions
  - Push → `TransactionDetailView`

### Transactions Tab
- `TransactionListView`: filterable by account / category / date range, searchable by payee
  - Push → `TransactionDetailView` → sheet `EditTransactionSheet`
  - Sheet → `AddTransactionSheet` (amount, payee, account, category, transfer toggle)
  - Sheet → `ImportSheet` (3-step flow)

### Import Sheet — 3 steps
1. **File Picker** — `DocumentPicker` for CSV, auto-detect delimiter + headers
2. **Column Mapping** — map CSV columns to date / amount / payee fields
3. **Preview + Confirm** — parsed rows, duplicates highlighted, confirm to import

### Budgets Tab
- `BudgetListView`: month selector, progress bars, over-budget alerts
  - Push → `BudgetDetailView`: transactions for category this month + Swift Charts bar chart
  - Sheet → `AddBudgetSheet` (category, monthly limit, month)

### Accounts Tab
- `AccountListView`: net worth header, assets group, liabilities group, balance per account
  - Push → `AccountDetailView`: running balance, all transactions, Swift Charts line chart
  - Sheet → `AddAccountSheet` (name, type, currency, opening balance, color + icon)

### Settings Tab
- `SettingsView`: default currency, manage categories, export to CSV, about/version
  - Push → `CategoryManagerView`: create / edit / delete categories

---

## Multi-Agent Development Workflow

### Git Branching Model
- `main` — production, protected, merge via PR only, tagged on release
- `develop` — integration branch, CI runs on every push
- `feature/name` — off develop, one branch per feature
- `fix/name` — off develop (off main for hotfixes)
- `release/x.y.z` — off develop, merges to main + back to develop

### Agents

**1 — Spec Agent**
- Trigger: Feature idea in natural language
- Branch: `spec/feature-name`
- Output: `docs/superpowers/specs/YYYY-MM-DD-*.md`
- Responsibilities: explore codebase for existing patterns, ask clarifying questions, propose 2-3 approaches with tradeoffs, write full design spec, flag scope creep

**2 — Planner Agent**
- Trigger: Approved spec doc
- Branch: appends to `spec/feature-name`
- Output: `docs/superpowers/plans/YYYY-MM-DD-*.md`
- Responsibilities: read spec + codebase, identify files to create/modify, break into ordered tasks with dependencies, flag architecture risks

**3 — Feature Agent**
- Trigger: Approved implementation plan
- Branch: `feature/name` (off develop)
- Output: PR to develop
- Responsibilities: follow MVVM+Repository pattern, implement task-by-task with one commit per task, read CLAUDE.md before every file, run `xcodebuild` after each task, open PR when complete

**4 — Test Agent**
- Trigger: Feature branch ready (runs in parallel with Review Agent)
- Branch: same feature branch
- Output: test files pushed to PR
- Responsibilities: unit tests for all Domain Services, mock repositories for ViewModel tests, integration tests for Repository layer, UI tests for critical happy paths, target ≥80% coverage on new code

**5 — Review Agent**
- Trigger: PR opened
- Output: PR review comments (approve or request changes)
- Checks: architecture layer compliance, no business logic in Views, no SwiftData in Domain Services, no `Double` for money, test coverage for new services

**6 — Bug Fix Agent**
- Trigger: Bug report (description + reproduction steps)
- Branch: `fix/bug-name` (off develop, or main for hotfixes)
- Output: PR with fix + regression test
- Process: write failing test first → implement minimal fix → confirm test passes

**7 — Release Agent**
- Trigger: "ready to ship"
- Branch: `release/x.y.z` (off develop)
- Output: version bump + CHANGELOG.md + git tag + PR to main
- Checks: full test suite must be green, no TODO/FIXME in new code

### Lifecycle Orchestration

```
Idea → [Spec Agent] → ✅ You approve
     → [Planner Agent] → ✅ You approve
     → [Feature Agent] ∥ [Test Agent] → PR opened
     → [Review Agent] → ✅ Merge to develop
     → (repeat for more features)
     → [Release Agent] → main tagged + shipped

Bug report → [Bug Fix Agent] → PR → [Review Agent] → merge
```

You approve twice per feature: after the spec and after the plan. Everything else is agent-driven until you hit merge.

---

## Future Extension Points

| Feature | Where it plugs in |
|---|---|
| Bank sync / automatic import | New `BankSyncRepository` implementing `TransactionRepositoryProtocol` |
| ML transaction recommendations | New `MLRecommendationRepository`; transaction metadata (payee, amount, date) already stored |
| Custom backend / iCloud sync | Swap `SwiftData*Repository` implementations for `Network*Repository` |
| Recurring transaction detection | New `RecurringTransactionService` in Domain layer; no model changes needed |
| iCloud CloudKit sync | Add `CloudKit` configuration to `ModelContainer`; repository layer unchanged |

---

## Testing Strategy

- **Domain Services** — unit tested with XCTest, no simulator needed, no SwiftData dependency
- **Repositories** — integration tested against an in-memory `ModelContainer`
- **ViewModels** — unit tested with mock repository implementations injected via protocol
- **UI flows** — `DemoUITests` covers critical paths: add transaction, import CSV, budget alert
- **CI** — `xcodebuild test` on every push to `develop` and every PR
