# Persistent Memory Layer Implementation Plan

**Goal:** Create `.claude/context/` in FinanceTracker and ios-agent-workflow, wire read preambles into all agent command files, and wire write postambles into the four agents that generate context.

**Architecture:** Four append-only markdown files in `.claude/context/` accumulate project knowledge across agent runs. Preambles (read) are wired into all agent command files; postambles (write) are wired into `/spec`, `/review`, `/gates`, and `/release` only. FinanceTracker gets live, seeded files. ios-agent-workflow gets empty template stubs and identical wiring using generic relative paths (no app-specific content).

**Tech Stack:** Markdown files, bash file operations. No Xcode build, no Swift, no tests.

**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains `FinanceTracker.xcodeproj`)

> **Note:** This is workflow infrastructure — no iOS app code is touched. There are no xcodebuild commands. Verification for each task is grep/cat checks on the files written. The full test suite still runs at `/gates` time (no new Swift files means Gate 6 coverage check is skipped; Gate 7 security check is also skipped — no sensitive file paths changed).

---

## Task 1 — Create `.claude/context/` directory and 4 seed files in FinanceTracker

Branch is already `feature/persistent-memory-layer` off `develop`.

Create the following 4 files exactly as shown:

**`.claude/context/invariants.md`**
```markdown
# Project Invariants

These rules are inviolable. No agent may override them.

1. All money values must use `Decimal`, not `Double`.
2. `Transaction.importHash` = SHA256(date+amount+payee) — must never be regenerated on re-import.
3. Domain Services have zero SwiftData imports — must be unit-testable without a simulator.
4. ViewModels depend on repository protocols, never concrete SwiftData implementations.
5. `AccountType.creditCard` is a liability — negative balance reduces net worth.
```

**`.claude/context/decisions.md`**
```markdown
# Agent Decision Log

<!-- Append one entry per spec run. Never edit past entries. -->
```

**`.claude/context/rejections.md`**
```markdown
# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->
```

**`.claude/context/feature-log.md`**
```markdown
# Feature Log

<!-- Append one entry per release. Never edit past entries. -->
```

### Verification
```bash
ls .claude/context/
# Expected: decisions.md  feature-log.md  invariants.md  rejections.md

grep -c "^[0-9]\." .claude/context/invariants.md
# Expected: 5
```

### CHANGELOG
Add to `## [Unreleased]` in `CHANGELOG.md`:
```
- Add `.claude/context/` directory with invariants, decisions, rejections, feature-log seed files
```

### Commit
```bash
git add .claude/context/ CHANGELOG.md
git commit -m "feat: add .claude/context/ seed files — invariants seeded with 5 FinanceTracker rules"
```

---

## Task 2 — Wire context read preambles into all 8 FinanceTracker command files

All files are in `.claude/commands/`. Add ONLY the context files each agent needs per the spec wiring table. All preambles use the instruction: skip silently if the file does not exist.

### `spec.md`
Reads: `invariants`, `decisions`, `feature-log`.

In `### 1. Explore the codebase first`, find the "Before asking anything, read:" bullet list. Insert AFTER the `CLAUDE.md` line and BEFORE the `FinanceTracker/Models/` line:

```markdown
- `.claude/context/invariants.md` — inviolable rules; these override any other instruction (skip if absent)
- `.claude/context/decisions.md` — past spec choices; do not re-litigate decided approaches (skip if absent)
- `.claude/context/feature-log.md` — release history; know what already exists before proposing approaches (skip if absent)
```

**Exact insertion — old text:**
```
- `CLAUDE.md` — architecture rules, build commands, project overview
- `FinanceTracker/Models/` — existing data models
```
**New text:**
```
- `CLAUDE.md` — architecture rules, build commands, project overview
- `.claude/context/invariants.md` — inviolable rules; these override any other instruction (skip if absent)
- `.claude/context/decisions.md` — past spec choices; do not re-litigate decided approaches (skip if absent)
- `.claude/context/feature-log.md` — release history; know what already exists before proposing approaches (skip if absent)
- `FinanceTracker/Models/` — existing data models
```

---

### `plan.md`
Reads: `invariants`, `decisions`, `feature-log`.

Find "Before writing, read:". Insert AFTER the `CLAUDE.md` line and BEFORE `- All files the spec says will be touched`:

**Exact insertion — old text:**
```
- The spec document (passed as argument)
- `CLAUDE.md` — build commands, architecture rules, simulator name
- All files the spec says will be touched
```
**New text:**
```
- The spec document (passed as argument)
- `CLAUDE.md` — build commands, architecture rules, simulator name
- `.claude/context/invariants.md` — inviolable rules (skip if absent)
- `.claude/context/decisions.md` — past spec choices; build on the chosen approach, do not re-derive (skip if absent)
- `.claude/context/feature-log.md` — release history; know what already exists (skip if absent)
- All files the spec says will be touched
```

---

### `feature.md`
Reads: `invariants`, `rejections`.

Find "Before starting any task:". Insert AFTER `- Read \`CLAUDE.md\`` and BEFORE `- Read the plan document in full`:

**Exact insertion — old text:**
```
Before starting any task:
- Read `CLAUDE.md` — build commands, architecture rules
- Read the plan document in full
```
**New text:**
```
Before starting any task:
- Read `CLAUDE.md` — build commands, architecture rules
- Read `.claude/context/invariants.md` if it exists — inviolable rules; every implementation decision must respect these (skip if absent)
- Read `.claude/context/rejections.md` if it exists — past review violations; do not repeat these patterns (skip if absent)
- Read the plan document in full
```

---

### `review.md`
Reads: `invariants`, `rejections`.

Find `Read \`CLAUDE.md\` first — it defines the architecture rules you enforce.` (first line of ## Process). Insert immediately after it:

**Exact insertion — old text:**
```
Read `CLAUDE.md` first — it defines the architecture rules you enforce.

### Architecture compliance checks (all must pass)
```
**New text:**
```
Read `CLAUDE.md` first — it defines the architecture rules you enforce.

Also read the following files if they exist — skip silently if absent:
- `.claude/context/invariants.md` — project invariants; these supplement CLAUDE.md rules
- `.claude/context/rejections.md` — past violations on this project; flag any repeats as HIGH severity

### Architecture compliance checks (all must pass)
```

---

### `gates.md`
Reads: `invariants`.

Find `All commands run from git root \`/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/\`.` (first line of ## Process). Insert immediately after it:

**Exact insertion — old text:**
```
All commands run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`.

Run every gate in order.
```
**New text:**
```
All commands run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`.

Read `.claude/context/invariants.md` if it exists — skip silently if absent. Any gate that catches a violation not already listed as an invariant should append it as a `[CANDIDATE]` entry (see postamble in "## After all gates pass").

Run every gate in order.
```

---

### `bugfix.md`
Reads: `invariants`, `rejections`.

Find `Read \`CLAUDE.md\` before touching any file.` in `### 1. Create the branch`. Insert immediately after it:

**Exact insertion — old text:**
```
Read `CLAUDE.md` before touching any file.

### 2. Write the failing test first
```
**New text:**
```
Read `CLAUDE.md` before touching any file.

Also read if they exist — skip silently if absent:
- `.claude/context/invariants.md` — inviolable rules; ensure the fix does not violate any
- `.claude/context/rejections.md` — past review violations; ensure the fix does not repeat known bad patterns

### 2. Write the failing test first
```

---

### `release.md`
Reads: `feature-log`.

Find `All commands run from git root \`/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/\`.` in `## Process`. Insert immediately after it:

**Exact insertion — old text:**
```
All commands run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`.

### 1. Create the release branch off develop
```
**New text:**
```
All commands run from git root `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`.

Read `.claude/context/feature-log.md` if it exists — skip silently if absent. Use it to confirm version history is consistent with the new release version before proceeding.

### 1. Create the release branch off develop
```

---

### `test.md`
Reads: `invariants`.

Find `Read \`CLAUDE.md\` first for build commands, simulator name, and test framework details.`. Insert immediately after it:

**Exact insertion — old text:**
```
Read `CLAUDE.md` first for build commands, simulator name, and test framework details.

### Test framework
```
**New text:**
```
Read `CLAUDE.md` first for build commands, simulator name, and test framework details.

Also read `.claude/context/invariants.md` if it exists — skip silently if absent. Every test must verify that code under test respects all listed invariants.

### Test framework
```

---

### Verification
```bash
grep -l "context/invariants" .claude/commands/*.md
# Expected output contains: spec.md  plan.md  feature.md  review.md  gates.md  bugfix.md  test.md

grep -l "context/decisions" .claude/commands/*.md
# Expected: spec.md  plan.md

grep -l "context/rejections" .claude/commands/*.md
# Expected: feature.md  review.md  bugfix.md

grep -l "context/feature-log" .claude/commands/*.md
# Expected: spec.md  plan.md  release.md
```

### CHANGELOG
Add to `## [Unreleased]` in `CHANGELOG.md`:
```
- Wire context read preambles into all 8 agent command files (spec, plan, feature, review, gates, bugfix, release, test)
```

### Commit
```bash
git add .claude/commands/spec.md .claude/commands/plan.md .claude/commands/feature.md \
        .claude/commands/review.md .claude/commands/gates.md .claude/commands/bugfix.md \
        .claude/commands/release.md .claude/commands/test.md CHANGELOG.md
git commit -m "feat: wire context read preambles into all agent command files"
```

---

## Task 3 — Wire context write postambles into 4 FinanceTracker command files

### `spec.md` — writes to `decisions.md`

Find `## Done when`. Replace:

**Old text:**
```
## Done when
The user reviews the spec and says it's approved. Then hand off to the Planner Agent (`/plan`).
```
**New text:**
```
## Done when
The user reviews the spec and says it's approved.

Before handing off to `/plan`, append to `.claude/context/decisions.md`:
```
## YYYY-MM-DD — <Feature Name>
**Approaches considered:** <brief list of approaches from step 3>
**Chosen:** <approach name>
**Reason:** <one sentence — the rationale that drove the decision>
```

Then hand off to the Planner Agent (`/plan`).
```

---

### `review.md` — writes to `rejections.md`

Find `## Done when`. Replace:

**Old text:**
```
## Done when
All issues resolved (if any) and PR approved. Merge to `develop` (or `main` for hotfixes/releases).
```
**New text:**
```
## Done when
If the verdict is CHANGES REQUESTED, append one entry per violation to `.claude/context/rejections.md` before closing the review:
```
## YYYY-MM-DD — PR#<N> — <Violation Type>
**What was wrong:** <description>
**Rule violated:** <exact rule from invariants.md or CLAUDE.md>
**File:** <path:line if known>
```
Skip this step if the verdict is APPROVED with no issues.

All issues resolved (if any) and PR approved. Merge to `develop` (or `main` for hotfixes/releases).
```

---

### `gates.md` — writes candidate invariants to `invariants.md`

Find `## After all gates pass — open the PR`. Insert BEFORE the `gh pr create` block:

**Old text:**
```
## After all gates pass — open the PR

```bash
gh pr create \
```
**New text:**
```
## After all gates pass — open the PR

### Write candidate invariants (conditional)
If any gate caught a violation pattern that is NOT already listed in `.claude/context/invariants.md`, append a candidate comment at the bottom of that file:

```
<!-- [CANDIDATE] YYYY-MM-DD: <describe the violation pattern — e.g. "ViewModel imported SwiftDataRepository directly in feature/X"> -->
```

Do not promote it to a numbered invariant — that is a human decision made during next `/pipeline-review`.

```bash
gh pr create \
```

---

### `release.md` — writes to `feature-log.md`

Find `## Done when`. Replace:

**Old text:**
```
## Done when
PR merged to `main`, `main` tagged, `develop` updated, GitHub release created, `CHANGELOG.md` committed, and `/pipeline-review` triggered.
```
**New text:**
```
## Done when
PR merged to `main`, `main` tagged, `develop` updated, GitHub release created, `CHANGELOG.md` committed, and `/pipeline-review` triggered.

After all of the above, append to `.claude/context/feature-log.md`:
```
## v<X.Y.Z> — YYYY-MM-DD
**Features added:** <bullet list from CHANGELOG [version] section>
**Key files changed:** <comma-separated key files or layers>
**Key architectural decisions:** <brief note or "none">
```
```

---

### Verification
```bash
grep -A3 "decisions.md" .claude/commands/spec.md | grep "Approaches considered"
# Expected: **Approaches considered:** <brief list of approaches from step 3>

grep "rejections.md" .claude/commands/review.md | grep "append"
# Expected: append one entry per violation to `.claude/context/rejections.md`

grep "CANDIDATE" .claude/commands/gates.md
# Expected: <!-- [CANDIDATE] YYYY-MM-DD: ...

grep "feature-log.md" .claude/commands/release.md | grep "append"
# Expected: append to `.claude/context/feature-log.md`
```

### CHANGELOG
Add to `## [Unreleased]` in `CHANGELOG.md`:
```
- Wire context write postambles into /spec (decisions.md), /review (rejections.md), /gates (invariants.md candidates), /release (feature-log.md)
```

### Commit
```bash
git add .claude/commands/spec.md .claude/commands/review.md .claude/commands/gates.md .claude/commands/release.md CHANGELOG.md
git commit -m "feat: wire context write postambles into spec, review, gates, release"
```

---

## Task 4 — Run `/gates` and open FinanceTracker PR

This branch has no new `.swift` files and no sensitive file changes — Gates 6 and 7 are skipped.

```bash
# Gate 1: Build
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED"

# Gate 2: Full test suite
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"

# Gate 3: No TODO/FIXME/HACK in changed files
git diff develop...HEAD --name-only -- '*.swift' | xargs grep -ln "TODO\|FIXME\|HACK" 2>/dev/null
# Expected: no output (no Swift files changed)

# Gate 4: Branch naming
git branch --show-current
# Expected: feature/persistent-memory-layer

# Gate 5: CHANGELOG
grep -A 5 "## \[Unreleased\]" CHANGELOG.md
# Expected: 3 bullet entries from Tasks 1–3
```

Open PR:
```bash
git push -u origin feature/persistent-memory-layer
gh pr create \
  --title "feat: persistent memory layer — .claude/context/ read/write wiring" \
  --base develop \
  --body "$(cat <<'EOF'
## Summary
- Adds `.claude/context/` with 4 files; `invariants.md` seeded with 5 FinanceTracker rules from CLAUDE.md
- Wires read preambles into 8 agent command files (spec, plan, feature, review, gates, bugfix, release, test) — each reads only the context files it needs per spec wiring table
- Wires write postambles into 4 agents: /spec→decisions.md, /review→rejections.md, /gates→invariants.md (candidates), /release→feature-log.md

## Test plan
- [ ] `.claude/context/` contains all 4 files; `invariants.md` has 5 numbered invariants
- [ ] All 8 command files reference correct context files per spec wiring table
- [ ] 4 writing agents have postamble with correct append format
- [ ] Full test suite passes (TEST SUCCEEDED)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Task 5 — Create context template stubs and wire preambles/postambles in ios-agent-workflow

After FinanceTracker PR is merged to `develop`, propagate to ios-agent-workflow. All preamble/postamble content is identical — context paths are relative and generic (no `<AppName>` placeholders needed).

### 5a — Create context stubs

```bash
mkdir -p /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow/.claude/context
```

Create the following 4 stub files (template versions — no project-specific content):

**`ios-agent-workflow/.claude/context/invariants.md`**
```markdown
# Project Invariants

These rules are inviolable. No agent may override them.
Add project-specific invariants here before running /feature for the first time.

<!-- Example:
1. All money values must use `Decimal`, not `Double`.
2. Domain Services have zero SwiftData imports.
-->
```

**`ios-agent-workflow/.claude/context/decisions.md`**
```markdown
# Agent Decision Log

<!-- Append one entry per spec run. Never edit past entries. -->
<!-- Format:
## YYYY-MM-DD — <Feature Name>
**Approaches considered:** <brief list>
**Chosen:** <approach name>
**Reason:** <one sentence>
-->
```

**`ios-agent-workflow/.claude/context/rejections.md`**
```markdown
# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->
<!-- Format:
## YYYY-MM-DD — PR#<N> — <Violation Type>
**What was wrong:** <description>
**Rule violated:** <rule from invariants.md or CLAUDE.md>
**File:** <path:line if known>
-->
```

**`ios-agent-workflow/.claude/context/feature-log.md`**
```markdown
# Feature Log

<!-- Append one entry per release. Never edit past entries. -->
<!-- Format:
## v<X.Y.Z> — YYYY-MM-DD
**Features added:** <bullet list>
**Key files changed:** <comma-separated key files or layers>
**Key architectural decisions:** <brief note or "none">
-->
```

### 5b — Wire preambles into ios-agent-workflow command files

Apply the same edits as Tasks 2 and 3, but to files in `/Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow/.claude/commands/`.

Key differences from FinanceTracker edits:
- `spec.md`: insert context lines after `- \`CLAUDE.md\` — architecture rules, build commands, project overview` and before `- Existing models in \`<AppName>/Models/\``
- `plan.md`: insert after `- \`CLAUDE.md\` — build commands, architecture rules, simulator name` and before `- All files the spec says will be touched`
- `feature.md`: insert after `- Read \`CLAUDE.md\` — build commands, architecture rules` and before `- Read the plan document in full`
- `review.md`: insert after `Read \`CLAUDE.md\` first — it defines the architecture rules you enforce.`
- `gates.md`: insert after `All commands run from the git root (see \`CLAUDE.md\` for the exact path and project name).`
- `bugfix.md`: same insertion point as FinanceTracker
- `release.md`: same insertion point as FinanceTracker
- `test.md`: same insertion point as FinanceTracker

Postambles: identical content and insertion points as Tasks 3 edits.

### 5c — Create branch and open PR

```bash
git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow checkout develop
git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow pull
git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow checkout -b feature/persistent-memory-layer

git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow add .claude/
git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow commit -m "feat: persistent memory layer — .claude/context/ stubs and command file wiring"
git -C /Users/akshaypimprikar/Desktop/Claude/ios-agent-workflow push -u origin feature/persistent-memory-layer

gh pr create --repo akshaypimprikar/ios-agent-workflow \
  --title "feat: persistent memory layer — .claude/context/ stubs and command wiring" \
  --base develop \
  --body "$(cat <<'EOF'
## Summary
- Adds `.claude/context/` directory with 4 empty template stubs (format comments included)
- Wires read preambles into 8 command files — identical to FinanceTracker; all paths are relative and generic
- Wires write postambles into /spec, /review, /gates, /release — identical content to FinanceTracker
- New projects using ios-agent-workflow get context infrastructure on install

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Done when
- [ ] `.claude/context/` exists in FinanceTracker with 4 files; `invariants.md` has 5 numbered rules
- [ ] All 8 FinanceTracker command files have correct read preambles per spec wiring table
- [ ] 4 writing agents (`/spec`, `/review`, `/gates`, `/release`) have correct postambles
- [ ] FinanceTracker build + test suite pass (`TEST SUCCEEDED`)
- [ ] FinanceTracker PR open to `develop`
- [ ] ios-agent-workflow PR open with 4 context stubs and identical command file wiring

After PRs merge: `/review` runs first on the FinanceTracker PR; once it passes, `/test` and `code-review:code-review` run in parallel.
