import Foundation

protocol CategoryRepositoryProtocol {
    func fetchAll() throws -> [Category]
    func fetch(id: UUID) throws -> Category?
    func save(_ category: Category) throws
    func delete(_ category: Category) throws
}
