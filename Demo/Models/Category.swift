import Foundation
import SwiftData

enum CategoryType: String, Codable, CaseIterable {
    case income
    case expense
}

@Model
final class Category {
    var id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var type: CategoryType
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade, inverse: \Budget.category)
    var budgets: [Budget] = []

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tag.fill",
        colorHex: String = "#888888",
        type: CategoryType
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
}
