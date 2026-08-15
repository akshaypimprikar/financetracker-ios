import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    let importActor: any TransactionImportWriting

    var body: some View {
        FinanceTrackerTabView(modelContext: context, importWriter: importActor)
    }
}

struct FinanceTrackerTabView: View {
    @State private var accountVM: AccountViewModel
    @State private var transactionVM: TransactionViewModel
    @State private var dashboardVM: DashboardViewModel
    @State private var budgetVM: BudgetViewModel
    @State private var importVM: ImportViewModel
    @State private var categoryVM: CategoryViewModel
    @State private var selectedTab: Int

    /// Screenshot tooling only: `--starttab=<name>` picks the initially
    /// selected tab so each screen can be captured with a fresh launch
    /// instead of scripted UI taps. No effect when the argument is absent.
    private static func initialTab() -> Int {
        guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--starttab=") }) else { return 0 }
        switch arg.replacingOccurrences(of: "--starttab=", with: "") {
        case "transactions": return 1
        case "budgets": return 2
        case "accounts": return 3
        case "settings": return 4
        default: return 0
        }
    }

    init(modelContext: ModelContext, importWriter: any TransactionImportWriting) {
        let accountRepo      = SwiftDataAccountRepository(context: modelContext)
        let transactionRepo  = SwiftDataTransactionRepository(context: modelContext)
        let categoryRepo     = SwiftDataCategoryRepository(context: modelContext)
        let budgetRepo       = SwiftDataBudgetRepository(context: modelContext)
        let importRecordRepo = SwiftDataImportRecordRepository(context: modelContext)

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
        _budgetVM = State(wrappedValue: BudgetViewModel(
            budgetRepo: budgetRepo,
            transactionRepo: transactionRepo,
            categoryRepo: categoryRepo
        ))
        _importVM = State(wrappedValue: ImportViewModel(
            accountRepo: accountRepo,
            importRecordRepo: importRecordRepo,
            importWriter: importWriter,
            categoryRepo: categoryRepo
        ))
        _categoryVM = State(wrappedValue: CategoryViewModel(
            categoryRepo: categoryRepo
        ))
        _selectedTab = State(wrappedValue: FinanceTrackerTabView.initialTab())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
            .tag(0)

            NavigationStack {
                TransactionListView(viewModel: transactionVM, importVM: importVM)
            }
            .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }
            .tag(1)

            NavigationStack {
                BudgetListView(viewModel: budgetVM, categoryVM: categoryVM)
            }
            .tabItem { Label("Budgets", systemImage: "target") }
            .tag(2)

            NavigationStack {
                AccountListView(viewModel: accountVM)
            }
            .tabItem { Label("Accounts", systemImage: "building.columns.fill") }
            .tag(3)

            NavigationStack {
                SettingsView(categoryVM: categoryVM)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(4)
        }
        .task {
            try? accountVM.load()
            try? transactionVM.load()
            try? dashboardVM.load()
            try? budgetVM.load()
            try? importVM.load()
            try? categoryVM.load()
        }
    }
}
