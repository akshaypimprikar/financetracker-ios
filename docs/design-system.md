# FinanceTracker Design System

All visual constants live in `FinanceTracker/Theme/`. Every view must use these tokens — no hardcoded colors, spacing values, or font sizes in production code.

---

## Colors

`Theme.Colors` — `FinanceTracker/Theme/Colors.swift`

| Token | Value | Meaning |
|---|---|---|
| `positive` | `.green` | Income amounts, credit transactions, available budget, positive balances |
| `destructive` | `.red` | Over-budget, negative balances, delete actions |
| `transfer` | `.blue` | Transfer transaction amounts |
| `netWorthCardBackground` | `.teal.opacity(0.12)` | Net worth hero card background |
| `spendingCardBackground` | `.orange.opacity(0.08)` | Spending summary card background |
| `primaryInteractive` | `.accentColor` | Progress bars, buttons, decorative call-to-action icons |

---

## Spacing

`Theme.Spacing` — `FinanceTracker/Theme/Spacing.swift`

| Token | Value | Usage |
|---|---|---|
| `tight` | `2pt` | Stacked text pairs (payee + category in transaction rows) |
| `compact` | `4pt` | Row vertical padding, progress bar padding |
| `rowSpacing` | `6pt` | Budget row internal VStack |
| `contentSpacing` | `8pt` | Section internal spacing, card subgroup spacing |
| `elementSpacing` | `12pt` | Icon-to-text gap in rows |
| `cardPadding` | `16pt` | Standard card and content padding |
| `sheetSpacing` | `24pt` | Import sheet major section spacing |
| `cornerRadiusCard` | `12pt` | Secondary cards (e.g. spending card) |
| `cornerRadiusCardLarge` | `16pt` | Hero/primary cards (e.g. net worth card) |

---

## Typography

`Theme.Typography` — `FinanceTracker/Theme/Typography.swift`

| Token | Value | Usage |
|---|---|---|
| `amountDisplay` | `.system(size: 36, weight: .bold)` | Hero financial figures (net worth on dashboard) |
| `sectionHeader` | `.headline` | Section titles ("Budgets", "Recent Transactions") |
| `rowTitle` | `.body` | Primary row text (payee names, account names) |
| `rowSubtitle` | `.caption` | Secondary metadata (dates, types, labels) |
| `code` | `.caption.monospaced()` | Technical text (import hashes, CSV preview) |

---

## Component Patterns

### Card
A tappable or informational surface with a colored background.

```swift
VStack { ... }
    .padding()                                      // Theme.Spacing.cardPadding
    .background(Theme.Colors.netWorthCardBackground)
    .cornerRadius(Theme.Spacing.cornerRadiusCardLarge)
    .frame(maxWidth: .infinity, alignment: .leading)
```

- Hero card: `cornerRadiusCardLarge` (16pt), `netWorthCardBackground`
- Secondary card: `cornerRadiusCard` (12pt), `spendingCardBackground`

### Row
A list item with a leading label block and a trailing value.

```swift
HStack {
    VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
        Text(title).font(Theme.Typography.rowTitle)
        Text(subtitle).font(Theme.Typography.rowSubtitle)
    }
    Spacer()
    Text(value).font(Theme.Typography.rowTitle).bold()
}
```

### Sheet
A modal form for creating or editing a record.

```swift
NavigationStack {
    Form {
        Section("Section Title") { ... }
    }
    .navigationTitle("Add X")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { ... } }
        ToolbarItem(placement: .confirmationAction) { Button("Add") { ... } }
    }
}
```

### Empty State
Shown when a list has no items.

```swift
ContentUnavailableView(
    "No X Yet",
    systemImage: "icon.name",
    description: Text("Tap + to add your first X.")
)
```

### Progress Bar
Used in budget rows and detail views.

```swift
ProgressView(value: min(progress.percentUsed, 1.0))
    .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
    .padding(.vertical, Theme.Spacing.compact)
```

---

## Data Visualisation

`Theme.Charts` — `FinanceTracker/Theme/Charts.swift`

### Colors

| Token | Value | Meaning |
|---|---|---|
| `balanceLine` | `.teal` | Stroke colour for the running balance line chart in AccountDetailView |
| `balanceAreaFill` | `.teal.opacity(0.08)` | Gradient fill under the balance line — same hue as `netWorthCardBackground` at lower opacity |
| `spendingBar` | `.orange` | Bar fill for the spending breakdown chart in BudgetDetailView — echoes `spendingCardBackground` |
| `gridLine` | `Color(.separator)` | Chart axis grid lines; system colour so it respects dark mode automatically |

### Sizes

| Token | Value | Meaning |
|---|---|---|
| `minHeight` | `180pt` | Minimum chart frame height when embedded in a `List` section |
| `lineStrokeWidth` | `2pt` | Balance line stroke width |

### Reused tokens

Charts share these tokens from the existing system — no duplication:

| Token | Source | Use in charts |
|---|---|---|
| `Theme.Spacing.cornerRadiusCard` | Spacing | Callout/annotation bubble corner radius |
| `Theme.Spacing.cardPadding` | Spacing | Horizontal chart padding |
| `Theme.Typography.rowSubtitle` | Typography | Axis labels |

### Component patterns

#### Balance Line Chart (AccountDetailView)
A line chart showing running account balance over time. Area below the line is filled with `balanceAreaFill`.

```swift
Chart(dataPoints) { point in
    LineMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
        .foregroundStyle(Theme.Charts.balanceLine)
        .lineStyle(StrokeStyle(lineWidth: Theme.Charts.lineStrokeWidth))
    AreaMark(x: .value("Date", point.date), y: .value("Balance", point.balance))
        .foregroundStyle(Theme.Charts.balanceAreaFill)
}
.frame(minHeight: Theme.Charts.minHeight)
.padding(.horizontal, Theme.Spacing.cardPadding)
```

#### Spending Bar Chart (BudgetDetailView)
A bar chart showing spending per category for the current month. All bars use `spendingBar`.

```swift
Chart(categoryTotals) { item in
    BarMark(x: .value("Category", item.name), y: .value("Spent", item.amount))
        .foregroundStyle(Theme.Charts.spendingBar)
}
.frame(minHeight: Theme.Charts.minHeight)
.padding(.horizontal, Theme.Spacing.cardPadding)
```
