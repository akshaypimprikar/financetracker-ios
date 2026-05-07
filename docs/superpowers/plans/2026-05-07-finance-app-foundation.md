# Personal Finance Tracker — Plan 1: Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the full architectural foundation — data models, repository protocols, SwiftData implementations, and all domain services with tests — so UI can be built on top in Plan 2.

**Architecture:** MVVM + Repository pattern. Domain Services are pure Swift with no SwiftData imports. Repositories are protocol-backed with SwiftData implementations today. All money values use `Decimal`, never `Double`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Apple Testing framework (`@Test` / `#expect`), CryptoKit (SHA256 for import dedup), UserNotifications

> **Note on file inclusion:** This project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16). Any `.swift` file created inside `Demo/Demo/`, `Demo/DemoTests/`, or `Demo/DemoUITests/` is automatically compiled — no `project.pbxproj` editing required.

> **This is Plan 1 of 3.** Plan 2 covers ViewModels + all UI screens. Plan 3 covers the multi-agent workflow command files.

**All commands run from:** `Demo/Demo/` (the directory containing `Demo.xcodeproj`)

---

## File Map

### Create

```
Demo/Demo/
├── Models/
│   ├── Account.swift
│   ├── Transaction.swift
│   ├── Category.swift
│   ├── Budget.swift
│   └── ImportRecord.swift
├── Repositories/
│   ├── Protocols/
│   │   ├── AccountRepositoryProtocol.swift
│   │   ├── TransactionRepositoryProtocol.swift
│   │   ├── CategoryRepositoryProtocol.swift
│   │   └── BudgetRepositoryProtocol.swift
│   └── SwiftData/
│       ├── SwiftDataAccountRepository.swift
│       ├── SwiftDataTransactionRepository.swift
│       ├── SwiftDataCategoryRepository.swift
│       └── SwiftDataBudgetRepository.swift
├── Services/
│   ├── BalanceService.swift
│   ├── NetWorthService.swift
│   ├── BudgetCalculationService.swift
│   ├── CSVImportService.swift
│   └── NotificationService.swift

DemoTests/
├── Services/
│   ├── BalanceServiceTests.swift
│   ├── NetWorthServiceTests.swift
│   ├── BudgetCalculationServiceTests.swift
│   └── CSVImportServiceTests.swift
└── Repositories/
    └── SwiftDataTransactionRepositoryTests.swift
```

### Modify

```
Demo/Demo/DemoApp.swift   — register all 5 models in ModelContainer
Demo/Demo/ContentView.swift — replace starter stub with tab bar shell
```

### Delete

```
Demo/Demo/Item.swift   — replaced by new models
```

---

## Task 1: Clean up starter files + create directory structure

**Files:**
- Delete: `Demo/Demo/Item.swift`
- Modify: `Demo/Demo/ContentView.swift`
- Create dirs: `Demo/Demo/Models/`, `Demo/Demo/Repositories/Protocols/`, `Demo/Demo/Repositories/SwiftData/`, `Demo/Demo/Services/`, `DemoTests/Services/`, `DemoTests/Repositories/`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p Demo/Models
mkdir -p Demo/Repositories/Protocols
mkdir -p Demo/Repositories/SwiftData
mkdir -p Demo/Services
mkdir -p DemoTests/Services
mkdir -p DemoTests/Repositories
```

- [ ] **Step 2: Delete Item.swift**

```bash
rm Demo/Item.swift
```

- [ ] **Step 3: Replace ContentView.swift with a tab bar shell**

Replace the entire content of `Demo/Demo/ContentView.swift` with:

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Dashboard")
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            Text("Transactions")
                .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }
            Text("Budgets")
                .tabItem { Label("Budgets", systemImage: "target") }
            Text("Accounts")
                .tabItem { Label("Accounts", systemImage: "building.columns.fill") }
            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 4: Verify build compiles**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Demo/ContentView.swift
git rm Demo/Item.swift
git commit -m "chore: clean up starter files, add tab shell + directory structure"
```

---

## Task 2: Account model

**Files:**
- Create: `Demo/Demo/Models/Account.swift`

- [ ] **Step 1: Create `Demo/Demo/Models/Account.swift`**

```swift
import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case creditCard
    case cash
    case investment

    var isLiability: Bool { self == .creditCard }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var currency: String
    var colorHex: String
    var icon: String
    var isArchived: Bool
    var openingBalance: Decimal
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currency: String = "USD",
        colorHex: String = "#4A90D9",
        icon: String = "creditcard",
        isArchived: Bool = false,
        openingBalance: Decimal = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.colorHex = colorHex
        self.icon = icon
        self.isArchived = isArchived
        self.openingBalance = openingBalance
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Demo/Models/Account.swift
git commit -m "feat: add Account SwiftData model"
```

---

## Task 3: Transaction model

**Files:**
- Create: `Demo/Demo/Models/Transaction.swift`

- [ ] **Step 1: Create `Demo/Demo/Models/Transaction.swift`**

```swift
import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case debit
    case credit
    case transfer
}

@Model
final class Transaction {
    var id: UUID
    var date: Date
    var amount: Decimal
    var payee: String
    var notes: String?
    var type: TransactionType
    var importHash: String?
    var account: Account
    var toAccount: Account?
    var category: Category?

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Decimal,
        payee: String,
        notes: String? = nil,
        type: TransactionType,
        importHash: String? = nil,
        account: Account,
        toAccount: Account? = nil,
        category: Category? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.payee = payee
        self.notes = notes
        self.type = type
        self.importHash = importHash
        self.account = account
        self.toAccount = toAccount
        self.category = category
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Demo/Models/Transaction.swift
git commit -m "feat: add Transaction SwiftData model"
```

---

## Task 4: Category, Budget, and ImportRecord models

**Files:**
- Create: `Demo/Demo/Models/Category.swift`
- Create: `Demo/Demo/Models/Budget.swift`
- Create: `Demo/Demo/Models/ImportRecord.swift`

- [ ] **Step 1: Create `Demo/Demo/Models/Category.swift`**

```swift
import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case income
    case expense
}

@Model
final class Category {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var type: CategoryType
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget] = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tag.fill",
        colorHex: String = "#888888",
        type: CategoryType
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
}
```

- [ ] **Step 2: Create `Demo/Demo/Models/Budget.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var monthlyLimit: Decimal
    var month: Date
    var category: Category

    init(
        id: UUID = UUID(),
        monthlyLimit: Decimal,
        month: Date,
        category: Category
    ) {
        self.id = id
        self.monthlyLimit = monthlyLimit
        self.month = month
        self.category = category
    }
}
```

- [ ] **Step 3: Create `Demo/Demo/Models/ImportRecord.swift`**

```swift
import Foundation
import SwiftData

@Model
final class ImportRecord {
    var id: UUID
    var filename: String
    var importedAt: Date
    var transactionCount: Int
    var source: String

    init(
        id: UUID = UUID(),
        filename: String,
        importedAt: Date = Date(),
        transactionCount: Int,
        source: String = "CSV"
    ) {
        self.id = id
        self.filename = filename
        self.importedAt = importedAt
        self.transactionCount = transactionCount
        self.source = source
    }
}
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Demo/Models/Category.swift Demo/Models/Budget.swift Demo/Models/ImportRecord.swift
git commit -m "feat: add Category, Budget, ImportRecord SwiftData models"
```

---

## Task 5: Update DemoApp.swift to register all models

**Files:**
- Modify: `Demo/Demo/DemoApp.swift`

- [ ] **Step 1: Replace `Demo/Demo/DemoApp.swift` with**

```swift
import SwiftUI
import SwiftData

@main
struct DemoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            Budget.self,
            ImportRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Demo/DemoApp.swift
git commit -m "feat: register all SwiftData models in ModelContainer"
```

---

## Task 6: Repository protocols

**Files:**
- Create: `Demo/Demo/Repositories/Protocols/AccountRepositoryProtocol.swift`
- Create: `Demo/Demo/Repositories/Protocols/TransactionRepositoryProtocol.swift`
- Create: `Demo/Demo/Repositories/Protocols/CategoryRepositoryProtocol.swift`
- Create: `Demo/Demo/Repositories/Protocols/BudgetRepositoryProtocol.swift`

- [ ] **Step 1: Create `Demo/Demo/Repositories/Protocols/AccountRepositoryProtocol.swift`**

```swift
import Foundation

protocol AccountRepositoryProtocol {
    func fetchAll() throws -> [Account]
    func fetch(id: UUID) throws -> Account?
    func save(_ account: Account) throws
    func delete(_ account: Account) throws
}
```

- [ ] **Step 2: Create `Demo/Demo/Repositories/Protocols/TransactionRepositoryProtocol.swift`**

```swift
import Foundation

protocol TransactionRepositoryProtocol {
    func fetchAll() throws -> [Transaction]
    func fetch(for account: Account) throws -> [Transaction]
    func fetch(for category: Category, in month: Date) throws -> [Transaction]
    func existsWithHash(_ hash: String) throws -> Bool
    func save(_ transaction: Transaction) throws
    func delete(_ transaction: Transaction) throws
}
```

- [ ] **Step 3: Create `Demo/Demo/Repositories/Protocols/CategoryRepositoryProtocol.swift`**

```swift
import Foundation

protocol CategoryRepositoryProtocol {
    func fetchAll() throws -> [Category]
    func fetch(id: UUID) throws -> Category?
    func save(_ category: Category) throws
    func delete(_ category: Category) throws
}
```

- [ ] **Step 4: Create `Demo/Demo/Repositories/Protocols/BudgetRepositoryProtocol.swift`**

```swift
import Foundation

protocol BudgetRepositoryProtocol {
    func fetchAll(for month: Date) throws -> [Budget]
    func fetch(for category: Category, in month: Date) throws -> Budget?
    func save(_ budget: Budget) throws
    func delete(_ budget: Budget) throws
}
```

- [ ] **Step 5: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Demo/Repositories/Protocols/
git commit -m "feat: add repository protocols for Account, Transaction, Category, Budget"
```

---

## Task 7: SwiftData Account and Category repositories

**Files:**
- Create: `Demo/Demo/Repositories/SwiftData/SwiftDataAccountRepository.swift`
- Create: `Demo/Demo/Repositories/SwiftData/SwiftDataCategoryRepository.swift`

- [ ] **Step 1: Create `Demo/Demo/Repositories/SwiftData/SwiftDataAccountRepository.swift`**

```swift
import Foundation
import SwiftData

struct SwiftDataAccountRepository: AccountRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ account: Account) throws {
        context.insert(account)
        try context.save()
    }

    func delete(_ account: Account) throws {
        context.delete(account)
        try context.save()
    }
}
```

- [ ] **Step 2: Create `Demo/Demo/Repositories/SwiftData/SwiftDataCategoryRepository.swift`**

```swift
import Foundation
import SwiftData

struct SwiftDataCategoryRepository: CategoryRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) throws -> Category? {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ category: Category) throws {
        context.insert(category)
        try context.save()
    }

    func delete(_ category: Category) throws {
        context.delete(category)
        try context.save()
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Demo/Repositories/SwiftData/SwiftDataAccountRepository.swift Demo/Repositories/SwiftData/SwiftDataCategoryRepository.swift
git commit -m "feat: add SwiftData implementations for Account and Category repositories"
```

---

## Task 8: SwiftData Transaction and Budget repositories

**Files:**
- Create: `Demo/Demo/Repositories/SwiftData/SwiftDataTransactionRepository.swift`
- Create: `Demo/Demo/Repositories/SwiftData/SwiftDataBudgetRepository.swift`
- Create: `DemoTests/Repositories/SwiftDataTransactionRepositoryTests.swift`

- [ ] **Step 1: Create `Demo/Demo/Repositories/SwiftData/SwiftDataTransactionRepository.swift`**

```swift
import Foundation
import SwiftData

struct SwiftDataTransactionRepository: TransactionRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(for account: Account) throws -> [Transaction] {
        let accountID = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account.id == accountID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(for category: Category, in month: Date) throws -> [Transaction] {
        let categoryID = category.id
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.category?.id == categoryID && $0.date >= start && $0.date < end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func existsWithHash(_ hash: String) throws -> Bool {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.importHash == hash }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    func save(_ transaction: Transaction) throws {
        context.insert(transaction)
        try context.save()
    }

    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }
}
```

- [ ] **Step 2: Create `Demo/Demo/Repositories/SwiftData/SwiftDataBudgetRepository.swift`**

```swift
import Foundation
import SwiftData

struct SwiftDataBudgetRepository: BudgetRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll(for month: Date) throws -> [Budget] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.month >= start && $0.month < end }
        )
        return try context.fetch(descriptor)
    }

    func fetch(for category: Category, in month: Date) throws -> Budget? {
        let categoryID = category.id
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate {
                $0.category.id == categoryID && $0.month >= start && $0.month < end
            }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ budget: Budget) throws {
        context.insert(budget)
        try context.save()
    }

    func delete(_ budget: Budget) throws {
        context.delete(budget)
        try context.save()
    }
}
```

- [ ] **Step 3: Write the failing integration test**

Create `DemoTests/Repositories/SwiftDataTransactionRepositoryTests.swift`:

```swift
import Testing
import SwiftData
@testable import Demo

@Suite("SwiftDataTransactionRepository")
struct SwiftDataTransactionRepositoryTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func fetchForAccountReturnsOnlyThatAccountsTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let accountA = Account(name: "Checking", type: .checking)
        let accountB = Account(name: "Savings", type: .savings)
        ctx.insert(accountA)
        ctx.insert(accountB)

        let txA = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, account: accountA)
        let txB = Transaction(date: .now, amount: 20, payee: "Salary", type: .credit, account: accountB)
        ctx.insert(txA)
        ctx.insert(txB)
        try ctx.save()

        let results = try repo.fetch(for: accountA)
        #expect(results.count == 1)
        #expect(results[0].payee == "Coffee")
    }

    @Test func existsWithHashReturnsTrueForDuplicate() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)

        let hash = "abc123"
        let tx = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, importHash: hash, account: account)
        try repo.save(tx)

        #expect(try repo.existsWithHash(hash) == true)
        #expect(try repo.existsWithHash("different") == false)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/SwiftDataTransactionRepositoryTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:|BUILD"
```

Expected: both tests pass

- [ ] **Step 5: Commit**

```bash
git add Demo/Repositories/SwiftData/ DemoTests/Repositories/
git commit -m "feat: add SwiftData implementations for Transaction and Budget repositories"
```

---

## Task 9: BalanceService

**Files:**
- Create: `Demo/Demo/Services/BalanceService.swift`
- Create: `DemoTests/Services/BalanceServiceTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `DemoTests/Services/BalanceServiceTests.swift`:

```swift
import Testing
import SwiftData
@testable import Demo

@Suite("BalanceService")
struct BalanceServiceTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test func openingBalanceWithNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)

        let result = BalanceService().balance(for: account, transactions: [])
        #expect(result == 500)
    }

    @Test func debitReducesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 200, payee: "Rent", type: .debit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 800)
    }

    @Test func creditIncreasesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 0)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 3000, payee: "Salary", type: .credit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 3000)
    }

    @Test func transferReducesSourceAndIncreasesDestination() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking, openingBalance: 1000)
        let savings = Account(name: "Savings", type: .savings, openingBalance: 0)
        ctx.insert(checking)
        ctx.insert(savings)
        let tx = Transaction(date: .now, amount: 500, payee: "Transfer", type: .transfer, account: checking, toAccount: savings)
        ctx.insert(tx)

        let service = BalanceService()
        #expect(service.balance(for: checking, transactions: [tx]) == 500)
        #expect(service.balance(for: savings, transactions: [tx]) == 500)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR (BalanceService does not exist yet)**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/BalanceServiceTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'BalanceService'`

- [ ] **Step 3: Create `Demo/Demo/Services/BalanceService.swift`**

```swift
import Foundation

struct BalanceService {
    func balance(for account: Account, transactions: [Transaction]) -> Decimal {
        var result = account.openingBalance
        for tx in transactions {
            switch tx.type {
            case .credit:
                result += tx.amount
            case .debit:
                result -= tx.amount
            case .transfer:
                if tx.account.id == account.id {
                    result -= tx.amount
                } else if tx.toAccount?.id == account.id {
                    result += tx.amount
                }
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/BalanceServiceTests 2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 4 tests passed, `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Demo/Services/BalanceService.swift DemoTests/Services/BalanceServiceTests.swift
git commit -m "feat: add BalanceService with tests"
```

---

## Task 10: NetWorthService

**Files:**
- Create: `Demo/Demo/Services/NetWorthService.swift`
- Create: `DemoTests/Services/NetWorthServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DemoTests/Services/NetWorthServiceTests.swift`:

```swift
import Testing
import SwiftData
@testable import Demo

@Suite("NetWorthService")
struct NetWorthServiceTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test func netWorthIsAssetsMinusLiabilities() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let balanceService = BalanceService()

        let checking = Account(name: "Checking", type: .checking, openingBalance: 2000)
        let savings = Account(name: "Savings", type: .savings, openingBalance: 5000)
        let creditCard = Account(name: "Visa", type: .creditCard, openingBalance: 0)
        ctx.insert(checking); ctx.insert(savings); ctx.insert(creditCard)

        // Credit card has a balance owed of 300
        let tx = Transaction(date: .now, amount: 300, payee: "Amazon", type: .debit, account: creditCard)
        ctx.insert(tx)

        let accounts: [(Account, [Transaction])] = [
            (checking, []),
            (savings, []),
            (creditCard, [tx])
        ]
        let result = NetWorthService().netWorth(accounts: accounts, balanceService: balanceService)
        // Assets: 2000 + 5000 = 7000
        // Liabilities: creditCard balance = 0 opening - 300 debit = -300 → owed = 300
        // Net worth: 7000 - 300 = 6700
        #expect(result == 6700)
    }

    @Test func netWorthWithNoAccountsIsZero() {
        let result = NetWorthService().netWorth(accounts: [], balanceService: BalanceService())
        #expect(result == 0)
    }

    @Test func archivedAccountsAreExcluded() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let active = Account(name: "Active", type: .checking, openingBalance: 1000)
        let archived = Account(name: "Old", type: .savings, openingBalance: 500, isArchived: true)
        ctx.insert(active); ctx.insert(archived)

        let accounts: [(Account, [Transaction])] = [(active, []), (archived, [])]
        let result = NetWorthService().netWorth(accounts: accounts, balanceService: BalanceService())
        #expect(result == 1000)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/NetWorthServiceTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'NetWorthService'`

- [ ] **Step 3: Create `Demo/Demo/Services/NetWorthService.swift`**

```swift
import Foundation

struct NetWorthService {
    func netWorth(accounts: [(Account, [Transaction])], balanceService: BalanceService) -> Decimal {
        accounts
            .filter { !$0.0.isArchived }
            .reduce(Decimal.zero) { total, pair in
                total + balanceService.balance(for: pair.0, transactions: pair.1)
            }
    }
}
// Credit card balances are negative when debt is owed (BalanceService subtracts debits).
// Adding a negative balance to net worth correctly reduces it — no special liability handling needed.
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/NetWorthServiceTests 2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add Demo/Services/NetWorthService.swift DemoTests/Services/NetWorthServiceTests.swift
git commit -m "feat: add NetWorthService with tests"
```

---

## Task 11: BudgetCalculationService

**Files:**
- Create: `Demo/Demo/Services/BudgetCalculationService.swift`
- Create: `DemoTests/Services/BudgetCalculationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DemoTests/Services/BudgetCalculationServiceTests.swift`:

```swift
import Testing
import SwiftData
@testable import Demo

@Suite("BudgetCalculationService")
struct BudgetCalculationServiceTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func makeMay2026() -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 1
        return Calendar.current.date(from: comps)!
    }

    @Test func spentIsZeroWithNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 500, month: makeMay2026(), category: category)
        ctx.insert(category); ctx.insert(budget)

        let progress = BudgetCalculationService().progress(budget: budget, transactions: [])
        #expect(progress.spent == 0)
        #expect(progress.limit == 500)
        #expect(progress.remaining == 500)
        #expect(progress.isOverBudget == false)
    }

    @Test func spentSumsDebitsOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let account = Account(name: "Checking", type: .checking)
        let budget = Budget(monthlyLimit: 200, month: makeMay2026(), category: category)
        ctx.insert(category); ctx.insert(account); ctx.insert(budget)

        let tx1 = Transaction(date: makeMay2026(), amount: 80, payee: "Grocery", type: .debit, account: account, category: category)
        let tx2 = Transaction(date: makeMay2026(), amount: 50, payee: "Restaurant", type: .debit, account: account, category: category)
        ctx.insert(tx1); ctx.insert(tx2)

        let progress = BudgetCalculationService().progress(budget: budget, transactions: [tx1, tx2])
        #expect(progress.spent == 130)
        #expect(progress.remaining == 70)
        #expect(progress.isOverBudget == false)
    }

    @Test func isOverBudgetWhenSpentExceedsLimit() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let account = Account(name: "Checking", type: .checking)
        let budget = Budget(monthlyLimit: 100, month: makeMay2026(), category: category)
        ctx.insert(category); ctx.insert(account); ctx.insert(budget)

        let tx = Transaction(date: makeMay2026(), amount: 150, payee: "Grocery", type: .debit, account: account, category: category)
        ctx.insert(tx)

        let progress = BudgetCalculationService().progress(budget: budget, transactions: [tx])
        #expect(progress.isOverBudget == true)
        #expect(progress.remaining == -50)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/BudgetCalculationServiceTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'BudgetCalculationService'`

- [ ] **Step 3: Create `Demo/Demo/Services/BudgetCalculationService.swift`**

```swift
import Foundation

struct BudgetProgress {
    let spent: Decimal
    let limit: Decimal
    var remaining: Decimal { limit - spent }
    var isOverBudget: Bool { spent > limit }
    var percentUsed: Double { limit == 0 ? 0 : Double(truncating: (spent / limit) as NSDecimalNumber) }
}

struct BudgetCalculationService {
    func progress(budget: Budget, transactions: [Transaction]) -> BudgetProgress {
        let spent = transactions
            .filter { $0.type == .debit }
            .reduce(Decimal.zero) { $0 + $1.amount }
        return BudgetProgress(spent: spent, limit: budget.monthlyLimit)
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/BudgetCalculationServiceTests 2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add Demo/Services/BudgetCalculationService.swift DemoTests/Services/BudgetCalculationServiceTests.swift
git commit -m "feat: add BudgetCalculationService with BudgetProgress and tests"
```

---

## Task 12: CSVImportService

**Files:**
- Create: `Demo/Demo/Services/CSVImportService.swift`
- Create: `DemoTests/Services/CSVImportServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `DemoTests/Services/CSVImportServiceTests.swift`:

```swift
import Testing
import CryptoKit
@testable import Demo

@Suite("CSVImportService")
struct CSVImportServiceTests {

    @Test func parsesCommaDelimitedCSV() throws {
        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee Shop
        2026-05-02,1200.00,Rent
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 2)
        #expect(results[0].payee == "Coffee Shop")
        #expect(results[0].amount == Decimal(string: "25.50"))
        #expect(results[1].payee == "Rent")
    }

    @Test func parsesSemicolonDelimitedCSV() throws {
        let csv = "date;amount;payee\n2026-05-01;50.00;Supermarket"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 1)
        #expect(results[0].payee == "Supermarket")
    }

    @Test func deduplicatesRowsWithMatchingHashes() throws {
        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee Shop
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let parsed = try CSVImportService().parse(csv: csv, mapping: mapping)
        let hash = parsed[0].importHash

        let results = CSVImportService().deduplicated(parsed: parsed, existingHashes: Set([hash]))
        #expect(results.isEmpty)
    }

    @Test func importHashIsDeterministic() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let hash1 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        let hash2 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        #expect(hash1 == hash2)
    }

    @Test func importHashDiffersForDifferentInputs() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let hash1 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        let hash2 = CSVImportService.importHash(date: date, amount: 26, payee: "Coffee")
        #expect(hash1 != hash2)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/CSVImportServiceTests 2>&1 | grep -E "error:|BUILD"
```

Expected: `error: cannot find type 'CSVImportService'`

- [ ] **Step 3: Create `Demo/Demo/Services/CSVImportService.swift`**

```swift
import Foundation
import CryptoKit

struct ParsedTransaction {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
}

struct ColumnMapping {
    let dateIndex: Int
    let amountIndex: Int
    let payeeIndex: Int
    let hasHeader: Bool
}

struct CSVImportService {
    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"].map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    func parse(csv: String, mapping: ColumnMapping) throws -> [ParsedTransaction] {
        let delimiter: Character = csv.contains(";") ? ";" : ","
        var lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if mapping.hasHeader && !lines.isEmpty { lines.removeFirst() }

        return try lines.compactMap { line -> ParsedTransaction? in
            let columns = line.components(separatedBy: String(delimiter)).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard columns.count > max(mapping.dateIndex, mapping.amountIndex, mapping.payeeIndex) else { return nil }
            guard let date = Self.parseDate(columns[mapping.dateIndex]) else { return nil }
            guard let amount = Decimal(string: columns[mapping.amountIndex]) else { return nil }
            let payee = columns[mapping.payeeIndex]
            return ParsedTransaction(
                date: date,
                amount: amount,
                payee: payee,
                importHash: Self.importHash(date: date, amount: amount, payee: payee)
            )
        }
    }

    func deduplicated(parsed: [ParsedTransaction], existingHashes: Set<String>) -> [ParsedTransaction] {
        parsed.filter { !existingHashes.contains($0.importHash) }
    }

    static func importHash(date: Date, amount: Decimal, payee: String) -> String {
        let input = "\(Int(date.timeIntervalSince1970))-\(amount)-\(payee.lowercased().trimmingCharacters(in: .whitespaces))"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatters.lazy.compactMap { $0.date(from: string) }.first
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:DemoTests/CSVImportServiceTests 2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 5 tests passed

- [ ] **Step 5: Commit**

```bash
git add Demo/Services/CSVImportService.swift DemoTests/Services/CSVImportServiceTests.swift
git commit -m "feat: add CSVImportService with SHA256 dedup and tests"
```

---

## Task 13: NotificationService

**Files:**
- Create: `Demo/Demo/Services/NotificationService.swift`

- [ ] **Step 1: Create `Demo/Demo/Services/NotificationService.swift`**

```swift
import Foundation
import UserNotifications

struct NotificationService {
    func scheduleBudgetAlert(budget: Budget, progress: BudgetProgress) {
        let center = UNUserNotificationCenter.current()
        let categoryName = budget.category.name

        // Remove any stale alerts for this budget before rescheduling
        let identifiers = [
            "budget-80-\(budget.id)",
            "budget-100-\(budget.id)"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        if progress.percentUsed >= 1.0 {
            schedule(center: center,
                     id: "budget-100-\(budget.id)",
                     title: "Budget exceeded",
                     body: "You've gone over your \(categoryName) budget.")
        } else if progress.percentUsed >= 0.8 {
            schedule(center: center,
                     id: "budget-80-\(budget.id)",
                     title: "Budget at 80%",
                     body: "You've used 80% of your \(categoryName) budget.")
        }
    }

    private func schedule(center: UNUserNotificationCenter, id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project Demo.xcodeproj -scheme Demo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test -project Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: all tests pass, `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Demo/Services/NotificationService.swift
git commit -m "feat: add NotificationService for budget threshold alerts"
```

---

## Final checklist

- [ ] All 5 models compile with no warnings
- [ ] All 4 repository protocols defined with correct method signatures
- [ ] All 4 SwiftData repository implementations compile
- [ ] `BalanceService` — 4 tests passing
- [ ] `NetWorthService` — 3 tests passing
- [ ] `BudgetCalculationService` — 3 tests passing
- [ ] `CSVImportService` — 5 tests passing
- [ ] `SwiftDataTransactionRepository` — 2 integration tests passing
- [ ] Full `xcodebuild test` suite green
- [ ] All commits on `develop` branch (or `feature/foundation` if using feature branching)

---

## What comes next

**Plan 2 — UI Features:** ViewModels (`@Observable`) for each tab, all SwiftUI screens, navigation structure (TabView + NavigationStack), AddTransaction/Import sheets.

**Plan 3 — Multi-Agent Workflow:** Claude Code command files (`.claude/commands/spec.md`, `plan.md`, `feature.md`, `test.md`, `review.md`, `bugfix.md`, `release.md`), updated `CLAUDE.md` with architecture enforcement rules for agents.
