import Foundation
import SwiftData

struct SwiftDataAccountRepository: AccountRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetchAllActive() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func save(_ account: Account) throws {
        context.insert(account)
        try context.save()
    }

    func delete(_ account: Account) throws {
        context.delete(account)
        try context.save()
    }
}
