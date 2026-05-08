import Foundation
import Observation

@Observable
final class AccountViewModel {
    private(set) var accounts: [Account] = []

    private let accountRepo: any AccountRepositoryProtocol
    private let transactionRepo: any TransactionRepositoryProtocol
    private let balanceService: BalanceService
    private let netWorthService: NetWorthService

    init(
        accountRepo: any AccountRepositoryProtocol,
        transactionRepo: any TransactionRepositoryProtocol,
        balanceService: BalanceService = BalanceService(),
        netWorthService: NetWorthService = NetWorthService()
    ) {
        self.accountRepo = accountRepo
        self.transactionRepo = transactionRepo
        self.balanceService = balanceService
        self.netWorthService = netWorthService
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
    }

    func balance(for account: Account) -> Decimal {
        let txs = (try? transactionRepo.fetch(for: account)) ?? []
        return balanceService.balance(for: account, transactions: txs)
    }

    func transactions(for account: Account) -> [Transaction] {
        (try? transactionRepo.fetch(for: account)) ?? []
    }

    func netWorth() -> Decimal {
        let pairs = accounts.map { ($0, (try? transactionRepo.fetch(for: $0)) ?? []) }
        return netWorthService.netWorth(accounts: pairs, balanceService: balanceService)
    }

    func addAccount(
        name: String,
        type: AccountType,
        currency: String,
        colorHex: String,
        icon: String,
        openingBalance: Decimal
    ) throws {
        let account = Account(name: name, type: type, currency: currency,
                              colorHex: colorHex, icon: icon,
                              openingBalance: openingBalance)
        try accountRepo.save(account)
        accounts = try accountRepo.fetchAll()
    }

    func delete(_ account: Account) throws {
        try accountRepo.delete(account)
        accounts = try accountRepo.fetchAll()
    }

    func archive(_ account: Account) throws {
        account.isArchived = true
        try accountRepo.save(account)
        accounts = try accountRepo.fetchAll()
    }
}
