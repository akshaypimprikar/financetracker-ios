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

*Not yet implemented. Tokens will be added to `FinanceTracker/Theme/Charts.swift` when the charts feature ships. Run `/design "chart visualisation"` before that spec is written.*
