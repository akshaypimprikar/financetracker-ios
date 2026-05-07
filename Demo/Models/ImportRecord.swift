import Foundation
import SwiftData

@Model
final class ImportRecord {
    var id: UUID
    var filename: String
    var importedAt: Date
    var transactionCount: Int
    var source: String

    init(
        id: UUID = UUID(),
        filename: String,
        importedAt: Date = Date(),
        transactionCount: Int,
        source: String = "CSV"
    ) {
        self.id = id
        self.filename = filename
        self.importedAt = importedAt
        self.transactionCount = transactionCount
        self.source = source
    }
}
