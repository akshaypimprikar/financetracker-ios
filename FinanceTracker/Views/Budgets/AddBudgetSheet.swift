import SwiftUI

struct AddBudgetSheet: View {
    @Bindable var viewModel: BudgetViewModel
    @Bindable var categoryVM: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var limitText = ""
    @State private var selectedCategoryID: UUID?
    @State private var isPresentingAddCategory = false

    private var canAdd: Bool {
        selectedCategoryID != nil && Decimal(string: limitText) != nil
    }

    private var hasUnbudgetedCategories: Bool { !viewModel.unbudgetedCategories.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if !hasUnbudgetedCategories {
                    emptyState
                } else {
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
                                .accessibilityIdentifier("budget-limit-field")
                        }
                    }
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if hasUnbudgetedCategories {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            guard let cat = viewModel.unbudgetedCategories.first(where: { $0.id == selectedCategoryID }),
                                  let limit = Decimal(string: limitText) else { return }
                            try? viewModel.add(category: cat, monthlyLimit: limit)
                            dismiss()
                        }
                        .disabled(!canAdd)
                        .accessibilityIdentifier("add-budget-confirm")
                    }
                }
            }
        }
        .onAppear {
            selectedCategoryID = viewModel.unbudgetedCategories.first?.id
        }
        .sheet(isPresented: $isPresentingAddCategory, onDismiss: {
            try? viewModel.load()
            selectedCategoryID = viewModel.unbudgetedCategories.first?.id
        }) {
            AddCategorySheet(categoryVM: categoryVM)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.suggestionsAvailable {
            ContentUnavailableView(
                "No Categories Yet",
                systemImage: "sparkles",
                description: Text("Import a CSV to get AI-suggested categories, then come back to set a budget")
            )
        } else {
            ContentUnavailableView {
                Label("No Categories Yet", systemImage: "tag")
            } description: {
                Text("Add a category to set a budget for it")
            } actions: {
                Button("Add Category") { isPresentingAddCategory = true }
                    .accessibilityIdentifier("add-budget-empty-add-category")
            }
        }
    }
}
