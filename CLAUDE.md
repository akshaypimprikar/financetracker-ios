# CLAUDE.md

FinanceTracker — iOS 26.4 personal finance app (SwiftUI + SwiftData). Users track spending across accounts, set monthly budgets per category, and import transactions from CSV.

## Build & Test

All commands run from `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains `FinanceTracker.xcodeproj`).

```bash
# Build
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'

# Full test suite
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17'

# Single suite / single test
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/<SuiteName>
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/<SuiteName>/<testName>
```

> **Simulator:** `iPhone 17` — iOS 26.4 ships with iPhone 17 only, not iPhone 16.
> **File inclusion:** `PBXFileSystemSynchronizedRootGroup` (Xcode 16) — drop a `.swift` file in the right folder and it compiles automatically. Never edit `project.pbxproj`.

## Architecture

**Layer rules (enforced):**
- Views: no business logic, no direct SwiftData access
- Domain Services: zero SwiftData imports — 100% unit-testable without a simulator
- All money values: `Decimal`, never `Double`
- ViewModels: depend on repository protocols, never concrete SwiftData implementations

## Key constraints

- `AccountType.creditCard` is a liability — negative balance reduces net worth (this is intentional)
- `Transaction.importHash` = SHA256(date+amount+payee) — used for CSV dedup, must be preserved
- Tests use `import Testing` with `@Suite` / `@Test` / `#expect()` — **not** XCTest for unit/integration tests

## Agent commands

Commands in `.claude/commands/`: `/spec` `/plan` `/feature` `/gates` `/test` `/review` `/pr-followup` `/bugfix` `/release` `/sync-workflow` `/design` `/pipeline-review`

Standard pipeline: `/spec` → `/plan` → `/feature` (simplify per task) → `/gates` → PR targets `develop` → `/pr-followup` (auto-chains `/review` → `/test`; `code-review:code-review` can't be agent-invoked — run it yourself) → `/release` → `main`

UI features: run `/design` before `/spec` if the feature introduces a visual pattern with no existing token.

**PR creation rule:** always pass `--base develop` to `gh pr create` for every branch type except `release/*` and `hotfix/*`. `gh pr create` defaults to `main` — omitting `--base` silently targets the wrong branch.
**Merge rule:** no command merges a PR automatically. A PR is mergeable only once `/review` returns APPROVED, `/test` passes, and `code-review:code-review` is clean — then the user merges it themselves. (GitHub review approval can't gate this: every PR here is authored under the user's own account, and GitHub blocks authors from approving their own PRs.) Agents report their verdict and stop.

**Cross-repo rule:** never use `cd` for pragma operations — the shell working directory persists across tool calls and silently affects subsequent `gh`/`git` commands. Always use `git -C /Users/akshaypimprikar/Desktop/Claude/pragma <cmd>` and `gh pr create --repo akshaypimprikar/pragma`.
