# FinanceTracker

An iOS 26.4 personal finance app built with SwiftUI + SwiftData — and a **multi-agent AI development workflow** that takes every feature from idea to merged PR without shortcuts.

The app is real, but the workflow is the interesting part.

---

## The Multi-Agent Pipeline

Every feature follows the same disciplined path:

```
Idea
  └─ /design  → establish or extend Theme token system before any UI work
  └─ /spec    → design spec, 2–3 approaches proposed, you choose
  └─ /plan    → task-by-task implementation plan with exact code + commands
  └─ /feature → TDD implementation: failing test → implement → pass → commit
  └─ /review  → architecture + design compliance check (layer rules, type safety, Theme tokens, coverage)
  └─ /test    → coverage report via xccov
  └─ /release → version bump, CHANGELOG, PR from develop → main, tag
```

You approve twice per feature: after the spec and after the plan. Everything else runs autonomously until you hit merge.

Nine slash commands in `.claude/commands/` define each agent's behaviour — branch strategy, TDD rules, architecture checks, design token enforcement, commit conventions, and PR targets.

---

## Architecture

MVVM + Repository. Strict layer separation enforced by the Review Agent on every PR.

```
Views               — SwiftUI, no business logic
ViewModels          — @Observable, depend on protocols only
Domain Services     — pure Swift, zero SwiftData imports, 100% unit testable
Repository Protocols — Foundation-only imports
SwiftData Repositories — concrete implementations, swappable
@Model entities     — Account, Transaction, Category, Budget, ImportRecord
```

**Key constraints:**
- All money values use `Decimal`, never `Double`
- `AccountType.creditCard` is a liability — intentional for net worth calculation
- `Transaction.importHash` = SHA256(date+amount+payee) — CSV dedup

---

## Features

- **Dashboard** — net worth, spending this month, budget progress
- **Transactions** — list, search by payee, filter by account, add manually
- **CSV Import** — 3-step flow: file picker → column mapping → preview + dedup
- **Budgets** — monthly limits per category with progress tracking
- **Accounts** — assets + liabilities, net worth calculation
- **Settings** — manage expense/income categories

---

## Tech Stack

| | |
|---|---|
| Platform | iOS 26.4 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Testing | Swift Testing (`@Suite`/`@Test`/`#expect`) + XCUITest |
| AI tooling | Claude Code with custom slash commands |

---

## Repo Structure

```
FinanceTracker/          — app source (Models, Services, Repositories, ViewModels, Views)
FinanceTrackerTests/     — unit + integration tests
FinanceTrackerUITests/   — XCUITest flows (5 core user flows)
.claude/commands/        — agent definitions (/spec, /plan, /feature, /review, /test, /bugfix, /release, /sync-workflow, /design)
FinanceTracker/Theme/    — semantic design tokens (Colors, Spacing, Typography)
docs/design-system.md   — token reference and component patterns
docs/superpowers/
  specs/                 — design specs (approved before any code is written)
  plans/                 — implementation plans (approved before the feature agent runs)
CLAUDE.md                — build commands, architecture rules, agent pipeline (always-on context)
CHANGELOG.md             — version history
```

The `docs/superpowers/` directory is the paper trail — every feature has a spec and a plan that predates the code.

---

## Branch Strategy (Gitflow)

```
main        — production, tagged on release only
develop     — integration branch, all features merge here
feature/*   — off develop, one per feature
fix/*       — off develop (hotfix/* off main)
release/*   — off develop, PR to main, back-merged to develop
spec/*      — off develop, for spec + plan docs
design/*    — off develop, for Theme token additions
```

---

## Build & Test

All commands run from the repo root (where `FinanceTracker.xcodeproj` lives).

```bash
# Build
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'

# Unit + integration tests
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests

# UI tests
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests
```

> Simulator: `iPhone 17` — iOS 26.4 ships with iPhone 17 only.
