import Foundation

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
}
