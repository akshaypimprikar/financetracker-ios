import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @Bindable var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Payee", value: transaction.payee)
                LabeledContent("Amount") {
                    Text(transaction.amount, format: .currency(code: transaction.account.currency))
                }
                LabeledContent("Date") {
                    Text(transaction.date,
                         format: .dateTime.month(.wide).day().year())
                }
                LabeledContent("Type", value: transaction.type.rawValue.capitalized)
                LabeledContent("Account", value: transaction.account.name)
                if let toAccount = transaction.toAccount {
                    LabeledContent("To Account", value: toAccount.name)
                }
                if let category = transaction.category {
                    LabeledContent("Category", value: category.name)
                }
                if let notes = transaction.notes, !notes.isEmpty {
                    LabeledContent("Notes", value: notes)
                }
                if let hash = transaction.importHash {
                    LabeledContent("Import ID") {
                        Text(hash.prefix(8) + "…")
                            .font(Theme.Typography.code)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", role: .destructive) {
                    try? viewModel.delete(transaction)
                    dismiss()
                }
            }
        }
    }
}
