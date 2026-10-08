---
name: test
description: Audit a feature branch for coverage gaps and fill them before /gates. Invoke after /feature finishes and before /gates, passing the branch name.
disable-model-invocation: true
---

# Test Agent

You are the **Test Agent** for FinanceTracker. Your job is to audit a feature branch for coverage gaps and fill them before `/gates` runs, so the added tests go through `/gates`, `code-review` and `/review` with the rest of the change.

## Trigger
Invoked after `/feature` finishes and before `/gates`, on the feature branch (e.g. `/test feature/recurring-transactions`). `/feature` already writes each task's test first (RED before GREEN; Gate 11 checks the commit order only for new ViewModel, Service and Repository files that have a matching test file), so this is an audit: find behavior the TDD tests left uncovered (the coverage targets below) and add tests for it. It no longer runs after `/review`, where its tests were never reviewed.

## Output
Test files committed to the feature branch, before `/gates` runs.

## Process

Read `AGENTS.md` first for build commands, simulator name, and test framework details.

Also read `.claude/context/invariants.md` if it exists — skip silently if absent. Every test must verify that code under test respects all listed invariants.

### Project settings
Read `project` in `scripts/pipeline_lanes.json`: `persistence` (swiftdata | coredata | realm | none), `ui` (swiftui | uikit), `architecture` (mvvm | mvc | viper). If the key is absent, assume swiftdata, swiftui, mvvm. For `ui: uikit`, or `persistence` other than swiftdata, also read `.claude/skills/test/uikit.md` (controller loading, in-memory Core Data). Read "ViewModel" as Controller (mvc) or Presenter (viper).

### Test framework
- **Unit tests and integration tests:** Apple `Testing` framework — `import Testing`, `@Suite`, `@Test`, `#expect()`, `#require()`
- **UI tests:** `XCTest`
- **NOT** XCTest for unit/integration tests

### Coverage targets
- **Domain Services** — unit test every public method; no simulator needed, no persistence framework
- **Repository implementations** — integration test against an in-memory store (`ModelContainer` for swiftdata; see `uikit.md` for Core Data)
- **ViewModels** (or Controllers / Presenters) — unit test with mock repository implementations injected via protocol
- **UI flows** — cover critical happy paths: add transaction, import CSV, budget alert
- **Mutations on shared/persisted entities** — a repeat-call/duplicate test and a missing-required-field test per mutation, not just the happy path (see `docs/2026-05-18-correctness-review-postmortem.md` Rule 6 and issue #10)
- **Target:** ≥80% coverage on all new code

### Test file locations
- Unit/integration: `FinanceTrackerTests/<Layer>/`
- UI: `FinanceTrackerUITests/`

### In-memory ModelContainer pattern for repository tests `[swiftdata]`
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
LOG=$(mktemp -t test)
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  > "$LOG" 2>&1; RC=$?
xcsift < "$LOG"
PASSED=$(grep -E "^Test [Cc]ase '.*' passed|^[✔✓] Test .*passed" "$LOG" | grep -vc "Test run with"); FAILED=$(grep -cE "^Test [Cc]ase '.*' failed|^[✘✗] Test .*failed" "$LOG")
[ -s "$LOG" ] && [ "$RC" -eq 0 ] && grep -q "TEST SUCCEEDED" "$LOG" && [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ] \
  && echo "TESTS PASS ($PASSED tests executed)" || echo "TESTS FAIL (xcodebuild exit $RC, passed=$PASSED, failed=$FAILED)"
```
The log file replaces a `| xcsift` pipeline, which hides `xcodebuild`'s exit status (an empty or crashed run then prints a clean-looking summary). The executed-test count is required for the same reason as in `/gates` Gate 2: `xcodebuild test` prints `** TEST SUCCEEDED **` with exit 0 when a test filter or scheme change matches nothing.

## Tip — autonomous test-fixing loop
If new tests fail after writing them, the user can run (as a separate top-level command, not from within this agent):
```
/loop Fix failing tests and re-run the suite. Stop when all XCTests pass with zero failures.
```
Claude will iterate on fixes and re-run the suite until all tests pass. Keep the condition deterministic — "all XCTests pass with zero failures" is checkable from command output; "the feature works correctly" is not.

## Done when
The coverage gaps are filled, all tests pass, and the tests are committed to the feature branch before `/gates`.
