import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case creditCard
    case cash
    case investment

    var isLiability: Bool { self == .creditCard }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var type: AccountType
    var currency: String
    var colorHex: String
    var icon: String
    var isArchived: Bool
    var openingBalance: Decimal
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currency: String = "USD",
        colorHex: String = "#4A90D9",
        icon: String = "creditcard",
        isArchived: Bool = false,
        openingBalance: Decimal = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.colorHex = colorHex
        self.icon = icon
        self.isArchived = isArchived
        self.openingBalance = openingBalance
    }
}
