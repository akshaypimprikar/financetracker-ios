import Foundation
import Observation

struct CategorySpending: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let amount: Decimal
}

@Observable
final class DashboardViewModel {
    private(set) var netWorth: Decimal = 0
    private(set) var spendingThisMonth: Decimal = 0
    private(set) var categorySpending: [CategorySpending] = []
    private(set) var recentTransactions: [Transaction] = []
    private(set) var budgetProgresses: [(Budget, BudgetProgress)] = []
    private(set) var currency: String = "USD"

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

        let activeAccounts = accounts.filter { !$0.isArchived }
        currency = activeAccounts.first?.currency ?? "USD"

        let pairs = activeAccounts.map { account in
            (account, allTransactions.filter { $0.account.id == account.id })
        }
        netWorth = netWorthService.netWorth(accounts: pairs, balanceService: balanceService)

        let calendar = Calendar.current
        let now = Date.now
        guard let startOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)),
              let endOfMonth = calendar.date(
                byAdding: DateComponents(month: 1), to: startOfMonth) else { return }

        let thisMonthDebits = allTransactions
            .filter { $0.type == .debit && $0.date >= startOfMonth && $0.date < endOfMonth }
        spendingThisMonth = budgetCalcService.totalSpent(transactions: thisMonthDebits)

        let categorizedDebits = thisMonthDebits.filter { $0.category != nil }
        let groupedByCategory = Dictionary(grouping: categorizedDebits) { $0.category!.id }
        categorySpending = groupedByCategory.values.map { transactions in
            CategorySpending(
                category: transactions[0].category!,
                amount: budgetCalcService.totalSpent(transactions: transactions)
            )
        }

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
