import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                netWorthCard
                spendingCard

                if !viewModel.budgetProgresses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Budgets").font(.headline)
                        ForEach(viewModel.budgetProgresses, id: \.0.id) { budget, progress in
                            BudgetProgressCard(budget: budget, progress: progress)
                        }
                    }
                }

                if !viewModel.recentTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Transactions").font(.headline)
                        ForEach(viewModel.recentTransactions) { tx in
                            TransactionRow(transaction: tx)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .onAppear { try? viewModel.load() }
    }

    private var netWorthCard: some View {
        VStack(spacing: 4) {
            Text("Net Worth")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.netWorth, format: .currency(code: "USD"))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(viewModel.netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.teal.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var spendingCard: some View {
        HStack {
            Text("Spent this month")
            Spacer()
            Text(viewModel.spendingThisMonth, format: .currency(code: "USD"))
                .bold()
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BudgetProgressCard: View {
    let budget: Budget
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(budget.category.name)
                    .font(.subheadline)
                Spacer()
                Text(progress.spent, format: .currency(code: "USD"))
                    .font(.subheadline.bold())
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
