import Foundation
import SwiftData

struct SwiftDataImportRecordRepository: ImportRecordRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [ImportRecord] {
        let descriptor = FetchDescriptor<ImportRecord>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ record: ImportRecord) throws {
        context.insert(record)
        try context.save()
    }

    func delete(_ record: ImportRecord) throws {
        context.delete(record)
        try context.save()
    }
}
