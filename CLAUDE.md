# CLAUDE.md

FinanceTracker — iOS 26.4 personal finance app (SwiftUI + SwiftData). Users track spending across accounts, set monthly budgets per category, and import transactions from CSV.

## Build & Test

All commands run from `/Users/akshaypimprikar/Desktop/FinanceTracker/` (git root, contains `FinanceTracker.xcodeproj`).

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

MVVM + Repository. Layers top → bottom: Views → ViewModels (@Observable) → Domain Services → Repository Protocols → SwiftData Repositories → @Model entities.

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

Nine slash commands in `.claude/commands/`: `/spec` `/plan` `/feature` `/test` `/review` `/bugfix` `/release` `/sync-workflow` `/design`

Standard pipeline: `/spec` → `/plan` → `/feature` (simplify per task) → PR → `develop` → `/review` + `/test` + `code-review:code-review` (parallel) → release → `main`

UI features: run `/design` before `/spec` if the feature introduces a visual pattern with no existing token. Run `/design` bootstrap once to establish `FinanceTracker/Theme/` and `docs/design-system.md`.

Branch strategy (gitflow):
- `feature/*` → `develop`
- `fix/*` → `develop` (hotfix: `hotfix/*` → `main` + `develop`)
- `release/*` → `main` + `develop`
- `spec/*` → `develop`
- `design/*` → `develop`
- `ci/*` → `develop`
- `main` receives only release and hotfix merges, never direct feature PRs

**PR creation rule:** always pass `--base develop` to `gh pr create` for every branch type except `release/*` and `hotfix/*`. `gh pr create` defaults to the repo default branch (`main`) — omitting `--base` silently targets the wrong branch.
