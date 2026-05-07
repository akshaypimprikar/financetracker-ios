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
