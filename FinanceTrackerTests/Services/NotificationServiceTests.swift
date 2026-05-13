import Foundation
import Testing
@testable import FinanceTracker

@Suite("NotificationService")
struct NotificationServiceTests {

    private func makeBudget() -> Budget {
        let category = Category(name: "Groceries", type: .expense)
        return Budget(monthlyLimit: 100, month: .now, category: category)
    }

    @Test func scheduleBudgetAlertBelowThresholdDoesNotCrash() {
        let service = NotificationService()
        let budget = makeBudget()
        let progress = BudgetProgress(spent: 40, limit: 100) // 40% — no alert
        service.scheduleBudgetAlert(budget: budget, progress: progress)
    }

    @Test func scheduleBudgetAlertAt80PercentDoesNotCrash() {
        let service = NotificationService()
        let budget = makeBudget()
        let progress = BudgetProgress(spent: 85, limit: 100) // 85% — 80% alert
        service.scheduleBudgetAlert(budget: budget, progress: progress)
    }

    @Test func scheduleBudgetAlertAt100PercentDoesNotCrash() {
        let service = NotificationService()
        let budget = makeBudget()
        let progress = BudgetProgress(spent: 110, limit: 100) // 110% — over-budget alert
        service.scheduleBudgetAlert(budget: budget, progress: progress)
    }
}
