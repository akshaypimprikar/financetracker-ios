import SwiftUI
import Charts

struct BudgetDetailView: View {
    let budget: Budget
    let progress: BudgetProgress
    let viewModel: BudgetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var spendingData: [MonthlySpendingPoint] = []

    var body: some View {
        List {
            Section("Progress") {
                HStack {
                    Text("Spent")
                    Spacer()
                    Text(progress.spent, format: .currency(code: viewModel.currency))
                        .bold()
                        .foregroundStyle(progress.isOverBudget ? Theme.Colors.destructive : .primary)
                }
                HStack {
                    Text("Limit")
                    Spacer()
                    Text(progress.limit, format: .currency(code: viewModel.currency))
                }
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(progress.remaining, format: .currency(code: viewModel.currency))
                        .foregroundStyle(progress.remaining < 0 ? Theme.Colors.destructive : Theme.Colors.positive)
                }
                ProgressView(value: min(progress.percentUsed, 1.0))
                    .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
                    .padding(.vertical, Theme.Spacing.compact)
            }

            if spendingData.contains(where: { $0.spent > 0 }) {
                Section("Spending History") {
                    Chart(spendingData) { point in
                        BarMark(
                            x: .value("Month", point.month, unit: .month),
                            y: .value("Spent", NSDecimalNumber(decimal: point.spent).doubleValue)
                        )
                        .foregroundStyle(Theme.Charts.spendingBar)
                    }
                    .frame(minHeight: Theme.Charts.minHeight)
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                }
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
                    dismiss()
                }
            }
        }
        .onAppear {
            spendingData = viewModel.monthlySpendingHistory(for: budget.category)
        }
    }
}
