import Foundation

struct BalanceDataPoint: Identifiable {
    let id: UUID
    let date: Date
    let balance: Decimal

    init(date: Date, balance: Decimal) {
        self.id = UUID()
        self.date = date
        self.balance = balance
    }
}

struct BalanceService {
    func balance(for account: Account, transactions: [Transaction]) -> Decimal {
        var result = account.openingBalance
        for tx in transactions {
            switch tx.type {
            case .credit:
                result += tx.amount
            case .debit:
                result -= tx.amount
            case .transfer:
                if tx.account.id == account.id {
                    result -= tx.amount
                } else if tx.toAccount?.id == account.id {
                    result += tx.amount
                }
            }
        }
        return result
    }

    func runningBalance(for account: Account, transactions: [Transaction]) -> [BalanceDataPoint] {
        guard !transactions.isEmpty else { return [] }
        let sorted = transactions.sorted { $0.date < $1.date }
        var points: [BalanceDataPoint] = []
        var running = account.openingBalance
        // Anchor 1 second before the first transaction so chart IDs are always unique
        let anchorDate = sorted[0].date.addingTimeInterval(-1)
        points.append(BalanceDataPoint(date: anchorDate, balance: running))
        for tx in sorted {
            switch tx.type {
            case .credit:
                running += tx.amount
            case .debit:
                running -= tx.amount
            case .transfer:
                if tx.account.id == account.id {
                    running -= tx.amount
                } else if tx.toAccount?.id == account.id {
                    running += tx.amount
                }
            }
            points.append(BalanceDataPoint(date: tx.date, balance: running))
        }
        return points
    }
}
