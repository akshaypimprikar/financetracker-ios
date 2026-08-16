import Foundation
import SwiftData

/// Seeds realistic sample data for screenshots and demos.
///
/// Only runs when the app is launched with `--seedscreenshots` (see
/// `FinanceTrackerApp`), which also forces an in-memory store the same way
/// `--uitesting` does — this never touches a real user's persisted data.
enum DemoDataSeeder {
    static func seed(into context: ModelContext) {
        let checking = Account(name: "Chase Checking", type: .checking, colorHex: "#4A90D9", icon: "building.columns", openingBalance: 3200)
        let savings = Account(name: "Ally Savings", type: .savings, colorHex: "#34C759", icon: "banknote", openingBalance: 12000)
        let creditCard = Account(name: "Chase Sapphire", type: .creditCard, colorHex: "#FF3B30", icon: "creditcard", openingBalance: 0)
        [checking, savings, creditCard].forEach { context.insert($0) }

        let categorySeeds: [(name: String, icon: String, color: String, type: CategoryType)] = [
            ("Groceries", "cart.fill", "#34C759", .expense),
            ("Dining", "fork.knife", "#FF9500", .expense),
            ("Transportation", "car.fill", "#5856D6", .expense),
            ("Rent", "house.fill", "#FF3B30", .expense),
            ("Utilities", "bolt.fill", "#FFCC00", .expense),
            ("Entertainment", "film.fill", "#AF52DE", .expense),
            ("Shopping", "bag.fill", "#FF2D55", .expense),
            ("Coffee", "cup.and.saucer.fill", "#A2845E", .expense),
            ("Salary", "dollarsign.circle.fill", "#34C759", .income),
        ]
        var categories: [String: Category] = [:]
        for seed in categorySeeds {
            let category = Category(name: seed.name, icon: seed.icon, colorHex: seed.color, type: seed.type)
            context.insert(category)
            categories[seed.name] = category
        }

        let calendar = Calendar.current
        let today = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let daysElapsed = max(calendar.dateComponents([.day], from: monthStart, to: today).day ?? 0, 0)
        func dateInMonth(_ offset: Int) -> Date {
            let clamped = min(offset, daysElapsed)
            return calendar.date(byAdding: .day, value: clamped, to: monthStart) ?? monthStart
        }

        let transactionSeeds: [(day: Int, amount: Decimal, payee: String, category: String, type: TransactionType, account: Account)] = [
            (1, 84.32, "Whole Foods Market", "Groceries", .debit, checking),
            (2, 6.75, "Blue Bottle Coffee", "Coffee", .debit, creditCard),
            (3, 45.00, "Shell Gas Station", "Transportation", .debit, checking),
            (4, 128.50, "Amazon", "Shopping", .debit, creditCard),
            (5, 32.10, "Chipotle", "Dining", .debit, creditCard),
            (7, 2200.00, "Landlord LLC", "Rent", .debit, checking),
            (8, 1850.00, "Acme Corp Payroll", "Salary", .credit, checking),
            (9, 15.99, "Netflix", "Entertainment", .debit, creditCard),
            (10, 62.40, "Trader Joe's", "Groceries", .debit, checking),
            (12, 5.25, "Blue Bottle Coffee", "Coffee", .debit, creditCard),
            (14, 95.00, "Uber", "Transportation", .debit, creditCard),
            (16, 210.00, "Best Buy", "Shopping", .debit, checking),
            (18, 48.60, "Olive Garden", "Dining", .debit, creditCard),
            (20, 140.00, "PG&E", "Utilities", .debit, checking),
            (22, 1850.00, "Acme Corp Payroll", "Salary", .credit, checking),
            (24, 55.20, "Whole Foods Market", "Groceries", .debit, checking),
            (26, 12.00, "AMC Theatres", "Entertainment", .debit, creditCard),
            (28, 38.75, "Sweetgreen", "Dining", .debit, creditCard),
        ]
        for seed in transactionSeeds {
            let transaction = Transaction(
                date: dateInMonth(seed.day),
                amount: seed.amount,
                payee: seed.payee,
                type: seed.type,
                account: seed.account,
                category: categories[seed.category]
            )
            context.insert(transaction)
        }

        let budgetSeeds: [(category: String, limit: Decimal)] = [
            ("Groceries", 500),
            ("Dining", 200),
            ("Transportation", 150),
            ("Entertainment", 100),
        ]
        for seed in budgetSeeds {
            guard let category = categories[seed.category] else { continue }
            context.insert(Budget(monthlyLimit: seed.limit, month: monthStart, category: category))
        }

        try? context.save()
    }
}
