# FinanceTracker — Plan 2a: ViewModels + Core Screens

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up `@Observable` ViewModels to the repository layer and build the Dashboard, Accounts, and Transactions tabs so users can add accounts, add manual transactions, and see their net worth.

**Architecture:** Three `@Observable` ViewModels (Account, Dashboard, Transaction) hold all state and call repository protocols. `FinanceTrackerTabView` creates all repos once from `ModelContext` and passes them to each ViewModel via init. Views are pure layout — no business logic.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `@Observable` (Observation framework), Apple Testing (`@Suite` / `@Test` / `#expect`), Swift Charts (Plan 2b).

**All commands run from:** `/Users/akshaypimprikar/Desktop/FinanceTracker/FinanceTracker/` (the directory containing `FinanceTracker.xcodeproj`)

> **Simulator:** Always `iPhone 17` — iOS 26.4 only ships with iPhone 17.

> **File inclusion:** `PBXFileSystemSynchronizedRootGroup` — any `.swift` file placed inside `FinanceTracker/`, `FinanceTrackerTests/`, or `FinanceTrackerUITests/` compiles automatically. Never edit `project.pbxproj`.

> **This is Plan 2a of 3.** Plan 2b covers the CSV Import flow. Plan 2c covers Budgets + Settings + CategoryManager.

---

## File Map

### Create

```
FinanceTracker/
├── Extensions/
│   └── Color+Hex.swift
├── ViewModels/
│   ├── AccountViewModel.swift
│   ├── DashboardViewModel.swift
│   └── TransactionViewModel.swift
└── Views/
    ├── Accounts/
    │   ├── AccountListView.swift      (includes AccountRow)
    │   ├── AccountDetailView.swift
    │   └── AddAccountSheet.swift
    ├── Dashboard/
    │   └── DashboardView.swift        (includes BudgetProgressRow)
    └── Transactions/
        ├── TransactionRow.swift
        ├── TransactionListView.swift
        ├── AddTransactionSheet.swift
        └── TransactionDetailView.swift

FinanceTrackerTests/
├── TestHelpers.swift
└── ViewModels/
    ├── AccountViewModelTests.swift
    ├── DashboardViewModelTests.swift
    └── TransactionViewModelTests.swift
```

### Modify

```
FinanceTracker/ContentView.swift
    — replace tab text stubs with FinanceTrackerTabView
FinanceTrackerTests/Repositories/SwiftDataTransactionRepositoryTests.swift
    — remove local makeContainer() (replaced by shared TestHelpers.swift)
```

---

## Task 1: Shared test helpers

**Files:**
- Create: `FinanceTrackerTests/TestHelpers.swift`
- Modify: `FinanceTrackerTests/Repositories/SwiftDataTransactionRepositoryTests.swift`

- [ ] **Step 1: Create `FinanceTrackerTests/TestHelpers.swift`**

```swift
import Foundation
import SwiftData
@testable import FinanceTracker

func makeContainer() throws -> ModelContainer {
    let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
```

- [ ] **Step 2: Remove the duplicate `makeContainer()` from `SwiftDataTransactionRepositoryTests.swift`**

Open `FinanceTrackerTests/Repositories/SwiftDataTransactionRepositoryTests.swift` and delete these 4 lines:

```swift
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
```

The tests in that file call `makeContainer()` as a free function now — no other changes needed.

- [ ] **Step 3: Verify existing repository tests still pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/SwiftDataTransactionRepository \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 2 tests passed

- [ ] **Step 4: Commit**

```bash
git add FinanceTrackerTests/TestHelpers.swift \
        FinanceTrackerTests/Repositories/SwiftDataTransactionRepositoryTests.swift
git commit -m "refactor: extract shared makeContainer() into TestHelpers"
```

---

## Task 2: AccountViewModel

**Files:**
- Create: `FinanceTracker/ViewModels/AccountViewModel.swift`
- Create: `FinanceTrackerTests/ViewModels/AccountViewModelTests.swift`

- [ ] **Step 1: Create `FinanceTrackerTests/ViewModels/AccountViewModelTests.swift`**

```swift
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("AccountViewModel")
struct AccountViewModelTests {

    @Test func loadFetchesAllAccounts() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Checking", type: .checking))
        ctx.insert(Account(name: "Savings", type: .savings))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.accounts.count == 2)
    }

    @Test func balanceIncludesTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 100, payee: "Rent",
                               type: .debit, account: account))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.balance(for: account) == 400)
    }

    @Test func netWorthExcludesArchivedAccounts() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Active", type: .checking, openingBalance: 1000))
        ctx.insert(Account(name: "Archived", type: .savings,
                           openingBalance: 500, isArchived: true))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.netWorth() == 1000)
    }

    @Test func addAccountPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()
        #expect(vm.accounts.isEmpty)

        try vm.addAccount(name: "Savings", type: .savings, currency: "USD",
                          colorHex: "#56aeff", icon: "banknote", openingBalance: 250)

        #expect(vm.accounts.count == 1)
        #expect(vm.accounts[0].name == "Savings")
        #expect(vm.accounts[0].openingBalance == 250)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/AccountViewModel \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'AccountViewModel'`

- [ ] **Step 3: Create `FinanceTracker/ViewModels/AccountViewModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class AccountViewModel {
    private(set) var accounts: [Account] = []
    var errorMessage: String?

    private let accountRepo: any AccountRepositoryProtocol
    private let transactionRepo: any TransactionRepositoryProtocol
    private let balanceService: BalanceService
    private let netWorthService: NetWorthService

    init(
        accountRepo: any AccountRepositoryProtocol,
        transactionRepo: any TransactionRepositoryProtocol,
        balanceService: BalanceService = BalanceService(),
        netWorthService: NetWorthService = NetWorthService()
    ) {
        self.accountRepo = accountRepo
        self.transactionRepo = transactionRepo
        self.balanceService = balanceService
        self.netWorthService = netWorthService
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
    }

    func balance(for account: Account) -> Decimal {
        let txs = (try? transactionRepo.fetch(for: account)) ?? []
        return balanceService.balance(for: account, transactions: txs)
    }

    func transactions(for account: Account) -> [Transaction] {
        (try? transactionRepo.fetch(for: account)) ?? []
    }

    func netWorth() -> Decimal {
        let active = accounts.filter { !$0.isArchived }
        let pairs = active.map { ($0, (try? transactionRepo.fetch(for: $0)) ?? []) }
        return netWorthService.netWorth(accounts: pairs, balanceService: balanceService)
    }

    func addAccount(
        name: String,
        type: AccountType,
        currency: String,
        colorHex: String,
        icon: String,
        openingBalance: Decimal
    ) throws {
        let account = Account(name: name, type: type, currency: currency,
                              colorHex: colorHex, icon: icon,
                              openingBalance: openingBalance)
        try accountRepo.save(account)
        accounts = try accountRepo.fetchAll()
    }

    func delete(_ account: Account) throws {
        try accountRepo.delete(account)
        accounts = try accountRepo.fetchAll()
    }

    func archive(_ account: Account) throws {
        account.isArchived = true
        try accountRepo.save(account)
        accounts = try accountRepo.fetchAll()
    }
}
```

- [ ] **Step 4: Run tests — expect 4 pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/AccountViewModel \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 4 tests passed

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/ViewModels/AccountViewModel.swift \
        FinanceTrackerTests/ViewModels/AccountViewModelTests.swift
git commit -m "feat: add AccountViewModel with tests"
```

---

## Task 3: DashboardViewModel

**Files:**
- Create: `FinanceTracker/ViewModels/DashboardViewModel.swift`
- Create: `FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift`

- [ ] **Step 1: Create `FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift`**

```swift
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("DashboardViewModel")
struct DashboardViewModelTests {

    @Test func loadComputesNetWorth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking, openingBalance: 1000)
        let card = Account(name: "Card", type: .creditCard, openingBalance: -300)
        ctx.insert(checking)
        ctx.insert(card)
        ctx.insert(Transaction(date: .now, amount: 200, payee: "Rent",
                               type: .debit, account: checking))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        // checking: 1000 - 200 = 800, card: -300, total = 500
        #expect(vm.netWorth == 500)
    }

    @Test func spendingThisMonthSumsDebitsOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 50, payee: "Coffee",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 30, payee: "Salary",
                               type: .credit, account: account))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.spendingThisMonth == 50)
    }

    @Test func recentTransactionsLimitedToFive() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        for i in 1...7 {
            ctx.insert(Transaction(date: .now, amount: Decimal(i * 10),
                                   payee: "Tx \(i)", type: .debit, account: account))
        }
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.recentTransactions.count == 5)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/DashboardViewModel \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'DashboardViewModel'`

- [ ] **Step 3: Create `FinanceTracker/ViewModels/DashboardViewModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class DashboardViewModel {
    private(set) var netWorth: Decimal = 0
    private(set) var spendingThisMonth: Decimal = 0
    private(set) var recentTransactions: [Transaction] = []
    private(set) var budgetProgresses: [(Budget, BudgetProgress)] = []

    private let accountRepo: any AccountRepositoryProtocol
    private let transactionRepo: any TransactionRepositoryProtocol
    private let budgetRepo: any BudgetRepositoryProtocol
    private let balanceService: BalanceService
    private let netWorthService: NetWorthService
    private let budgetCalcService: BudgetCalculationService

    init(
        accountRepo: any AccountRepositoryProtocol,
        transactionRepo: any TransactionRepositoryProtocol,
        budgetRepo: any BudgetRepositoryProtocol,
        balanceService: BalanceService = BalanceService(),
        netWorthService: NetWorthService = NetWorthService(),
        budgetCalcService: BudgetCalculationService = BudgetCalculationService()
    ) {
        self.accountRepo = accountRepo
        self.transactionRepo = transactionRepo
        self.budgetRepo = budgetRepo
        self.balanceService = balanceService
        self.netWorthService = netWorthService
        self.budgetCalcService = budgetCalcService
    }

    func load() throws {
        let accounts = try accountRepo.fetchAll()
        let allTransactions = try transactionRepo.fetchAll()

        let pairs = accounts.filter { !$0.isArchived }.map { account in
            (account, allTransactions.filter { $0.account.id == account.id })
        }
        netWorth = netWorthService.netWorth(accounts: pairs, balanceService: balanceService)

        let calendar = Calendar.current
        let now = Date.now
        guard let startOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)),
              let endOfMonth = calendar.date(
                byAdding: DateComponents(month: 1), to: startOfMonth) else { return }

        spendingThisMonth = allTransactions
            .filter { $0.type == .debit && $0.date >= startOfMonth && $0.date < endOfMonth }
            .reduce(Decimal.zero) { $0 + $1.amount }

        recentTransactions = Array(
            allTransactions.sorted { $0.date > $1.date }.prefix(5)
        )

        let budgets = try budgetRepo.fetchAll(for: startOfMonth)
        budgetProgresses = budgets.map { budget in
            let txs = allTransactions.filter {
                $0.category?.id == budget.category.id &&
                $0.date >= startOfMonth && $0.date < endOfMonth
            }
            return (budget, budgetCalcService.progress(budget: budget, transactions: txs))
        }
    }
}
```

- [ ] **Step 4: Run tests — expect 3 pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/DashboardViewModel \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/ViewModels/DashboardViewModel.swift \
        FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift
git commit -m "feat: add DashboardViewModel with tests"
```

---

## Task 4: TransactionViewModel

**Files:**
- Create: `FinanceTracker/ViewModels/TransactionViewModel.swift`
- Create: `FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift`

- [ ] **Step 1: Create `FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift`**

```swift
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("TransactionViewModel")
struct TransactionViewModelTests {

    @Test func loadFetchesAllTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 1200, payee: "Rent",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.transactions.count == 2)
    }

    @Test func addTransactionPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        try vm.add(date: .now, amount: 50, payee: "Grocery", notes: nil,
                   type: .debit, account: account, toAccount: nil, category: nil)

        #expect(vm.transactions.count == 1)
        #expect(vm.transactions[0].payee == "Grocery")
    }

    @Test func searchTextFiltersPayee() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee Shop",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 50, payee: "Grocery Store",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.searchText = "coffee"

        #expect(vm.filteredTransactions.count == 1)
        #expect(vm.filteredTransactions[0].payee == "Coffee Shop")
    }

    @Test func selectedAccountFiltersTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking)
        let savings = Account(name: "Savings", type: .savings)
        ctx.insert(checking)
        ctx.insert(savings)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: checking))
        ctx.insert(Transaction(date: .now, amount: 100, payee: "Interest",
                               type: .credit, account: savings))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = checking

        #expect(vm.filteredTransactions.count == 1)
        #expect(vm.filteredTransactions[0].payee == "Coffee")
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/TransactionViewModel \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'TransactionViewModel'`

- [ ] **Step 3: Create `FinanceTracker/ViewModels/TransactionViewModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class TransactionViewModel {
    private(set) var transactions: [Transaction] = []
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    var searchText: String = ""
    var selectedAccount: Account?

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let categoryRepo: any CategoryRepositoryProtocol

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        categoryRepo: any CategoryRepositoryProtocol
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.categoryRepo = categoryRepo
    }

    func load() throws {
        transactions = try transactionRepo.fetchAll()
        accounts = try accountRepo.fetchAll()
        categories = try categoryRepo.fetchAll()
    }

    var filteredTransactions: [Transaction] {
        var result = transactions
        if !searchText.isEmpty {
            result = result.filter {
                $0.payee.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedAccount {
            result = result.filter { $0.account.id == selectedAccount.id }
        }
        return result.sorted { $0.date > $1.date }
    }

    func add(
        date: Date,
        amount: Decimal,
        payee: String,
        notes: String?,
        type: TransactionType,
        account: Account,
        toAccount: Account?,
        category: Category?
    ) throws {
        let tx = Transaction(
            date: date, amount: amount, payee: payee, notes: notes,
            type: type, account: account, toAccount: toAccount, category: category
        )
        try transactionRepo.save(tx)
        transactions = try transactionRepo.fetchAll()
    }

    func delete(_ transaction: Transaction) throws {
        try transactionRepo.delete(transaction)
        transactions = try transactionRepo.fetchAll()
    }
}
```

- [ ] **Step 4: Run tests — expect 4 pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/TransactionViewModel \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 4 tests passed

- [ ] **Step 5: Run full suite to confirm nothing broke**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add FinanceTracker/ViewModels/TransactionViewModel.swift \
        FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift
git commit -m "feat: add TransactionViewModel with filter/search and tests"
```

---

## Task 5: Wire ViewModels into ContentView

**Files:**
- Modify: `FinanceTracker/ContentView.swift`

- [ ] **Step 1: Replace the entire content of `FinanceTracker/ContentView.swift`**

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        FinanceTrackerTabView(modelContext: context)
    }
}

struct FinanceTrackerTabView: View {
    @State private var accountVM: AccountViewModel
    @State private var transactionVM: TransactionViewModel
    @State private var dashboardVM: DashboardViewModel

    init(modelContext: ModelContext) {
        let accountRepo = SwiftDataAccountRepository(context: modelContext)
        let transactionRepo = SwiftDataTransactionRepository(context: modelContext)
        let categoryRepo = SwiftDataCategoryRepository(context: modelContext)
        let budgetRepo = SwiftDataBudgetRepository(context: modelContext)

        _accountVM = State(wrappedValue: AccountViewModel(
            accountRepo: accountRepo,
            transactionRepo: transactionRepo
        ))
        _transactionVM = State(wrappedValue: TransactionViewModel(
            transactionRepo: transactionRepo,
            accountRepo: accountRepo,
            categoryRepo: categoryRepo
        ))
        _dashboardVM = State(wrappedValue: DashboardViewModel(
            accountRepo: accountRepo,
            transactionRepo: transactionRepo,
            budgetRepo: budgetRepo
        ))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            NavigationStack {
                TransactionListView(viewModel: transactionVM)
            }
            .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }

            Text("Budgets — coming in Plan 2c")
                .tabItem { Label("Budgets", systemImage: "target") }

            NavigationStack {
                AccountListView(viewModel: accountVM)
            }
            .tabItem { Label("Accounts", systemImage: "building.columns.fill") }

            Text("Settings — coming in Plan 2c")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            try? accountVM.load()
            try? transactionVM.load()
            try? dashboardVM.load()
        }
    }
}
```

- [ ] **Step 2: Verify build — will fail because views don't exist yet**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'DashboardView'` (and similar for AccountListView, TransactionListView). This is correct — the views will be created in Tasks 6–9.

- [ ] **Step 3: Commit the ContentView change (even though build fails)**

```bash
git add FinanceTracker/ContentView.swift
git commit -m "feat: wire ViewModels into FinanceTrackerTabView shell"
```

---

## Task 6: Color+Hex extension + AccountListView

**Files:**
- Create: `FinanceTracker/Extensions/Color+Hex.swift`
- Create: `FinanceTracker/Views/Accounts/AccountListView.swift`

- [ ] **Step 1: Create `FinanceTracker/Extensions/Color+Hex.swift`**

```swift
import SwiftUI

extension Color {
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Accounts/AccountListView.swift`**

```swift
import SwiftUI

struct AccountListView: View {
    @Bindable var viewModel: AccountViewModel
    @State private var isPresentingAdd = false

    private var assets: [Account] {
        viewModel.accounts.filter { !$0.type.isLiability && !$0.isArchived }
    }
    private var liabilities: [Account] {
        viewModel.accounts.filter { $0.type.isLiability && !$0.isArchived }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Net Worth")
                    Spacer()
                    Text(viewModel.netWorth(),
                         format: .currency(code: "USD"))
                    .bold()
                    .foregroundStyle(viewModel.netWorth() >= 0 ? .primary : .red)
                }
            }

            if !assets.isEmpty {
                Section("Assets") {
                    ForEach(assets) { account in
                        NavigationLink {
                            AccountDetailView(account: account, viewModel: viewModel)
                        } label: {
                            AccountRow(account: account,
                                       balance: viewModel.balance(for: account))
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(assets[index])
                        }
                    }
                }
            }

            if !liabilities.isEmpty {
                Section("Liabilities") {
                    ForEach(liabilities) { account in
                        NavigationLink {
                            AccountDetailView(account: account, viewModel: viewModel)
                        } label: {
                            AccountRow(account: account,
                                       balance: viewModel.balance(for: account))
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(liabilities[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddAccountSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Decimal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.icon)
                .foregroundStyle(Color(hex: account.colorHex) ?? .accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(balance, format: .currency(code: account.currency))
                .bold()
                .foregroundStyle(balance >= 0 ? .primary : .red)
        }
    }
}
```

- [ ] **Step 3: Verify build (still fails — AddAccountSheet and AccountDetailView missing)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:|BUILD" | head -5
```

Expected: errors about `AddAccountSheet`, `AccountDetailView`, `DashboardView`, `TransactionListView` — these all come in the next tasks.

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/Extensions/Color+Hex.swift \
        FinanceTracker/Views/Accounts/AccountListView.swift
git commit -m "feat: add AccountListView with asset/liability sections"
```

---

## Task 7: AddAccountSheet + AccountDetailView

**Files:**
- Create: `FinanceTracker/Views/Accounts/AddAccountSheet.swift`
- Create: `FinanceTracker/Views/Accounts/AccountDetailView.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Accounts/AddAccountSheet.swift`**

```swift
import SwiftUI

struct AddAccountSheet: View {
    @Bindable var viewModel: AccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = AccountType.checking
    @State private var currency = "USD"
    @State private var openingBalanceText = ""
    @State private var colorHex = "#4A90D9"
    @State private var icon = "banknote"

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    TextField("Currency (e.g. USD)", text: $currency)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Opening Balance") {
                    TextField("0.00", text: $openingBalanceText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let balance = Decimal(string: openingBalanceText) ?? 0
                        try? viewModel.addAccount(
                            name: name, type: type, currency: currency,
                            colorHex: colorHex, icon: icon,
                            openingBalance: balance
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Accounts/AccountDetailView.swift`**

```swift
import SwiftUI

struct AccountDetailView: View {
    let account: Account
    @Bindable var viewModel: AccountViewModel

    var body: some View {
        let transactions = viewModel.transactions(for: account)
            .sorted { $0.date > $1.date }

        List {
            Section {
                HStack {
                    Text("Balance")
                    Spacer()
                    Text(viewModel.balance(for: account),
                         format: .currency(code: account.currency))
                    .bold()
                }
                HStack {
                    Text("Type")
                    Spacer()
                    Text(account.type.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Currency")
                    Spacer()
                    Text(account.currency)
                        .foregroundStyle(.secondary)
                }
            }

            if transactions.isEmpty {
                Section("Transactions") {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Transactions") {
                    ForEach(transactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.payee)
                                Text(tx.date,
                                     format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(tx.amount,
                                 format: .currency(code: account.currency))
                            .foregroundStyle(tx.type == .credit ? .green : .primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Archive") {
                    try? viewModel.archive(account)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify build (still missing DashboardView and TransactionListView)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "error:" | grep -v "DashboardView\|TransactionListView" | head -5
```

Expected: no errors except the two remaining missing views.

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/Views/Accounts/AddAccountSheet.swift \
        FinanceTracker/Views/Accounts/AccountDetailView.swift
git commit -m "feat: add AddAccountSheet and AccountDetailView"
```

---

## Task 8: DashboardView

**Files:**
- Create: `FinanceTracker/Views/Transactions/TransactionRow.swift`
- Create: `FinanceTracker/Views/Dashboard/DashboardView.swift`

`TransactionRow` is defined first because `DashboardView` depends on it.

- [ ] **Step 1: Create `FinanceTracker/Views/Transactions/TransactionRow.swift`**

```swift
import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee)
                    .font(.body)
                if let category = transaction.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(transaction.date,
                         format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: "USD"))
                .foregroundStyle(
                    transaction.type == .credit ? .green :
                    transaction.type == .transfer ? .blue : .primary
                )
        }
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Dashboard/DashboardView.swift`**

```swift
import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                netWorthCard
                spendingCard

                if !viewModel.budgetProgresses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Budgets").font(.headline)
                        ForEach(viewModel.budgetProgresses, id: \.0.id) { budget, progress in
                            BudgetProgressCard(budget: budget, progress: progress)
                        }
                    }
                }

                if !viewModel.recentTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Transactions").font(.headline)
                        ForEach(viewModel.recentTransactions) { tx in
                            TransactionRow(transaction: tx)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .onAppear { try? viewModel.load() }
    }

    private var netWorthCard: some View {
        VStack(spacing: 4) {
            Text("Net Worth")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.netWorth, format: .currency(code: "USD"))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(viewModel.netWorth >= 0 ? .primary : .red)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.teal.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var spendingCard: some View {
        HStack {
            Text("Spent this month")
            Spacer()
            Text(viewModel.spendingThisMonth, format: .currency(code: "USD"))
                .bold()
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BudgetProgressCard: View {
    let budget: Budget
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(budget.category.name)
                    .font(.subheadline)
                Spacer()
                Text(progress.spent, format: .currency(code: "USD"))
                    .font(.subheadline.bold())
                Text("/ \(progress.limit.formatted(.currency(code: "USD")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Verify build (only TransactionListView missing now)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | head -5
```

Expected: only `error: cannot find type 'TransactionListView'`

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/Views/Transactions/TransactionRow.swift \
        FinanceTracker/Views/Dashboard/DashboardView.swift
git commit -m "feat: add DashboardView and TransactionRow"
```

---

## Task 9: TransactionListView

**Files:**
- Create: `FinanceTracker/Views/Transactions/TransactionListView.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Transactions/TransactionListView.swift`**

```swift
import SwiftUI

struct TransactionListView: View {
    @Bindable var viewModel: TransactionViewModel
    @State private var isPresentingAdd = false

    var body: some View {
        List {
            if !viewModel.accounts.isEmpty {
                accountFilterPicker
            }

            ForEach(viewModel.filteredTransactions) { tx in
                NavigationLink {
                    TransactionDetailView(transaction: tx, viewModel: viewModel)
                } label: {
                    TransactionRow(transaction: tx)
                }
            }
            .onDelete { indexSet in
                let txs = viewModel.filteredTransactions
                for index in indexSet {
                    try? viewModel.delete(txs[index])
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search payee")
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddTransactionSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }

    private var accountFilterPicker: some View {
        Picker("Account", selection: $viewModel.selectedAccount) {
            Text("All accounts").tag(nil as Account?)
            ForEach(viewModel.accounts) { account in
                Text(account.name).tag(account as Account?)
            }
        }
        .pickerStyle(.menu)
    }
}
```

- [ ] **Step 2: Verify build (AddTransactionSheet and TransactionDetailView still missing)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | head -5
```

Expected: errors for `AddTransactionSheet` and `TransactionDetailView` only.

- [ ] **Step 3: Commit**

```bash
git add FinanceTracker/Views/Transactions/TransactionListView.swift
git commit -m "feat: add TransactionListView with search and account filter"
```

---

## Task 10: AddTransactionSheet + TransactionDetailView

**Files:**
- Create: `FinanceTracker/Views/Transactions/AddTransactionSheet.swift`
- Create: `FinanceTracker/Views/Transactions/TransactionDetailView.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Transactions/AddTransactionSheet.swift`**

```swift
import SwiftUI

struct AddTransactionSheet: View {
    @Bindable var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var amountText = ""
    @State private var payee = ""
    @State private var notes = ""
    @State private var type = TransactionType.debit
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?

    private var isTransfer: Bool { type == .transfer }

    private var canAdd: Bool {
        !payee.trimmingCharacters(in: .whitespaces).isEmpty &&
        Decimal(string: amountText) != nil &&
        selectedAccount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date,
                               displayedComponents: .date)
                    TextField("Payee", text: $payee)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select account").tag(nil as Account?)
                        ForEach(viewModel.accounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    if isTransfer {
                        Picker("To Account", selection: $selectedToAccount) {
                            Text("Select account").tag(nil as Account?)
                            ForEach(viewModel.accounts.filter {
                                $0.id != selectedAccount?.id
                            }) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Uncategorized").tag(nil as Category?)
                            ForEach(viewModel.categories) { cat in
                                Text(cat.name).tag(cat as Category?)
                            }
                        }
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let account = selectedAccount,
                              let amount = Decimal(string: amountText) else { return }
                        try? viewModel.add(
                            date: date, amount: amount, payee: payee,
                            notes: notes.isEmpty ? nil : notes,
                            type: type, account: account,
                            toAccount: isTransfer ? selectedToAccount : nil,
                            category: isTransfer ? nil : selectedCategory
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .onAppear {
            selectedAccount = viewModel.accounts.first
        }
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Transactions/TransactionDetailView.swift`**

```swift
import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @Bindable var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Payee", value: transaction.payee)
                LabeledContent("Amount") {
                    Text(transaction.amount, format: .currency(code: "USD"))
                }
                LabeledContent("Date") {
                    Text(transaction.date,
                         format: .dateTime.month(.wide).day().year())
                }
                LabeledContent("Type", value: transaction.type.rawValue.capitalized)
                LabeledContent("Account", value: transaction.account.name)
                if let toAccount = transaction.toAccount {
                    LabeledContent("To Account", value: toAccount.name)
                }
                if let category = transaction.category {
                    LabeledContent("Category", value: category.name)
                }
                if let notes = transaction.notes, !notes.isEmpty {
                    LabeledContent("Notes", value: notes)
                }
                if let hash = transaction.importHash {
                    LabeledContent("Import ID") {
                        Text(hash.prefix(8) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", role: .destructive) {
                    try? viewModel.delete(transaction)
                    dismiss()
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify build succeeds**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run full test suite**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/Views/Transactions/AddTransactionSheet.swift \
        FinanceTracker/Views/Transactions/TransactionDetailView.swift
git commit -m "feat: add AddTransactionSheet and TransactionDetailView"
```

---

## Final Checklist

- [ ] `TestHelpers.swift` shared `makeContainer()` used by all test suites
- [ ] `AccountViewModel` — 4 tests passing
- [ ] `DashboardViewModel` — 3 tests passing
- [ ] `TransactionViewModel` — 4 tests passing
- [ ] `FinanceTrackerTabView` wires all three ViewModels from a single ModelContext
- [ ] `AccountListView` groups assets / liabilities, shows net worth, allows add + delete
- [ ] `AddAccountSheet` saves a new account via ViewModel
- [ ] `AccountDetailView` shows balance + transaction history + archive action
- [ ] `DashboardView` shows net worth, spending this month, budget progress cards, recent 5 transactions
- [ ] `TransactionListView` has search + account filter + add button
- [ ] `AddTransactionSheet` supports debit/credit/transfer with category/toAccount picker
- [ ] `TransactionDetailView` shows all fields + delete action
- [ ] Full `xcodebuild test` suite green
- [ ] No `Double` for money anywhere in new code
- [ ] No business logic in any View file

---

## What comes next

**Plan 2b — Import Flow:** `ImportViewModel` + the 3-step `ImportSheet` (file picker → column mapping → preview & confirm). Uses `CSVImportService` and `TransactionRepositoryProtocol.existsWithHash` for dedup.

**Plan 2c — Budgets + Settings:** `BudgetViewModel` + `BudgetListView` + `BudgetDetailView` + `AddBudgetSheet` + `SettingsView` + `CategoryManagerView`.
