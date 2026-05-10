import SwiftUI

struct BudgetListView: View {
    @Bindable var viewModel: BudgetViewModel
    @State private var isPresentingAdd = false

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Month",
                    selection: $viewModel.selectedMonth,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .onChange(of: viewModel.selectedMonth) {
                    try? viewModel.load()
                }
            }

            if viewModel.budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "target",
                    description: Text("Tap + to set a budget for a category")
                )
            } else {
                Section("This month") {
                    ForEach(viewModel.budgets, id: \.0.id) { budget, progress in
                        NavigationLink {
                            BudgetDetailView(budget: budget, progress: progress,
                                             viewModel: viewModel)
                        } label: {
                            BudgetRow(budget: budget, progress: progress)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(viewModel.budgets[index].0)
                        }
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
                    .disabled(viewModel.unbudgetedCategories.isEmpty)
                    .accessibilityIdentifier("add-budget-button")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddBudgetSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }
}

private struct BudgetRow: View {
    let budget: Budget
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(budget.category.name, systemImage: budget.category.icon)
                    .font(.subheadline.bold())
                Spacer()
                Text(progress.spent, format: .currency(code: "USD"))
                    .bold()
                    .foregroundStyle(progress.isOverBudget ? .red : .primary)
                Text("/ \(progress.limit.formatted(.currency(code: "USD")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }
}
