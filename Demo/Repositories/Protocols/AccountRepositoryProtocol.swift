import Foundation

protocol AccountRepositoryProtocol {
    func fetchAll() throws -> [Account]
    func fetch(id: UUID) throws -> Account?
    func save(_ account: Account) throws
    func delete(_ account: Account) throws
}
