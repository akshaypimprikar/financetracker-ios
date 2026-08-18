import SwiftUI

struct BudgetListView: View {
    private static let monthChangeDebounce: Duration = .milliseconds(150)

    @Bindable var viewModel: BudgetViewModel
    @Bindable var categoryVM: CategoryViewModel
    @State private var isPresentingAdd = false
    @State private var loadTask: Task<Void, Never>?

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
                    loadTask?.cancel()
                    loadTask = Task {
                        try? await Task.sleep(for: Self.monthChangeDebounce)
                        guard !Task.isCancelled else { return }
                        try? viewModel.load()
                    }
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
                            BudgetRow(budget: budget, progress: progress,
                                      currency: viewModel.currency)
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
                    .accessibilityIdentifier("add-budget-button")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddBudgetSheet(viewModel: viewModel, categoryVM: categoryVM)
        }
        .onAppear { try? viewModel.load() }
        .onDisappear { loadTask?.cancel() }
    }
}

private struct BudgetRow: View {
    let budget: Budget
    let progress: BudgetProgress
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.rowSpacing) {
            HStack {
                Label(budget.category.name, systemImage: budget.category.icon)
                    .font(.subheadline.bold())
                Spacer()
                Text(progress.spent, format: .currency(code: currency))
                    .bold()
                    .foregroundStyle(progress.isOverBudget ? Theme.Colors.destructive : .primary)
                Text("/ \(progress.limit.formatted(.currency(code: currency)))")
                    .font(Theme.Typography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? Theme.Colors.destructive : (Color(hex: budget.category.colorHex) ?? Theme.Colors.primaryInteractive))
        }
        .padding(.vertical, Theme.Spacing.compact)
    }
}
