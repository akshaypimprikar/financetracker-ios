import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("BudgetCalculationService")
struct BudgetCalculationServiceTests {

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

    @Test func totalSpentSumsDebitsOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        let d1 = Transaction(date: .now, amount: 50, payee: "A", type: .debit, account: account)
        let d2 = Transaction(date: .now, amount: 30, payee: "B", type: .debit, account: account)
        ctx.insert(d1); ctx.insert(d2)

        let result = BudgetCalculationService().totalSpent(transactions: [d1, d2])
        #expect(result == 80)
    }

    @Test func totalSpentIgnoresCreditAndTransfer() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        let debit    = Transaction(date: .now, amount: 40,  payee: "Shop", type: .debit,    account: account)
        let credit   = Transaction(date: .now, amount: 100, payee: "Pay",  type: .credit,   account: account)
        let transfer = Transaction(date: .now, amount: 200, payee: "Move", type: .transfer, account: account)
        ctx.insert(debit); ctx.insert(credit); ctx.insert(transfer)

        let result = BudgetCalculationService().totalSpent(transactions: [debit, credit, transfer])
        #expect(result == 40)
    }

    @Test func totalSpentReturnsZeroForEmptyInput() {
        let result = BudgetCalculationService().totalSpent(transactions: [])
        #expect(result == Decimal.zero)
    }
}
