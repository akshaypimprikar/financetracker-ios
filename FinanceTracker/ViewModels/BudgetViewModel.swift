import Foundation
import Observation

@Observable
final class BudgetViewModel {
    private(set) var budgets: [(Budget, BudgetProgress)] = []
    private(set) var categories: [Category] = []
    var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
    }()

    var currency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private let budgetRepo: any BudgetRepositoryProtocol
    private let transactionRepo: any TransactionRepositoryProtocol
    private let categoryRepo: any CategoryRepositoryProtocol
    private let budgetCalcService: BudgetCalculationService

    init(
        budgetRepo: any BudgetRepositoryProtocol,
        transactionRepo: any TransactionRepositoryProtocol,
        categoryRepo: any CategoryRepositoryProtocol,
        budgetCalcService: BudgetCalculationService = BudgetCalculationService()
    ) {
        self.budgetRepo = budgetRepo
        self.transactionRepo = transactionRepo
        self.categoryRepo = categoryRepo
        self.budgetCalcService = budgetCalcService
    }

    func load() throws {
        categories = try categoryRepo.fetchAll()
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let allBudgets = try budgetRepo.fetchAll(for: selectedMonth)
        let allTx = try transactionRepo.fetchAll()

        budgets = allBudgets.map { budget in
            let txs = allTx.filter {
                $0.category?.id == budget.category.id &&
                $0.date >= start && $0.date < end
            }
            return (budget, budgetCalcService.progress(budget: budget, transactions: txs))
        }
    }

    enum BudgetError: Error {
        case duplicateBudget
    }

    func add(category: Category, monthlyLimit: Decimal) throws {
        let cal = Calendar.current
        guard let month = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) else { return }
        if let _ = try budgetRepo.fetch(for: category, in: month) {
            throw BudgetError.duplicateBudget
        }
        let budget = Budget(monthlyLimit: monthlyLimit, month: month, category: category)
        try budgetRepo.save(budget)
        try load()
    }

    func delete(_ budget: Budget) throws {
        try budgetRepo.delete(budget)
        try load()
    }

    var unbudgetedCategories: [Category] {
        let budgetedIDs = Set(budgets.map { $0.0.category.id })
        return categories.filter { !budgetedIDs.contains($0.id) }
    }

    static let defaultSpendingHistoryMonths = 12
    var spendingHistoryMonths: Int = BudgetViewModel.defaultSpendingHistoryMonths

    func monthlySpendingHistory(for category: Category) -> [MonthlySpendingPoint] {
        let cal = Calendar.current
        let base = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        return (0..<spendingHistoryMonths).reversed().compactMap { offset -> MonthlySpendingPoint? in
            guard let month = cal.date(byAdding: .month, value: -offset, to: base) else { return nil }
            let txs = (try? transactionRepo.fetch(for: category, in: month)) ?? []
            let total = budgetCalcService.totalSpent(transactions: txs)
            return MonthlySpendingPoint(month: month, spent: total)
        }
    }
}
