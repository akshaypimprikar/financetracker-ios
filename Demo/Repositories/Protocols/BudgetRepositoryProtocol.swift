import Foundation

protocol BudgetRepositoryProtocol {
    func fetchAll(for month: Date) throws -> [Budget]
    func fetch(for category: Category, in month: Date) throws -> Budget?
    func save(_ budget: Budget) throws
    func delete(_ budget: Budget) throws
}
