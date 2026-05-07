import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee)
                    .font(.body)
                if let category = transaction.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(transaction.date,
                         format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: "USD"))
                .foregroundStyle(
                    transaction.type == .credit ? .green :
                    transaction.type == .transfer ? .blue : .primary
                )
        }
    }
}
