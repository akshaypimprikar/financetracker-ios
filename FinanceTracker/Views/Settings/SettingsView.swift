import SwiftUI

struct SettingsView: View {
    @Bindable var categoryVM: CategoryViewModel
    @State private var isPresentingAdd = false

    private var expenseCategories: [Category] {
        categoryVM.categories.filter { $0.type == .expense }
    }
    private var incomeCategories: [Category] {
        categoryVM.categories.filter { $0.type == .income }
    }

    var body: some View {
        List {
            if !expenseCategories.isEmpty {
                Section("Expense Categories") {
                    ForEach(expenseCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? categoryVM.delete(expenseCategories[index])
                        }
                    }
                }
            }

            if !incomeCategories.isEmpty {
                Section("Income Categories") {
                    ForEach(incomeCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? categoryVM.delete(incomeCategories[index])
                        }
                    }
                }
            }

            if categoryVM.categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "tag",
                    description: Text("Tap + to add a category")
                )
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddCategorySheet(categoryVM: categoryVM)
        }
        .onAppear { try? categoryVM.load() }
    }
}
