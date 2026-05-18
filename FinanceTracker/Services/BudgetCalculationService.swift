import Foundation

struct BudgetProgress {
    let spent: Decimal
    let limit: Decimal
    var remaining: Decimal { limit - spent }
    var isOverBudget: Bool { spent > limit }
    var percentUsed: Double { limit == 0 ? 0 : Double(truncating: (spent / limit) as NSDecimalNumber) }
}

struct MonthlySpendingPoint: Identifiable {
    let id: UUID
    let month: Date
    let spent: Decimal

    init(month: Date, spent: Decimal) {
        self.id = UUID()
        self.month = month
        self.spent = spent
    }
}

struct BudgetCalculationService {
    func progress(budget: Budget, transactions: [Transaction]) -> BudgetProgress {
        let spent = totalSpent(transactions: transactions)
        return BudgetProgress(spent: spent, limit: budget.monthlyLimit)
    }

    func totalSpent(transactions: [Transaction]) -> Decimal {
        transactions
            .filter { $0.type == .debit }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}
