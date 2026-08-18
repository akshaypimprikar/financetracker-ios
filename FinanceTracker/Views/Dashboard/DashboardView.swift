import SwiftUI
import Charts

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.cardPadding) {
                netWorthCard
                spendingCard

                if !viewModel.categorySpending.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.contentSpacing) {
                        Text("Spending by Category").font(Theme.Typography.sectionHeader)
                        Chart(viewModel.categorySpending) { item in
                            BarMark(
                                x: .value("Category", item.category.name),
                                y: .value("Spent", NSDecimalNumber(decimal: item.amount).doubleValue)
                            )
                            .foregroundStyle(Theme.Charts.spendingBar)
                        }
                        .frame(minHeight: Theme.Charts.minHeight)
                        .padding(.horizontal, Theme.Spacing.cardPadding)
                    }
                }

                if !viewModel.budgetProgresses.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.contentSpacing) {
                        Text("Budgets").font(Theme.Typography.sectionHeader)
                        ForEach(viewModel.budgetProgresses, id: \.0.id) { budget, progress in
                            BudgetProgressCard(budget: budget, progress: progress,
                                               currency: viewModel.currency)
                        }
                    }
                }

                if !viewModel.recentTransactions.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.contentSpacing) {
                        Text("Recent Transactions").font(Theme.Typography.sectionHeader)
                        ForEach(viewModel.recentTransactions) { tx in
                            TransactionRow(transaction: tx)
                                .padding(.vertical, Theme.Spacing.tight)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.cardPadding)
        }
        .navigationTitle("Dashboard")
        .onAppear { try? viewModel.load() }
    }

    private var netWorthCard: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Text("Net Worth")
                .font(Theme.Typography.rowSubtitle)
                .foregroundStyle(.secondary)
            Text(viewModel.netWorth, format: .currency(code: viewModel.currency))
                .font(Theme.Typography.amountDisplay)
                .foregroundStyle(viewModel.netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Colors.netWorthCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge))
    }

    private var spendingCard: some View {
        HStack {
            Text("Spent this month")
            Spacer()
            Text(viewModel.spendingThisMonth, format: .currency(code: viewModel.currency))
                .bold()
        }
        .padding(Theme.Spacing.cardPadding)
        .background(Theme.Colors.spendingCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCard))
    }
}

private struct BudgetProgressCard: View {
    let budget: Budget
    let progress: BudgetProgress
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.compact) {
            HStack {
                Text(budget.category.name)
                    .font(.subheadline)
                Spacer()
                Text(progress.spent, format: .currency(code: currency))
                    .font(.subheadline.bold())
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
