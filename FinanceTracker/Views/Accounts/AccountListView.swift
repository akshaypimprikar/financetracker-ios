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
        List {
            Section {
                HStack {
                    Text("Net Worth")
                    Spacer()
                    Text(viewModel.netWorth(),
                         format: .currency(code: "USD"))
                    .bold()
                    .foregroundStyle(viewModel.netWorth() >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
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
        HStack(spacing: 12) {
            Image(systemName: account.icon)
                .foregroundStyle(Color(hex: account.colorHex) ?? .accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(balance, format: .currency(code: account.currency))
                .bold()
                .foregroundStyle(balance >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
        }
    }
}
