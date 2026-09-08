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
                        loadBudgets()
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
                            do {
                                try viewModel.delete(viewModel.budgets[index].0)
                            } catch {
                                viewModel.markLoadFailed()
                            }
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
        .onAppear { loadBudgets() }
        .onDisappear { loadTask?.cancel() }
        .alert(
            "Couldn't Update Budgets",
            isPresented: Binding(
                get: { viewModel.loadFailed },
                set: { isPresented in
                    if !isPresented { viewModel.dismissLoadFailure() }
                }
            )
        ) {
            Button("OK") { }
        } message: {
            Text("Something went wrong loading or updating your budgets. Try again.")
        }
    }

    /// Shared by the debounced month-change reload and the initial `onAppear` load —
    /// one place owns "load failed, tell the user" so the two call sites can't drift
    /// out of sync. `.onDelete` above calls `markLoadFailed()` directly instead (a
    /// delete failure isn't a load failure, but reuses the same alert rather than
    /// adding a second failure state for one extra call site).
    private func loadBudgets() {
        do {
            try viewModel.load()
        } catch {
            viewModel.markLoadFailed()
        }
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
