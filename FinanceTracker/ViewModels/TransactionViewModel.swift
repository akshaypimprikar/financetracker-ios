import Foundation
import Observation

@Observable
final class TransactionViewModel {
    // Any new input to `filteredTransactions` below must invalidate the cache
    // here too, or it will silently return stale results.
    private(set) var transactions: [Transaction] = [] {
        didSet { invalidateFilteredTransactionsCache() }
    }
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    var searchText: String = "" {
        didSet { invalidateFilteredTransactionsCache() }
    }
    var selectedAccount: Account? {
        didSet { invalidateFilteredTransactionsCache() }
    }

    @ObservationIgnored private var cachedFilteredTransactions: [Transaction]?
    @ObservationIgnored private(set) var filterComputeCount = 0

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let categoryRepo: any CategoryRepositoryProtocol

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        categoryRepo: any CategoryRepositoryProtocol
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.categoryRepo = categoryRepo
    }

    func load() throws {
        transactions = try transactionRepo.fetchAll()
        accounts = try accountRepo.fetchAll()
        categories = try categoryRepo.fetchAll()
    }

    var filteredTransactions: [Transaction] {
        if let cachedFilteredTransactions {
            return cachedFilteredTransactions
        }
        filterComputeCount += 1
        var result = transactions
        if !searchText.isEmpty {
            result = result.filter {
                $0.payee.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedAccount {
            result = result.filter { $0.account.id == selectedAccount.id }
        }
        let sorted = result.sorted { $0.date > $1.date }
        cachedFilteredTransactions = sorted
        return sorted
    }

    private func invalidateFilteredTransactionsCache() {
        cachedFilteredTransactions = nil
    }

    func add(
        date: Date,
        amount: Decimal,
        payee: String,
        notes: String?,
        type: TransactionType,
        account: Account,
        toAccount: Account?,
        category: Category?
    ) throws {
        let tx = Transaction(
            date: date, amount: amount, payee: payee, notes: notes,
            type: type, account: account, toAccount: toAccount, category: category
        )
        try transactionRepo.save(tx)
        transactions = try transactionRepo.fetchAll()
    }

    func delete(_ transaction: Transaction) throws {
        try transactionRepo.delete(transaction)
        transactions = try transactionRepo.fetchAll()
    }
}
