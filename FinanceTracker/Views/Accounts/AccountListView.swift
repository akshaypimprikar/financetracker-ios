import SwiftUI

struct AccountListView: View {
    @Bindable var viewModel: AccountViewModel
    @State private var isPresentingAdd = false

    private var assets: [Account] {
        viewModel.accounts.filter { !$0.type.isLiability && !$0.isArchived }
    }
    private var liabilities: [Account] {
        viewModel.accounts.filter { $0.type.isLiability && !$0.isArchived }
    }

    var body: some View {
        let netWorth = viewModel.netWorth()
        List {
            Section {
                HStack {
                    Text("Net Worth")
                    Spacer()
                    Text(netWorth, format: .currency(code: viewModel.currency))
                        .bold()
                        .foregroundStyle(netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
                }
            }

            if !assets.isEmpty {
                Section("Assets") {
                    ForEach(assets) { account in
                        NavigationLink {
                            AccountDetailView(account: account, viewModel: viewModel)
                        } label: {
                            AccountRow(account: account,
                                       balance: viewModel.balance(for: account))
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(assets[index])
                        }
                    }
                }
            }

            if !liabilities.isEmpty {
                Section("Liabilities") {
                    ForEach(liabilities) { account in
                        NavigationLink {
                            AccountDetailView(account: account, viewModel: viewModel)
                        } label: {
                            AccountRow(account: account,
                                       balance: viewModel.balance(for: account))
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(liabilities[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
                    .accessibilityIdentifier("add-account-button")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddAccountSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Decimal

    var body: some View {
        HStack(spacing: Theme.Spacing.elementSpacing) {
            Image(systemName: account.icon)
                .foregroundStyle(Color(hex: account.colorHex) ?? Theme.Colors.primaryInteractive)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(account.name)
                Text(account.type.rawValue.capitalized)
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(balance, format: .currency(code: account.currency))
                .bold()
                .foregroundStyle(balance >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
        }
    }
}
