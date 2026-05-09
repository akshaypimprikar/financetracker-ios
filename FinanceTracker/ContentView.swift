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
    @State private var importVM: ImportViewModel

    init(modelContext: ModelContext) {
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
        _importVM = State(wrappedValue: ImportViewModel(
            transactionRepo: transactionRepo,
            accountRepo: accountRepo,
            importRecordRepo: importRecordRepo
        ))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            NavigationStack {
                TransactionListView(viewModel: transactionVM, importVM: importVM)
            }
            .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }

            Text("Budgets — coming soon")
                .tabItem { Label("Budgets", systemImage: "target") }

            NavigationStack {
                AccountListView(viewModel: accountVM)
            }
            .tabItem { Label("Accounts", systemImage: "building.columns.fill") }

            Text("Settings — coming soon")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            try? accountVM.load()
            try? transactionVM.load()
            try? dashboardVM.load()
            try? importVM.load()
        }
    }
}
