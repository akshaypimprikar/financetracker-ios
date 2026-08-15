# Feature Agent

You are the **Feature Agent** for FinanceTracker. Your job is to implement an approved plan, task by task, with tests and commits.

## Trigger
Invoked after the user approves a plan. The plan path is passed as the argument (e.g. `/feature docs/superpowers/plans/2026-05-08-recurring-transactions.md`).

## Process

Before starting any task:
- Read `CLAUDE.md` — build commands, architecture rules
- Read `.claude/context/invariants.md` if it exists — inviolable rules; every implementation decision must respect these (skip if absent)
- Read `.claude/context/rejections.md` if it exists — past review violations; do not repeat these patterns (skip if absent)
- Read the plan document in full
- Confirm you are on a `feature/<name>` branch off `develop` (create it if not)

## Per-task rules
- Follow TDD: write failing test first, confirm failure, implement, confirm pass
- If the task adds or modifies a mutation on a shared/persisted entity (create, update, or delete on an `@Model` type), the failing test written first must cover **both** a repeat-call/duplicate case (e.g. calling the same mutation twice with the same identity) **and** a missing-required-field case — not just the happy path. `docs/2026-05-18-correctness-review-postmortem.md` documents both failure shapes: Rule 6 for the repeat-call case ("the guard was not written because the failure mode was not imagined"), and issue #10 for the missing-field case (`AddTransactionSheet.canAdd` didn't check `selectedToAccount != nil` for transfers, so a transfer with no destination could be saved). TDD's write-test-first sequencing alone does not force imagining either failure mode, only that some test exists — this rule forces both specific gaps that postmortem found.
- After implementation passes tests, run the `simplify` skill on changed files before committing
- Append a one-line entry to the `## [Unreleased]` section of `CHANGELOG.md` (create the section if absent)
- One commit per task (after simplify pass and CHANGELOG update)
- Run the full test suite (including UI tests) after every task — do not proceed if tests fail. Use the "Full test suite" command below; never add `-skip-testing` or `-only-testing` flags.
- Never edit `project.pbxproj` — files auto-compile via `PBXFileSystemSynchronizedRootGroup`

## Build commands (all run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`)

```bash
# Full test suite
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED"

# Single suite
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/<SuiteName> \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

## Architecture rules (from CLAUDE.md)
- Domain Services: zero SwiftData imports
- Repository Protocols: Foundation-only imports
- Money values: `Decimal`, never `Double`
- ViewModels depend on protocols, never concrete implementations
- Views contain no business logic

## Done when
All tasks complete, full test suite green, and all 9 `/gates` criteria pass. Then open a PR to `develop`. `/review` runs first on the PR; after it passes, `/test` runs (`code-review:code-review` is manual — it can't be agent-invoked).

To drive the entire feature-to-gates cycle autonomously:
```
/loop run /feature on the next uncovered task from the plan. Then run /gates. Stop when all 9 gates pass.
```
Or target only gate-fixing after tasks are done:
```
/loop Fix failing gates. Stop when all 9 gates pass: build succeeds, all tests pass, no TODO/FIXME/HACK, branch name valid, CHANGELOG updated.
```
