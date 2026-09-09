import SwiftUI

struct AddAccountSheet: View {
    @Bindable var viewModel: AccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = AccountType.checking
    @State private var currency = "USD"
    @State private var openingBalanceText = ""
    @State private var colorHex = "#4A90D9"
    @State private var icon = "banknote"

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("account-name-field")
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    TextField("Currency (e.g. USD)", text: $currency)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Opening Balance") {
                    TextField("0.00", text: $openingBalanceText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let balance = Decimal(string: openingBalanceText) ?? 0
                        try? viewModel.addAccount(
                            name: name, type: type, currency: currency,
                            colorHex: colorHex, icon: icon,
                            openingBalance: balance
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("add-account-confirm")
                }
            }
        }
    }
}
