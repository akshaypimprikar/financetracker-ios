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
