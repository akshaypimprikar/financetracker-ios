# Multi-Agent Workflow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Install seven Claude Code slash commands into `.claude/commands/` and update `CLAUDE.md` with an Agent Workflow section so every future feature follows a structured spec → plan → implement → review pipeline.
**Architecture:** Commands are Markdown files that Claude Code loads as `/spec`, `/plan`, `/feature`, `/test`, `/review`, `/bugfix`, `/release`. They encode project-specific paths, branch strategy, and architecture rules so agents don't need prior context.
**Tech Stack:** Claude Code slash commands (`.claude/commands/`), Markdown.
**All commands run from:** `/Users/akshaypimprikar/Desktop/FinanceTracker/` (git root)

---

## Task 1 — Create `/spec` command

**File:** `.claude/commands/spec.md`

The Spec Agent turns a feature idea into an approved design spec saved to `docs/superpowers/specs/`.

Rules:
- Reads `CLAUDE.md`, existing models, services, and protocols before asking questions
- Proposes 2–3 approaches with tradeoffs before writing
- Enforces layer rules in every spec (no business logic in Views, no SwiftData in Services, Decimal for money)
- Saves to `docs/superpowers/specs/YYYY-MM-DD-<feature-name>.md` on branch `spec/<feature-name>`
- Hands off to `/plan` when approved

---

## Task 2 — Create `/plan` command

**File:** `.claude/commands/plan.md`

The Planner Agent turns an approved spec into a numbered task-by-task implementation plan.

Rules:
- Every task has exact file paths, complete code (no placeholders), and xcodebuild commands
- TDD structure per task: write failing test → confirm failure → implement → confirm pass → commit
- Build commands use `xcodebuild` from git root with `iPhone 17` simulator
- Saves plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- Hands off to `/feature` (+ `/test` in parallel) when approved

---

## Task 3 — Create `/feature` command

**File:** `.claude/commands/feature.md`

The Feature Agent implements an approved plan task by task with TDD and per-task commits.

Rules:
- Creates branch `feature/<name>` off `main`
- Strict TDD: write failing test first, confirm failure, implement, confirm pass
- One commit per task; full suite must pass before next task
- Never edits `project.pbxproj` (PBXFileSystemSynchronizedRootGroup auto-compiles)
- Opens PR to `main` when all tasks done; hands off to `/review` and `/test` in parallel

---

## Task 4 — Create `/test` command

**File:** `.claude/commands/test.md`

The Test Agent writes comprehensive tests for a feature branch, covering Domain Services, Repositories, ViewModels, and critical UI flows.

Rules:
- Unit/integration: Apple `Testing` framework (`@Suite`, `@Test`, `#expect()`) — NOT XCTest
- UI tests: XCTest in `FinanceTrackerUITests/`
- In-memory `ModelContainer` for repository integration tests
- Mock repository protocols for ViewModel unit tests
- Coverage target ≥80% on all new code

---

## Task 5 — Create `/review` command

**File:** `.claude/commands/review.md`

The Review Agent checks a PR for architecture compliance and code quality.

Rules:
- Verifies all layer separation rules from CLAUDE.md
- Checks no `Double` for money, no force-unwraps, no SwiftData in Domain Services
- Verifies tests exist for all new Services, Repositories, and ViewModels
- Outputs ✅/❌ per check; verdict is APPROVED or CHANGES REQUESTED

---

## Task 6 — Create `/bugfix` command

**File:** `.claude/commands/bugfix.md`

The Bug Fix Agent fixes a reported bug with a mandatory regression test.

Rules:
- Writes the failing test BEFORE touching production code
- Implements minimal fix to make failing test pass — no refactoring
- Runs full suite after fix; no regressions allowed
- Opens PR to `main`; Review Agent runs on the PR

---

## Task 7 — Create `/release` command

**File:** `.claude/commands/release.md`

The Release Agent prepares and tags a release.

Rules:
- Pre-flight: full test suite green, no TODO/FIXME in new code, no force-unwraps added since last tag
- Bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj`
- Updates `CHANGELOG.md`
- Tags `v<version>` on `main`, creates GitHub release via `gh`

---

## Task 8 — Update CLAUDE.md with Agent Workflow section

Add a new `## Agent Workflow` section to `CLAUDE.md` that documents:
- The seven slash commands and when to use each
- The standard pipeline: `/spec` → `/plan` → `/feature` + `/test` (parallel) → `/review` → merge
- Agent-specific enforcement rules (what each agent must check before proceeding)
