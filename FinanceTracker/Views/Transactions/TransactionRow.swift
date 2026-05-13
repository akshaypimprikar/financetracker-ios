import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(transaction.payee)
                    .font(Theme.Typography.rowTitle)
                if let category = transaction.category {
                    Text(category.name)
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    Text(transaction.date,
                         format: .dateTime.month(.abbreviated).day())
                        .font(Theme.Typography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: transaction.account.currency))
                .foregroundStyle(
                    transaction.type == .credit ? Theme.Colors.positive :
                    transaction.type == .transfer ? Theme.Colors.transfer : .primary
                )
        }
    }
}
