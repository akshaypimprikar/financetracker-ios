import SwiftUI

struct TransactionListView: View {
    @Bindable var viewModel: TransactionViewModel
    @State private var isPresentingAdd = false

    var body: some View {
        List {
            if !viewModel.accounts.isEmpty {
                accountFilterPicker
            }

            ForEach(viewModel.filteredTransactions) { tx in
                NavigationLink {
                    TransactionDetailView(transaction: tx, viewModel: viewModel)
                } label: {
                    TransactionRow(transaction: tx)
                }
            }
            .onDelete { indexSet in
                let txs = viewModel.filteredTransactions
                for index in indexSet {
                    try? viewModel.delete(txs[index])
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search payee")
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddTransactionSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }

    private var accountFilterPicker: some View {
        Picker("Account", selection: $viewModel.selectedAccount) {
            Text("All accounts").tag(nil as Account?)
            ForEach(viewModel.accounts) { account in
                Text(account.name).tag(account as Account?)
            }
        }
        .pickerStyle(.menu)
    }
}
