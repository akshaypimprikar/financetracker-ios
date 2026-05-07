import SwiftUI

struct AddTransactionSheet: View {
    @Bindable var viewModel: TransactionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var amountText = ""
    @State private var payee = ""
    @State private var notes = ""
    @State private var type = TransactionType.debit
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?

    private var isTransfer: Bool { type == .transfer }

    private var canAdd: Bool {
        !payee.trimmingCharacters(in: .whitespaces).isEmpty &&
        Decimal(string: amountText) != nil &&
        selectedAccount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date,
                               displayedComponents: .date)
                    TextField("Payee", text: $payee)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select account").tag(nil as Account?)
                        ForEach(viewModel.accounts) { account in
                            Text(account.name).tag(account as Account?)
                        }
                    }
                    if isTransfer {
                        Picker("To Account", selection: $selectedToAccount) {
                            Text("Select account").tag(nil as Account?)
                            ForEach(viewModel.accounts.filter {
                                $0.id != selectedAccount?.id
                            }) { account in
                                Text(account.name).tag(account as Account?)
                            }
                        }
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Uncategorized").tag(nil as Category?)
                            ForEach(viewModel.categories) { cat in
                                Text(cat.name).tag(cat as Category?)
                            }
                        }
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let account = selectedAccount,
                              let amount = Decimal(string: amountText) else { return }
                        try? viewModel.add(
                            date: date, amount: amount, payee: payee,
                            notes: notes.isEmpty ? nil : notes,
                            type: type, account: account,
                            toAccount: isTransfer ? selectedToAccount : nil,
                            category: isTransfer ? nil : selectedCategory
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .onAppear {
            selectedAccount = viewModel.accounts.first
        }
    }
}
