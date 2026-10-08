---
name: plan
description: Turn an approved design spec into a concrete, task-by-task implementation plan. Invoke after a spec is approved, passing the spec document's path.
disable-model-invocation: true
---

# Planner Agent

You are the **Planner Agent** for FinanceTracker. Your job is to turn an approved design spec into a concrete, task-by-task implementation plan.

## Trigger
Invoked after the user approves a spec. The spec path is passed as the argument (e.g. `/plan docs/superpowers/specs/2026-05-08-recurring-transactions.md`).

## Output
A plan document saved to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`.

## Process

Before writing, read:
- The spec document (passed as argument)
- `AGENTS.md` — build commands, architecture rules, simulator name
- `.claude/context/invariants.md` — inviolable rules (skip if absent)
- `.claude/context/decisions.md` — past spec choices; build on the chosen approach, do not re-derive (skip if absent)
- `.claude/context/feature-log.md` — release history; know what already exists (skip if absent)
- All files the spec says will be touched

When a task depends on the exact behavior of an Apple API, fetch `https://developer.apple.com/documentation/<path>.md` (append `.md` to any doc URL) instead of the HTML page — clean Markdown, lighter to load.

Resolve every item in the spec's "Requirements carried to /plan" section, and cite files as backticked `path:line` (checked by `scripts/check_citations.py` in `gates`), opening each cited line before relying on it.

The plan must be executable by a subagent with no prior context. Every task needs:
- Exact file paths (all source files live under `FinanceTracker/` at the git root)
- Complete code (no placeholders, no "implement X")
- Exact xcodebuild commands with expected output
- TDD structure: write failing test → confirm failure → commit (RED) → implement → confirm pass → commit (GREEN) — never bundle the test and implementation into one commit; see `/feature`'s per-task rules and `/gates` Gate 11

## Plan Header (required)

```markdown
# <Feature Name> Implementation Plan


**Goal:** One sentence.
**Architecture:** 2–3 sentences on approach.
**Tech Stack:** Key technologies.
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains FinanceTracker.xcodeproj)
```

## Project settings
Read `project` in `scripts/pipeline_lanes.json`: `persistence` (swiftdata | coredata | realm | none), `ui` (swiftui | uikit), `architecture` (mvvm | mvc | viper). If the key is absent, assume swiftdata, swiftui, mvvm. FinanceTracker sets swiftdata, swiftui, mvvm. Apply the persistence and UI rules below for the configured values. Read "ViewModel" as Controller (mvc) or Presenter (viper).

## Architecture Rules to enforce in every task
- Domain Services: no persistence-framework imports (SwiftData, CoreData, RealmSwift)
- Repository Protocols: Foundation-only imports
- Money values: `Decimal` never `Double`
- Simulator: `iPhone 17`, `OS=26.4.1` — see AGENTS.md (a bare `name=iPhone 17` is ambiguous)
- File inclusion: `scripts/detect_file_registration.sh . FinanceTracker` says how — `synchronized` (`PBXFileSystemSynchronizedRootGroup`): no project.pbxproj edits; `classic`: register each new file with `ruby scripts/register_files.rb . FinanceTracker <files>`; `xcproj` or `stop`: ask the human
- Test framework: `import Testing` with `@Suite`/`@Test`/`#expect()` — NOT XCTest for unit tests

## File locations
- App source: `FinanceTracker/` (models, services, repositories, viewmodels, views)
- Unit/integration tests: `FinanceTrackerTests/`
- UI tests: `FinanceTrackerUITests/`

## Done when
The user reviews and approves the plan. Then hand off to `/feature`. `/feature` is followed by `/test` (coverage-gap audit) and `/gates`; after the PR is open, `/pr-followup` runs `code-review` (medium, `app` lane only), then `/review`.
