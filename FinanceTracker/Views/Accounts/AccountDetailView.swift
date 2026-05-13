import SwiftUI

struct AccountDetailView: View {
    let account: Account
    @Bindable var viewModel: AccountViewModel

    var body: some View {
        let transactions = viewModel.transactions(for: account)
            .sorted { $0.date > $1.date }

        List {
            Section {
                HStack {
                    Text("Balance")
                    Spacer()
                    Text(viewModel.balance(for: account),
                         format: .currency(code: account.currency))
                    .bold()
                }
                HStack {
                    Text("Type")
                    Spacer()
                    Text(account.type.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Currency")
                    Spacer()
                    Text(account.currency)
                        .foregroundStyle(.secondary)
                }
            }

            if transactions.isEmpty {
                Section("Transactions") {
                    Text("No transactions yet")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Transactions") {
                    ForEach(transactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                Text(tx.payee)
                                Text(tx.date,
                                     format: .dateTime.month(.abbreviated).day().year())
                                    .font(Theme.Typography.rowSubtitle)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(tx.amount,
                                 format: .currency(code: account.currency))
                            .foregroundStyle(tx.type == .credit ? Theme.Colors.positive : .primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Archive") {
                    try? viewModel.archive(account)
                }
            }
        }
    }
}
