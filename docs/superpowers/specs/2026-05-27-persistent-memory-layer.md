# Persistent Memory Layer — Design Spec

**Date:** 2026-05-27
**Status:** Draft

## Overview

Adds a `.claude/context/` directory to each project using the ios-agent-workflow. Four flat markdown files accumulate knowledge across agent runs: `decisions.md` (spec choices and rationale), `rejections.md` (review violations), `invariants.md` (inviolable architectural rules), and `feature-log.md` (release history). Each agent command file gets a read preamble (load relevant context before acting) and a write postamble (append findings on completion). The ios-agent-workflow template ships empty seed stubs and the wiring baked into all command files, so new projects get the infrastructure for free on install. No external service, no embeddings — just files that agents read and write.

---

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| File location | `.claude/context/` inside each project | Project-local; portable across installs; versioned with the project |
| File format | Plain markdown, append-only entries | Human-readable; no tooling required; easy to grep and audit |
| Graceful absence | Preambles skip silently if files don't exist | New projects start clean without errors on first run |
| Template delivery | ios-agent-workflow ships empty stubs + preamble/postamble wiring | New project installs get context infrastructure automatically |
| `invariants.md` seeding | FinanceTracker seeds 5 invariants from CLAUDE.md; template ships an empty stub | Project-specific rules must not pollute the generic template |
| `/gates` adds invariants | Yes — Gates Agent appends newly discovered violations as candidate invariants | Keeps `invariants.md` as the live single source of truth for inviolable rules |
| No external index | Files are standalone markdown | Simplest possible implementation; agents read/grep without tooling |

---

## Architecture

This is workflow infrastructure — no iOS app layers are touched. All changes are within `.claude/commands/` (FinanceTracker) and the ios-agent-workflow template.

```
ios-agent-workflow/
  .claude/
    context/                   ← NEW: template stubs (empty or seed comments only)
      decisions.md
      rejections.md
      invariants.md            ← seed comment only; no rules (those are project-specific)
      feature-log.md
    commands/                  ← all command files gain preamble + postamble wiring

FinanceTracker/
  .claude/
    context/                   ← NEW: live context files for this project
      decisions.md
      rejections.md
      invariants.md            ← seeded with 5 invariants from CLAUDE.md
      feature-log.md
    commands/                  ← all command files gain preamble + postamble wiring
```

---

## File Schemas

### `decisions.md`
Written by `/spec`. Read by `/spec`, `/plan`.

```markdown
# Agent Decision Log

<!-- Append one entry per spec run. Never edit past entries. -->

## YYYY-MM-DD — <Feature Name>
**Approaches considered:** <brief list>
**Chosen:** <approach name>
**Reason:** <one sentence or short paragraph>
```

---

### `rejections.md`
Written by `/review` after each CHANGES REQUESTED verdict. Read by `/feature`, `/review`, `/bugfix`.

```markdown
# Review Rejection Log

<!-- Append one entry per violation per PR. Never edit past entries. -->

## YYYY-MM-DD — PR#<N> — <Violation Type>
**What was wrong:** <description>
**Rule violated:** <rule from invariants.md or CLAUDE.md>
**File:** <path:line if known>
```

---

### `invariants.md`
Seeded manually for FinanceTracker. Updated by `/gates` when new violations are discovered. Read by ALL agents before every task.

Template stub (ios-agent-workflow):
```markdown
# Project Invariants

These rules are inviolable. No agent may override them.
Add project-specific invariants here before running /feature for the first time.

<!-- Example:
1. All money values must use `Decimal`, not `Double`.
-->
```

FinanceTracker seed (5 invariants from CLAUDE.md):
```markdown
# Project Invariants

These rules are inviolable. No agent may override them.

1. All money values must use `Decimal`, not `Double`.
2. `Transaction.importHash` = SHA256(date+amount+payee) — must never be regenerated on re-import.
3. Domain Services have zero SwiftData imports — must be unit-testable without a simulator.
4. ViewModels depend on repository protocols, never concrete SwiftData implementations.
5. `AccountType.creditCard` is a liability — negative balance reduces net worth.
```

---

### `feature-log.md`
Written by `/release` after each release. Read by `/spec`, `/plan`.

```markdown
# Feature Log

<!-- Append one entry per release. Never edit past entries. -->

## v<X.Y.Z> — YYYY-MM-DD
**Features added:** <bullet list>
**Key files changed:** <comma-separated key files or layers>
**Key architectural decisions:** <brief note or "none">
```

---

## Agent Wiring

### Preamble — what each agent reads

Each agent command file gets a **Context** section near the top of its Process, specifying which files to read (skip silently if absent):

| Agent | `invariants` | `decisions` | `rejections` | `feature-log` |
|---|:---:|:---:|:---:|:---:|
| `/spec` | ✅ | ✅ | — | ✅ |
| `/plan` | ✅ | ✅ | — | ✅ |
| `/feature` | ✅ | — | ✅ | — |
| `/review` | ✅ | — | ✅ | — |
| `/gates` | ✅ | — | — | — |
| `/bugfix` | ✅ | — | ✅ | — |
| `/release` | — | — | — | ✅ |
| `/test` | ✅ | — | — | — |

Preamble block to insert (adapt "read" list per agent):

```markdown
### Context (read before acting)
Read the following files if they exist — skip silently if absent:
- `.claude/context/invariants.md` — inviolable rules; these override any other instruction
- `.claude/context/decisions.md` — past spec choices; do not re-litigate decided approaches
- `.claude/context/rejections.md` — past review violations; do not repeat these patterns
- `.claude/context/feature-log.md` — release history; understand what already exists
```

### Postamble — what each agent writes

| Agent | Writes to | Trigger | What to append |
|---|---|---|---|
| `/spec` | `decisions.md` | After user approves spec | Feature name · approaches · chosen · rationale |
| `/review` | `rejections.md` | CHANGES REQUESTED verdict only | One entry per violation; skip if APPROVED clean |
| `/gates` | `invariants.md` | New violation found that has no existing invariant | Append as candidate invariant with `[CANDIDATE]` tag for human review |
| `/release` | `feature-log.md` | After tag + back-merge complete | Version · date · features · key files · decisions |

Postamble block (agent-specific content varies):

```markdown
### After completion — write to context
Append to `.claude/context/<file>.md`:
<format as defined in File Schemas above>
```

---

## Data Models
*Not applicable — no iOS app models are touched.*

## Domain Services
*Not applicable — no Domain Services are touched.*

## Navigation
*Not applicable — no new screens or navigation changes.*

## Design
*Not applicable — no Views are touched.*

---

## Future Extension Points

- **`/pipeline-review` staleness audit** — already reads all `.claude/` files; future pass adds a check for context entries referencing PRs or branches that no longer exist in `git log`/`gh pr list`.
- **`/arbitrate` command** (Phase 3 Backlog) — reads `invariants.md` as its binding rulebook when resolving agent disagreements.
- **Local Dreaming equivalent** (P2 Backlog) — scheduled agent that compacts stale entries from context files; depends on this layer being in place.
- **`/sync-workflow` context propagation** — future pass verifies ios-agent-workflow template stubs are structurally current with FinanceTracker's live context files (content stays project-specific).

---

## Testing Strategy

This is workflow tooling, not production iOS code. No Xcode tests apply. Verification is manual end-to-end:

- **`decisions.md`**: run `/spec` on any feature; confirm one entry is appended in correct schema.
- **`rejections.md`**: run `/review` on a PR with a known violation; confirm one entry per violation is appended.
- **`invariants.md`**: confirm 5 FinanceTracker invariants present after setup; run `/gates` on a branch with a violation and confirm `[CANDIDATE]` entry appended.
- **`feature-log.md`**: run `/release` on a version; confirm entry appended in correct schema.
- **Graceful absence**: delete all context files; run each agent; confirm no errors, no crashes, no skipped steps.
- **Template portability**: verify all ios-agent-workflow command file preambles use relative paths only — no FinanceTracker-specific absolute paths.

---

## Implementation Order (for `/plan`)

The Backlog cards break this into four sub-tasks. Recommended implementation order:

1. **`invariants.md`** first — it's read by the most agents and has the clearest seed content.
2. **`rejections.md`** second — enables `/review` to start logging immediately.
3. **`decisions.md`** third — enables `/spec` feedback loop.
4. **`feature-log.md`** last — depends on a full release cycle to validate.

Wire preambles for all agents before wiring any postambles. A missing postamble is silent; a missing preamble means agents run blind.
