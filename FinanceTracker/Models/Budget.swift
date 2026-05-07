import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var monthlyLimit: Decimal
    var month: Date
    var category: Category

    init(
        id: UUID = UUID(),
        monthlyLimit: Decimal,
        month: Date,
        category: Category
    ) {
        self.id = id
        self.monthlyLimit = monthlyLimit
        self.month = month
        self.category = category
    }
}
