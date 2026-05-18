import Foundation

protocol TransactionRepositoryProtocol {
    func fetchAll() throws -> [Transaction]
    func fetch(for account: Account) throws -> [Transaction]
    func fetch(for category: Category, in month: Date) throws -> [Transaction]
    func fetchRecent(limit: Int) throws -> [Transaction]
    func existsWithHash(_ hash: String) throws -> Bool
    func save(_ transaction: Transaction) throws
    func delete(_ transaction: Transaction) throws
}
