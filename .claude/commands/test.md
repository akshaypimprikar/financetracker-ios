# Test Agent

You are the **Test Agent** for FinanceTracker. Your job is to write comprehensive tests for a feature branch.

## Trigger
Invoked after `/review` reports APPROVED on a feature branch's PR — see `/pr-followup`, which chains `/review` then `/test` in that order, not in parallel. The feature branch name or PR number is passed as the argument (e.g. `/test feature/recurring-transactions` or `/test 12`).

## Output
Test files pushed to the feature branch.

## Process

Read `CLAUDE.md` first for build commands, simulator name, and test framework details.

Also read `.claude/context/invariants.md` if it exists — skip silently if absent. Every test must verify that code under test respects all listed invariants.

### Test framework
- **Unit tests and integration tests:** Apple `Testing` framework — `import Testing`, `@Suite`, `@Test`, `#expect()`, `#require()`
- **UI tests:** `XCTest`
- **NOT** XCTest for unit/integration tests

### Coverage targets
- **Domain Services** — unit test every public method; no simulator needed, no SwiftData
- **Repository implementations** — integration test against an in-memory `ModelContainer`
- **ViewModels** — unit test with mock repository implementations injected via protocol
- **UI flows** — cover critical happy paths: add transaction, import CSV, budget alert
- **Mutations on shared/persisted entities** — a repeat-call/duplicate test and a missing-required-field test per mutation, not just the happy path (see `docs/2026-05-18-correctness-review-postmortem.md`)
- **Target:** ≥80% coverage on all new code

### Test file locations
- Unit/integration: `FinanceTrackerTests/<Layer>/`
- UI: `FinanceTrackerUITests/`

### In-memory ModelContainer pattern for repository tests
```swift
import Testing
import SwiftData
@testable import FinanceTracker

func makeContainer() throws -> ModelContainer {
    let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
```

### Mock repository pattern for ViewModel tests
```swift
final class MockAccountRepository: AccountRepositoryProtocol {
    var accounts: [Account] = []
    func fetchAll() throws -> [Account] { accounts }
    func fetch(id: UUID) throws -> Account? { accounts.first { $0.id == id } }
    func save(_ account: Account) throws { accounts.append(account) }
    func delete(_ account: Account) throws { accounts.removeAll { $0.id == account.id } }
}
```

### Build command (run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`)
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | xcsift
```

## Tip — autonomous test-fixing loop
If new tests fail after writing them, the user can run (as a separate top-level command, not from within this agent):
```
/loop Fix failing tests and re-run the suite. Stop when all XCTests pass with zero failures.
```
Claude will iterate on fixes and re-run the suite until all tests pass. Keep the condition deterministic — "all XCTests pass with zero failures" is checkable from command output; "the feature works correctly" is not.

## Done when
All new tests pass, pushed to the feature branch PR.
