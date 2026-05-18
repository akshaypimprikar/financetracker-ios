import SwiftUI

struct TransactionListView: View {
    @Bindable var viewModel: TransactionViewModel
    @Bindable var importVM: ImportViewModel
    @State private var isPresentingAdd = false
    @State private var isPresentingImport = false

    var body: some View {
        List {
            if !viewModel.accounts.isEmpty {
                accountFilterPicker
            }

            if viewModel.filteredTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text(viewModel.searchText.isEmpty
                                      ? "Tap + to add your first transaction"
                                      : "No results for \"\(viewModel.searchText)\"")
                )
            } else {
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
        }
        .searchable(text: $viewModel.searchText, prompt: "Search payee")
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") {
                    isPresentingImport = true
                }
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
                    .accessibilityIdentifier("add-transaction-button")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddTransactionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportSheet(viewModel: importVM)
                .onDisappear { try? viewModel.load() }
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
