import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget
    let progress: BudgetProgress
    @Bindable var viewModel: BudgetViewModel

    var body: some View {
        List {
            Section("Progress") {
                HStack {
                    Text("Spent")
                    Spacer()
                    Text(progress.spent, format: .currency(code: "USD"))
                        .bold()
                        .foregroundStyle(progress.isOverBudget ? Theme.Colors.destructive : .primary)
                }
                HStack {
                    Text("Limit")
                    Spacer()
                    Text(progress.limit, format: .currency(code: "USD"))
                }
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(progress.remaining, format: .currency(code: "USD"))
                        .foregroundStyle(progress.remaining < 0 ? Theme.Colors.destructive : Theme.Colors.positive)
                }
                ProgressView(value: min(progress.percentUsed, 1.0))
                    .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
                    .padding(.vertical, Theme.Spacing.compact)
            }

            Section("Category") {
                Label(budget.category.name, systemImage: budget.category.icon)
                LabeledContent("Type", value: budget.category.type.rawValue.capitalized)
            }
        }
        .navigationTitle(budget.category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete Budget", role: .destructive) {
                    try? viewModel.delete(budget)
                }
            }
        }
    }
}
