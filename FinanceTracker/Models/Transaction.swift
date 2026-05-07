import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case debit
    case credit
    case transfer
}

@Model
final class Transaction {
    var id: UUID
    var date: Date
    var amount: Decimal
    var payee: String
    var notes: String?
    var type: TransactionType
    var importHash: String?
    var account: Account
    var toAccount: Account?
    var category: Category?

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Decimal,
        payee: String,
        notes: String? = nil,
        type: TransactionType,
        importHash: String? = nil,
        account: Account,
        toAccount: Account? = nil,
        category: Category? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.payee = payee
        self.notes = notes
        self.type = type
        self.importHash = importHash
        self.account = account
        self.toAccount = toAccount
        self.category = category
    }
}
