import SwiftUI

struct AddBudgetSheet: View {
    @Bindable var viewModel: BudgetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var limitText = ""

    private var canAdd: Bool {
        selectedCategoryID != nil && Decimal(string: limitText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $selectedCategoryID) {
                        Text("Select").tag(nil as UUID?)
                        ForEach(viewModel.unbudgetedCategories) { cat in
                            Text(cat.name).tag(cat.id as UUID?)
                        }
                    }
                    TextField("Monthly limit", text: $limitText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let cat = viewModel.unbudgetedCategories.first(where: { $0.id == selectedCategoryID }),
                              let limit = Decimal(string: limitText) else { return }
                        try? viewModel.add(category: cat, monthlyLimit: limit)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .onAppear {
            selectedCategoryID = viewModel.unbudgetedCategories.first?.id
        }
    }

    @State private var selectedCategoryID: UUID?
}
