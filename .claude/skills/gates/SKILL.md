---
name: gates
description: Verify a feature branch meets all pre-PR criteria (build, tests, coverage, gate integrity, and more) before opening the pull request. Invoke at the end of a feature session, passing the branch name.
disable-model-invocation: true
model: claude-haiku-4-5-20251001
---

# Gates Agent

You are the **Gates Agent** for FinanceTracker. Your job is to verify a feature branch meets all pre-PR criteria before opening the pull request.

## Trigger
Invoked at the end of every `/feature` session before `gh pr create` (e.g. `/gates feature/recurring-transactions`).

## Process

All commands run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`.

Read `.claude/context/invariants.md` if it exists — skip silently if absent. Any gate that catches a violation not already listed as an invariant should be recorded as a candidate (see "### Write candidate invariants" under "## After all gates pass").

Run every gate in order. If any gate fails, stop, report what must be fixed, and do NOT open the PR.

### Pre-step — clean tree and pinned SHA (runs before Gate 0; applies to every gate)
```bash
git status --porcelain      # must print nothing
git rev-parse HEAD          # record this — every gate below is evidence about this exact commit
```
If `git status --porcelain` prints anything, **stop** and tell the user to commit (or stash) first —
Gates 1–2 build the working tree, while Gates 3–13 read the committed `git diff develop...HEAD`,
so a dirty tree makes the two halves describe different code. Any fix made while gates are failing
(including Gate 5's CHANGELOG auto-populate) is a new commit: return to this pre-step and re-record
the SHA, because the gate summary must describe the commit that actually opens the PR.

### Gate 0 — Build-relevant change check (runs first; determines if Gates 1–2 apply)
```bash
GATE0="$(git rev-parse --git-dir)/gate0-$(git rev-parse HEAD)"   # untracked, so the tree stays clean
git diff develop...HEAD --name-only -- '*.swift' '*.xcodeproj/**' '*.xcworkspace/**' '*.xcconfig' '*Info.plist' '*.entitlements' '*Package.resolved' '*Package.swift' '*.xctestplan' | tee "$GATE0"
```
This is the only copy of the build-relevance list: later steps that depend on Gate 0 read `$GATE0` (the file is named
after the pinned SHA, so a stale result from another commit is never read) instead of repeating it.
If this returns **no output**, skip Gates 1 and 2 — nothing that affects the build or test suite changed. Continue from Gate 3.
If any file is listed, run Gates 1 and 2 as normal. Project, config, plist, entitlement and
package-manifest, scheme and test-plan changes are included on purpose (a test-plan edit changes which tests run; add any other build input your project has — asset or string catalogs, data models): a build-setting flip (e.g. `SWIFT_DEFAULT_ACTOR_ISOLATION`
in the `.pbxproj`, or in the `.xcproj` that the Xcode 27.2 beta can convert a project to) can break the build or change runtime behavior without touching a `.swift` file.
The project and workspace bundles are matched whole (`*.xcodeproj/**`, `*.xcworkspace/**`), not by file extension, so `project.pbxproj`, the `project.xcproj` that replaces it after `xcodebuild -convert-project xcproj`, shared schemes and workspace settings all count, and so does any file a later Xcode adds to the bundle. `scripts/tests/test_gate0_pathspec.py` fails if a second copy of this list appears or if it stops matching those files.
Gates 3–13 still scope their own greps to `*.swift` where they say so.

### Gate 1 — Build (conditional: Gate 0 listed files)
```bash
LOG=$(mktemp -t gate1-build)
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  > "$LOG" 2>&1; RC=$?
xcsift < "$LOG"
[ -s "$LOG" ] && [ "$RC" -eq 0 ] && grep -q "BUILD SUCCEEDED" "$LOG" \
  && echo "GATE 1 PASS" || echo "GATE 1 FAIL (xcodebuild exit $RC, log bytes $(wc -c < "$LOG"))"
```
Pass: `GATE 1 PASS` — non-empty log, exit 0, and the `BUILD SUCCEEDED`
marker. Fail: anything else — an empty log or a non-zero exit is a failure, never "no errors seen".
Stop immediately — a test run on a broken build is meaningless. Why there is no `| xcsift` pipeline, and the
Xcode 27 SDK-break advisory: `reference.md` § Gate 1.

### Gate 2 — Full test suite (conditional: Gate 0 listed files)
```bash
LOG=$(mktemp -t gate2-test)
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  > "$LOG" 2>&1; RC=$?
xcsift < "$LOG"
PASSED=$(grep -E "^Test [Cc]ase '.*' passed|^[✔✓] Test .*passed" "$LOG" | grep -vc "Test run with"); FAILED=$(grep -cE "^Test [Cc]ase '.*' failed|^[✘✗] Test .*failed" "$LOG")
[ -s "$LOG" ] && [ "$RC" -eq 0 ] && grep -q "TEST SUCCEEDED" "$LOG" && [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ] \
  && echo "GATE 2 PASS ($PASSED tests executed)" || echo "GATE 2 FAIL (xcodebuild exit $RC, passed=$PASSED, failed=$FAILED)"
```
Pass: `GATE 2 PASS` with an executed-test count above zero (why zero fails: `reference.md` § Gate 2).
Fail: empty log, non-zero exit, any failed test case, or zero executed tests (a test that fails once and passes on `-retry-tests-on-failure` still counts as failed here — fail-closed on purpose). Report the
executed-test count in the gate summary.

### Gate 3 — No TODO/FIXME/HACK in changed files
```bash
git diff develop...HEAD --name-only -- '*.swift' | xargs grep -ln "TODO\|FIXME\|HACK" 2>/dev/null
```
Pass: no output. Fail: list every offending file and line.

### Gate 4 — Branch naming convention
```bash
git branch --show-current
```
Pass: branch matches one of `feature/*`, `fix/*`, `hotfix/*`, `release/*`, `spec/*`, `design/*`, `ci/*`, `chore/*`.
Fail: `main`, `develop`, or any non-conforming name — stop and ask the user to rename.

### Gate 5 — CHANGELOG.md has Unreleased entries
```bash
grep -A 10 "## \[Unreleased\]" CHANGELOG.md 2>/dev/null | grep -v "^##" | grep -v "^$"
```
Pass: at least one non-empty line under `## [Unreleased]`.
Fail: section missing or empty — create the section and add a one-line summary per task,
using `git log develop..HEAD --oneline` to enumerate commits. `/feature`'s two-commit-per-task
structure means only the GREEN (implementation) commit carries user-facing content — summarize
those, skipping RED (test-only) commits, which have nothing to summarize.
N/A: a PR that changes only `.claude/context/feature-log.md` (a standalone feature-log correction; `/release` now puts its entry in the release commit), and only if
this gate fails on it. A feature-log entry is not a user-facing change. Report `[–] N/A (feature-log only)`.

### Gate 6 — Coverage (conditional: new Swift files on branch)
```bash
git diff develop...HEAD --name-only --diff-filter=A -- '*.swift'
```
If any new `.swift` files are listed, run the `ios-coverage` skill to capture coverage and verify ≥80% on new code.
Skip this gate if the branch contains no new files (fixes and refactors only).

### Gate 7 — Security (conditional: sensitive code paths)
```bash
git diff develop...HEAD --name-only -- '*.swift' | grep -E "CSVImport|Repository|SwiftData|UserNotification"
```
If any matches, run the `security-review` skill before opening the PR.
Skip this gate if no sensitive files were modified.

### Gate 8 — CSV import concurrency shape (conditional: TransactionImportActor.swift changed)
```bash
git diff develop...HEAD --name-only -- '*.swift' | grep -q "TransactionImportActor.swift" && {
  grep -v "^\s*///\|^\s*//" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift | grep -n "@MainActor"
  grep -cE "func (existingHashes|save)\(.*\b(Account|Transaction|Category|Budget|ImportRecord)\b" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
  grep -c "modelContext\.save()" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
}
```
Pass: first grep returns no output (no `@MainActor` outside comments — the actor isn't main-actor-isolated); second grep count is `0` (no `@Model` type — `Account`/`Transaction`/`Category`/`Budget`/`ImportRecord` — appears as a parameter or return type on the protocol-conformance methods, i.e. nothing `@Model`-typed crosses the actor's public boundary; internal caching of a resolved `@Model` instance that never leaves the actor is fine and won't trigger this); third grep count is exactly `1` (one `modelContext.save()` per chunk, never per row).
Skip this gate if `TransactionImportActor.swift` is untouched on this branch.

### Gate 9 — Architecture & layer-rule compliance (AGENTS.md-enforced rules)
This is the single authoritative check for all layer-separation, type-safety, and
pattern rules. `/review` re-runs this gate's grep-only commands at the PR HEAD SHA and
compares the result to your gate summary (it does not re-run `xcodebuild`). If any command
below produces output, that's a violation to fix here, before opening the PR.
```bash
# Domain Services must have zero SwiftData imports
git diff develop...HEAD --name-only -- '*.swift' | grep '/Services/' | xargs grep -ln '^import SwiftData' 2>/dev/null

# Repository Protocols must import Foundation only — no SwiftData, no SwiftUI
git diff develop...HEAD --name-only -- '*.swift' | grep '/Repositories/Protocols/' | xargs grep -n '^import SwiftData\|^import SwiftUI' 2>/dev/null

# ViewModels must depend on repository protocols, never concrete SwiftData*Repository types
# (Tests/ excluded — FinanceTrackerTests/ViewModels/*.swift legitimately constructs concrete
# SwiftData*Repository instances against an in-memory ModelContainer, per AGENTS.md's own
# documented test pattern; that's not a production ViewModel violating the rule.)
git diff develop...HEAD --name-only -- '*.swift' | grep '/ViewModels/' | grep -v 'Tests/' | xargs grep -n 'SwiftData\w*Repository' 2>/dev/null

# Views must have no direct SwiftData access (no business logic beyond calling ViewModel methods)
git diff develop...HEAD --name-only -- '*.swift' | grep '/Views/' | xargs grep -ln '^import SwiftData' 2>/dev/null

# Money values must be Decimal, never Double — regex heuristic, NOT an AST check (see note below).
# (a) Declared as Double: `amount: Double`, `[Double]`, `[String: Double]`, `Double?`, `-> Double` / `-> [Double]` on a
#     money-named func, or an inferred-Double float literal (`var total = 0.0`, `let price = 9.99`).
git diff develop...HEAD --name-only -- '*.swift' | xargs grep -nHiE \
  -e '\b\w*(amount|balance|total|price|cost|budget|limit|spent|income|expense)\w*\s*:\s*(\[\s*(\w+\s*:\s*)?)?Double\b' \
  -e 'func\s+\w*(amount|balance|total|price|cost|budget|limit|spent|income|expense)\w*\s*\(.*\)\s*(async\s+)?(throws\s+)?->\s*(\[\s*(\w+\s*:\s*)?)?Double\b' \
  -e '\b\w*(amount|balance|total|price|cost|budget|limit|spent|income|expense)\w*\s*=\s*-?[0-9]+\.[0-9]+\b' 2>/dev/null
# (b) Conversions to Double: any `.doubleValue`, or `Double(` on a line naming a money stem.
#     Swift Charts plot values (`.value(...)` lines — the one boundary this codebase converts at) are excluded.
git diff develop...HEAD --name-only -- '*.swift' | xargs grep -nHiE \
  -e '\.doubleValue' \
  -e '(amount|balance|total|price|cost|budget|limit|spent|income|expense).*\bDouble\(' \
  -e '\bDouble\(.*(amount|balance|total|price|cost|budget|limit|spent|income|expense)' 2>/dev/null | grep -v '\.value('

# No try! or as! in changed production code (Tests/UITests excluded)
git diff develop...HEAD --name-only -- '*.swift' | grep -v 'Tests/' | xargs grep -nE '\btry!|as!' 2>/dev/null

# Unit/integration tests must use the Testing framework, never XCTest
git diff develop...HEAD --name-only -- 'FinanceTrackerTests/*.swift' | xargs grep -l 'XCTestCase\|import XCTest' 2>/dev/null

# UI test selectors must match a real accessibilityIdentifier in production views
grep -hro 'app\.\(buttons\|textFields\|staticTexts\)\["[^"]*"\]' FinanceTrackerUITests/*.swift 2>/dev/null | sort -u
# — then cross-check each literal against: grep -r 'accessibilityIdentifier' FinanceTracker/Views/

# New @Model types must be `final class` with a UUID id
git diff develop...HEAD --name-only --diff-filter=A -- '*.swift' | grep '/Models/' | xargs grep -L 'final class' 2>/dev/null
git diff develop...HEAD --name-only --diff-filter=A -- '*.swift' | grep '/Models/' | xargs grep -L 'var id: UUID\|let id: UUID' 2>/dev/null

# @Relationship declarations must specify deleteRule
git diff develop...HEAD --name-only -- '*.swift' | grep '/Models/' | xargs grep -n '@Relationship' 2>/dev/null | grep -v 'deleteRule'

# New Domain Services must have no stored mutable state — no `var` stored properties.
# Excludes computed properties (bodies opening with `{` or protocol `{ get }` requirements),
# which the naive pattern alone can't distinguish from genuinely stored `var`s.
git diff develop...HEAD --name-only --diff-filter=A -- '*.swift' | grep '/Services/' | xargs grep -nE '^\s*(private\s+)?var\s+\w+\s*[:=]' 2>/dev/null | grep -v '{\s*$' | grep -v '{ get'

# Transaction.importHash must remain present if Transaction.swift changed (invariants.md #2)
git diff develop...HEAD --name-only -- '*.swift' | grep -q 'Models/Transaction.swift' && grep -L 'importHash' FinanceTracker/Models/Transaction.swift
```
Pass: every command returns no output (the UI-selector listing is cross-checked by hand/agent against `FinanceTracker/Views/` — flag any selector with no matching `accessibilityIdentifier`; the `@Model`/`deleteRule` checks only fire when Models/ files are actually touched).
Fail: list every offending file and line, grouped by which rule it violates.

**The money check is a regex heuristic, not an AST check.** It matches identifier names, so it can
miss a `Double` behind a `typealias`, through a generic, or under a name with none of the listed stems,
and it can flag a non-money identifier that merely contains one (`totalPages: Double`). A real check
needs SwiftSyntax — a new dependency, out of scope here. Treat a hit as a violation unless it is a
dimensionless ratio (e.g. `BudgetCalculationService.swift`'s `percentUsed`, an accepted hit today), and
name each accepted hit in the gate summary so `/review` can tell it from a new one; treat silence as "no
match found", not proof.

**`importHash` golden test (conditional: `Gate 0` listed files, and the suite exists on `develop`).** The
grep above only proves the name `importHash` still appears; it cannot notice the hash *value* changing,
which silently breaks CSV dedup on re-import. The behavioral check is the Swift Testing suite
`ImportHashGoldenTests` (`FinanceTrackerTests/ImportHashGoldenTests.swift`). This is the one Gate 9 step
that runs `xcodebuild`, so it is `/gates`-only — `/review` does not re-run it:
```bash
GATE0="$(git rev-parse --git-dir)/gate0-$(git rev-parse HEAD)"
if [ ! -f "$GATE0" ]; then
  echo "GOLDEN FAIL: no Gate 0 result for this commit; run Gate 0 first"
elif [ ! -s "$GATE0" ]; then
  echo "GOLDEN SKIP: no build-relevant changes (Gate 0 empty)"
elif ! git cat-file -e develop:FinanceTrackerTests/ImportHashGoldenTests.swift 2>/dev/null; then
  echo "GOLDEN SKIP: ImportHashGoldenTests not on develop yet (merge-order dependency)"
elif [ ! -f FinanceTrackerTests/ImportHashGoldenTests.swift ]; then
  echo "GOLDEN FAIL: ImportHashGoldenTests.swift exists on develop but is missing on this branch"
else
  LOG=$(mktemp -t gate9-golden)
  xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
    -only-testing:FinanceTrackerTests/ImportHashGoldenTests > "$LOG" 2>&1; RC=$?
  PASSED=$(grep -E "^Test [Cc]ase 'ImportHashGoldenTests/.*' passed|^[✔✓] Test .*passed" "$LOG" | grep -vc "Test run with"); FAILED=$(grep -cE "^Test [Cc]ase '.*' failed|^[✘✗] Test .*failed" "$LOG")
  [ "$RC" -eq 0 ] && [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ] \
    && echo "GOLDEN PASS ($PASSED tests executed)" || echo "GOLDEN FAIL (xcodebuild exit $RC, passed=$PASSED, failed=$FAILED)"
fi
```
Pass: `GOLDEN PASS` with more than zero tests executed. `GOLDEN SKIP` is reported as `[–]` with its reason
(never `[✓]`). Fail: any `GOLDEN FAIL` — including the suite file missing on a branch whose `develop`
already has it, which is what a deleted or renamed golden test looks like. Never fix a failing
golden test by editing the expected value on a `feature/*` branch: an intentional hash-format change is a
`chore/*`/`fix/*` decision and needs a migration plan (invariants.md #2). The zero-test guard matters: a
misspelled or renamed suite passes `xcodebuild` with exit 0 and no tests.

## Gate summary

Report every gate before opening the PR. The first line is mandatory: the full SHA recorded in the
pre-step. `/review` compares it to the PR HEAD and rejects a summary that is missing or stale.
```
Gates run at <full 40-char SHA from `git rev-parse HEAD`>
Lane: <output of `python3 scripts/check_pr_lane.py --git origin/<base> --head-branch <branch> --base-branch <base>`, where <base> is the PR's base: `develop`, or `main` for `release/*` and a hotfix's first PR>
Gates:
[✓] Build
[✓] Tests — <N> tests executed
[✓] No TODO/FIXME/HACK
[✓] Branch naming
[✗] CHANGELOG — Unreleased section empty (auto-populating from git log...)
[–] Coverage — skipped (no new files)
[–] Security — skipped (no sensitive files)
[–] CSV import concurrency shape — skipped (TransactionImportActor.swift untouched)
[✓] Architecture & layer-rule compliance
[i] Abstraction bloat — no candidates found
[✓] RED-before-GREEN commit order
[i] Visual verification — screenshot captured, review above
[✓] Gate integrity
```

When Gates 1 and 2 are skipped:
```
Gates run at <full 40-char SHA>
Lane: <lane>
Gates:
[–] Build — skipped (no build-relevant changes)
[–] Tests — skipped (no build-relevant changes)
[✓] No TODO/FIXME/HACK
[✓] Branch naming
[✓] CHANGELOG
[–] Coverage — skipped (no Swift files)
[–] Security — skipped (no Swift files)
[–] CSV import concurrency shape — skipped (TransactionImportActor.swift untouched)
[✓] Architecture & layer-rule compliance
[i] Abstraction bloat — 1 candidate found (see report)
[–] RED-before-GREEN commit order — skipped (no new ViewModel/Service/Repository files)
[–] Visual verification — skipped (no Views/ changes)
[✓] Gate integrity
```

Fix any failures before continuing.

## Autonomous gate-fixing loop
If gates fail and need iterative fixes, use the `/loop` prompts in `reference.md` § Autonomous gate-fixing loop, run as a separate top-level command. Adding, renaming or removing a gate: update that loop's stop condition (gate count, advisory list) in the same commit.

### Gate 10 — Abstraction bloat / duplication (heuristic, advisory)
```bash
# New protocols introduced on this branch
git diff develop...HEAD --name-only --diff-filter=A -- '*.swift' | xargs grep -Eln "^((public|internal|package|private|fileprivate|open|nonisolated|@[A-Za-z]+) )*protocol " 2>/dev/null

# Duplicated added lines (non-blank, appearing 2+ times across the diff) — copy-paste signal
git diff develop...HEAD -- '*.swift' | grep -E '^\+[^+]' | sed 's/^\+//' | grep -v '^\s*$' | sort | uniq -d
```
For each new protocol found, check its conformance count: `grep -rn ": <ProtocolName>" --include=*.swift .` A protocol with exactly one conforming type, outside the established `<Repository>Protocol`-style pattern (where a single implementation plus a test mock is expected), is a candidate for inlining.

For duplicated lines, flag any run of 3+ consecutive duplicated added lines as a candidate for extraction into a shared helper. Exception: the verbatim `#if compiler(>=6.4)` / `#else` protocol duplication that invariant #6 requires is intentional (`nonisolated` can't be conditionally applied to a lone modifier) — don't report it as an extraction candidate.

This gate is advisory: list candidates in the gate summary but do not block the PR on them. Final judgment on whether to extract or inline is a human or `/review` call.

### Gate 11 — RED-before-GREEN commit order (conditional: new ViewModel/Service/Repository files)
```bash
python3 scripts/check_tdd_commit_order.py
```
For every new file under `FinanceTracker/ViewModels/`, `FinanceTracker/Services/`, or
`FinanceTracker/Repositories/SwiftData/` on this branch that has a matching `*Tests.swift`
file, the script checks that the test file was added in a strictly earlier commit than the
implementation — never the same commit, never a later one (why: `reference.md` § Gate 11).

Pass: script exits 0 (no violations, or nothing in scope to check).
Fail: script lists each violation (file, commit, reason) — fix by re-doing the task as two
commits (test-only, confirm it fails, then implementation) per `/feature`'s per-task rules.
Nothing checked (exit 2): the script warns that no file in the repo matches `SCOPED_LAYER_DIRS`,
which happens if the layer folders were renamed or moved. Update `SCOPED_LAYER_DIRS` to the
current folders and re-run. Do not treat exit 2 as a pass; it means the gate checked nothing. Report it as `[✗]`.
Rewriting already-pushed history is not required or expected; this gate only evaluates the
branch as it stands when `/gates` runs.
Skip this gate if the branch adds no new files under the scoped directories, but only after
confirming those directories still exist; if they were renamed, run the script to get exit 2.

### Gate 12 — Visual verification (advisory, conditional: Views/ changed)
```bash
git diff develop...HEAD --name-only -- '*.swift' | grep '/Views/'
```
Skip this gate if this returns no output — no UI-facing changes to verify visually. Also
skip, reporting `[–] Visual verification — skipped (XcodeBuildMCP simulator tools
unavailable)`, if the XcodeBuildMCP simulator/UI-automation tools are not available in this
session — this is a spike, not a hard dependency for `/gates` to run.

If any `Views/` files changed, capture the screen with the XcodeBuildMCP steps in `reference.md` § Gate 12 (reuse Gate 1's build; never call `build_run_sim`). This gate captures evidence and never blocks: report `[i]`, never `[✓]`/`[✗]`. The "does this look right" call is Akshay's, made by looking at the screenshot before merging.

### Gate 13 — Gate integrity (floor-guard)
```bash
python3 scripts/check_gate_integrity.py
```
On a `release/*` or `hotfix/*` branch (which PRs against `main`, not `develop`), pass the correct base
explicitly instead: `python3 scripts/check_gate_integrity.py main`.

Detects gate-weakening — a gate-definition file edited on a `feature/*` branch, a test deleted instead
of fixed, a new suppression marker, an unfinished stub, or a lowered threshold — rather than
code-quality issues. It is the diff-detectable half of "Guard against self-modifying guardrail files" below; the live half is
`.claude/hooks/guard_protected_paths.py`.

Pass: script exits 0. Fail: script lists each violation — fix the underlying issue, or, if the
gate-definition change is legitimate maintenance, move it to its own `chore/*` or `fix/*` branch instead
of bundling it with feature work. If `scripts/check_gate_integrity.py` does not exist, this gate FAILS
(report `[✗] Gate integrity — script missing`); never skip it as "not applicable".

## After all gates pass — open the PR

### Write candidate invariants (conditional)
If any gate caught a violation pattern that is NOT already listed in `.claude/context/invariants.md`, write it as a candidate comment:

```
<!-- [CANDIDATE] YYYY-MM-DD: <describe the violation pattern — e.g. "ViewModel imported SwiftDataRepository directly in feature/X"> -->
```

- **On a `feature/*` branch, do not write to `invariants.md`** — `.claude/hooks/guard_protected_paths.py` blocks the edit and Gate 13 flags it, and the write would also change the tree after the SHA was pinned. Put the comment line under a `## Candidate invariants` heading in the PR body instead; it gets appended to the file from a `chore/*` branch.
- On any other branch, append it at the bottom of that file, commit it, and restart from the pre-step — the commit moves HEAD, so the gate summary must be re-run against the new SHA.

Do not promote it to a numbered invariant — that is a human decision made during the next `/pipeline-review`.

Include the actual Gate summary output (from above, starting with its `Gates run at <sha>` line) in the
PR body under its own section — `/review` checks that SHA against the PR HEAD and re-runs the
deterministic gates itself, comparing its results to this block.

If the `Lane:` line says `pipeline` (or the PR touches pipeline paths alongside app code), also add a
`Motivating incident: <what went wrong, with a link or date>` line to the PR body, or
`Motivating incident: none (<reason>)`. The `review-evidence` check fails a pipeline-lane PR
without a non-empty one.

```bash
gh pr create \
  --title "<type>(<scope>): <description>" \
  --base develop \
  --body "$(cat <<'EOF'
## Summary
- <bullet per task from the plan>

## Gates
<paste the actual Gate summary block from this run — the `Gates run at <sha>` line, plus each gate's ✓/✗/– status>

## Test plan
- [ ] Full test suite passes (TEST SUCCEEDED)
- [ ] Tested on iPhone 17 simulator

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

If `/gates` is re-run after the PR is open (a fix cycle changes HEAD), update the PR body's gate section with the new summary — `gh pr edit <PR> --body-file <file>` — so its `Gates run at <sha>` matches the new HEAD; `/review` rejects a stale one.

**Always pass `--base develop`** — `gh pr create` defaults to `main` (repo default), which bypasses gitflow.
Exceptions: `release/*` and `hotfix/*` branches use `--base main`, except a hotfix's second PR back to `develop`, which uses `--base develop` (see `/bugfix`).

## Guard against self-modifying guardrail files

`.claude/hooks/guard_protected_paths.py` (a `PreToolUse` hook) blocks edits to the guarded files on a `feature/*` branch, and Gate 13 plus the `gates` CI job catch the same set on a plain commit and push. What each layer covers, what it misses, and where the pattern came from: `reference.md` § Guard. Known gaps, so a clean gate summary is not read as proof: the hook fails open on a detached HEAD and allows every edit off `feature/*`, it does not load in a session started from `~/Desktop/Claude` (the parent directory), and its Bash-write detection is best effort.

## Done when
All 13 gates report (11 blocking gates pass; Gates 10 and 12 are advisory, see their own
sections above), the summary opens with `Gates run at <sha>`, PR is open, and the PR URL is returned to the user.

## Tip — chain into code-review + review
Once the PR is open, run `/pr-followup <PR>` to run `code-review` (medium)
and then `/review`, and record both in the PR body for the `review-evidence`
check. `/test` runs before `/gates`, not after the PR opens.
