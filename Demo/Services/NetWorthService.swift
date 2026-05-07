import Foundation

struct NetWorthService {
    func netWorth(accounts: [(Account, [Transaction])], balanceService: BalanceService) -> Decimal {
        accounts
            .filter { !$0.0.isArchived }
            .reduce(Decimal.zero) { total, pair in
                total + balanceService.balance(for: pair.0, transactions: pair.1)
            }
    }
}
// Credit card balances are negative when debt is owed (BalanceService subtracts debits).
// Adding a negative balance correctly reduces net worth — no special liability case needed.
