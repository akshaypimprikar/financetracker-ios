import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("BalanceService")
struct BalanceServiceTests {

    @Test func openingBalanceWithNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)

        let result = BalanceService().balance(for: account, transactions: [])
        #expect(result == 500)
    }

    @Test func debitReducesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 200, payee: "Rent", type: .debit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 800)
    }

    @Test func creditIncreasesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 0)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 3000, payee: "Salary", type: .credit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 3000)
    }

    @Test func transferReducesSourceAndIncreasesDestination() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking, openingBalance: 1000)
        let savings = Account(name: "Savings", type: .savings, openingBalance: 0)
        ctx.insert(checking)
        ctx.insert(savings)
        let tx = Transaction(date: .now, amount: 500, payee: "Transfer", type: .transfer, account: checking, toAccount: savings)
        ctx.insert(tx)

        let service = BalanceService()
        #expect(service.balance(for: checking, transactions: [tx]) == 500)
        #expect(service.balance(for: savings, transactions: [tx]) == 500)
    }

    @Test func runningBalanceReturnsEmptyForNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)

        let result = BalanceService().runningBalance(for: account, transactions: [])
        #expect(result.isEmpty)
    }

    @Test func runningBalanceFirstPointIsOpeningBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 200, payee: "Rent", type: .debit, account: account)
        ctx.insert(tx)

        let points = BalanceService().runningBalance(for: account, transactions: [tx])
        #expect(points.count == 2)
        #expect(points[0].balance == 1000)
    }

    @Test func runningBalanceAppliesDebitsCorrectly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 300, payee: "Groceries", type: .debit, account: account)
        ctx.insert(tx)

        let points = BalanceService().runningBalance(for: account, transactions: [tx])
        #expect(points.last?.balance == 700)
    }

    @Test func runningBalanceAppliesCreditsCorrectly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 0)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 2000, payee: "Salary", type: .credit, account: account)
        ctx.insert(tx)

        let points = BalanceService().runningBalance(for: account, transactions: [tx])
        #expect(points.last?.balance == 2000)
    }

    @Test func transferWithNilToAccountDoesNotCrash() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)
        // Transfer with no toAccount — should not crash and should debit source
        let tx = Transaction(date: .now, amount: 100, payee: "Transfer Out", type: .transfer,
                             account: account, toAccount: nil)
        ctx.insert(tx)

        let balance = BalanceService().balance(for: account, transactions: [tx])
        #expect(balance == 400)
    }

    @Test func runningBalanceSortsTransactionsByDate() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let later   = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 20))!
        let earlier = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let tx1 = Transaction(date: later,   amount: 200, payee: "Later",   type: .debit, account: account)
        let tx2 = Transaction(date: earlier, amount: 100, payee: "Earlier", type: .debit, account: account)
        ctx.insert(tx1); ctx.insert(tx2)

        let points = BalanceService().runningBalance(for: account, transactions: [tx1, tx2])
        #expect(points[0].balance == 1000)
        #expect(points[1].balance == 900)
        #expect(points[2].balance == 700)
    }
}
