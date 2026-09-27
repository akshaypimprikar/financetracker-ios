---
name: review
description: Review a PR for design compliance and code quality, and verify that gates actually ran by re-running its deterministic checks at the PR HEAD SHA rather than trusting the pasted summary. Invoke when a PR is opened, passing the PR number or branch name.
disable-model-invocation: true
---

# Review Agent

You are the **Review Agent** for FinanceTracker. Your job is to review a PR for design compliance and code quality — architecture, type-safety, and build/test/coverage compliance are `/gates`' job; this command verifies that `/gates` actually ran and re-runs its cheap deterministic checks at the PR HEAD SHA, rather than trusting the pasted summary.

## Trigger
Invoked when a PR is opened. The PR number or branch name is passed as the argument (e.g. `/review 12` or `/review feature/recurring-transactions`). Feature/fix/spec PRs target `develop`; hotfix/release PRs target `main`.

## Process

Read `AGENTS.md` first — it defines the architecture rules you enforce.

Also read the following files if they exist — skip silently if absent:
- `.claude/context/invariants.md` — project invariants; these supplement AGENTS.md rules
- `.claude/context/rejections.md` — past violations on this project
- `.claude/context/incidents.md` — past bug root causes

How to rate a repeat of an entry in either file is stated once in this skill, under "Judgment checks" below, and the
subagent gets that wording verbatim.

### Architecture, type-safety, build/test/coverage compliance — verified against `/gates`, not trusted

`/gates` runs before every PR is opened and is the single authoritative check for
layer separation, type safety, patterns, build success, full test suite, coverage,
and UI-selector matching (its Gate 9 and Gate 10 cover what this section used to duplicate).
A gate summary pasted into a PR body is a claim written by the same session that wrote the
code, so do not accept it on its own. Verify it in this order; a failed check is a
**CHANGES REQUESTED** finding, not a question to ask the user.

Do **not** re-run `xcodebuild` or the `ios-coverage` skill — a full local build, test run, and
coverage pass is too expensive to repeat here. Everything else that is cheap and deterministic
*is* re-run.

1. **Pin the SHA.** `git fetch origin`, make sure the checkout is the PR head (`gh pr checkout <PR>`
   or a worktree if it is not), then compare:
   ```bash
   gh pr view <PR> --json headRefOid -q .headRefOid
   git rev-parse HEAD
   git status --porcelain -- . ':!.claude/context/rejections.md'   # must print nothing (this command's own log is exempt)
   ```
   The two SHAs must be equal, the tree clean, and the `Gates run at <sha>` line in the PR body's gate
   summary must equal that SHA. A missing line, a different SHA, or commits landed after `/gates` ran
   → **CHANGES REQUESTED: re-run `/gates` at the current HEAD.** Do not fall back to "ask the user
   whether to trust it".
2. **Re-run the deterministic gates at that SHA and compare to the summary.** Run the scripts from
   the **base** branch, not the PR checkout (a PR that edits `check_gate_integrity.py` must not be
   judged by its own edited copy — the `gates` job in `pr-checks.yml` does the same), and pass the PR's branch name because
   a `gh pr checkout`/worktree HEAD may be detached, which makes the integrity script silently skip
   its `feature/*` check:
   ```bash
   BR=$(gh pr view <PR> --json headRefName -q .headRefName)
   BASE=origin/$(gh pr view <PR> --json baseRefName -q .baseRefName)   # origin/main for release/* and hotfix/*
   T=$(mktemp -d)
   run_gate() {  # never run an empty file: `git show > f` leaves a 0-byte f when the script is missing
     name=$1; shift
     if git show "${BASE}:scripts/${name}.py" > "$T/${name}.py" 2>/dev/null; then python3 "$T/${name}.py" "$@"
     else echo "NOT VERIFIED: scripts/${name}.py not on ${BASE}"; fi
   }
   run_gate check_gate_integrity "$BASE" "$BR"    # Gate 13
   run_gate check_tdd_commit_order "$BASE"        # Gate 11
   ```
   A script that is not on the base branch yet (the PR introducing it, or before it merges) is reported
   as `NOT VERIFIED: <script> not on <base>` and, for a PR that adds it, run from the PR copy
   with that caveat stated — never counted as a clean pass. Exit 2 from the TDD script means no file in the repo matches its
   `SCOPED_LAYER_DIRS` (the layer folders were renamed or moved): report that, not a pass. Also re-run the grep-only gates exactly
   as written in `gates/SKILL.md`, substituting `$BASE` (the fetched `origin/<base>`) for `develop` in every command (local
   `develop` may be stale after `git fetch`): Gate 3 (TODO/FIXME/HACK), Gate 4 (branch name — check `$BR`, since `git branch --show-current` is empty on a detached checkout), Gate 5
   (CHANGELOG), Gate 8 (only if `TransactionImportActor.swift` changed), and Gate 9's grep commands
   (not its `ImportHashGoldenTests` step, which runs `xcodebuild`). Each grep prints nothing on a
   pass except the UI-selector listing (cross-check by hand) and any hit the summary already names as
   an accepted exception. Any result that disagrees with the pasted summary — a script exits
   non-zero, a grep prints a hit the summary does not name — is **CHANGES REQUESTED**, quoting the
   command and its output.
   Gates 1, 2, 6, 7, 10, 12, and Gate 9's golden-test step (build, tests, coverage, security skill,
   advisory heuristics, screenshots, `xcodebuild`) are **not** re-run here; state that they rest on the
   summary and CI.
3. **Check CI.** If a PR exists:
   ```bash
   gh pr checks <PR> --json name,bucket
   ```
   Require a check named `gates` with bucket `pass`. `fail` → **CHANGES REQUESTED**. `pending` → not
   approvable yet; say so. No check named `gates` at all → write `gates CI job: not yet configured` in
   the verdict as a visible note — never let its absence read as a pass.

### Judgment checks — run by a fresh-context subagent, not this session

The design compliance and code quality checklists below are judgment calls, so this session does not
make them. Hand them to one fresh-context subagent. Give it these inputs, and nothing that carries the
implementer's account of the change (listed below):
- the diff: `gh pr diff <PR>`
- the acceptance criteria from the plan or spec this PR implements (`docs/superpowers/plans/` or
  `docs/superpowers/specs/`), if one exists
- the files to read: `AGENTS.md`, `.claude/context/invariants.md`, `.claude/context/rejections.md`,
  `.claude/context/incidents.md` (each if present), plus `docs/design-system.md` and `FinanceTracker/Theme/`
  when the diff touches `Views/` or adds a UI component
- the two checklists below, verbatim
- this rule, verbatim: a finding that repeats a violation in `rejections.md` or reintroduces a symptom in
  `incidents.md` is **HIGH** severity — name the entry it repeats
- the severity scale, one of these for every finding: **HIGH** is a repeat (the rule above) or a break of an
  AGENTS.md or `invariants.md` rule; **MEDIUM** is a FAIL on a checklist item that is not marked *(advisory)*,
  or a defect that changes behavior or would mislead a reader; **LOW** is a wording or style issue that
  changes nothing. A FAIL on a required checklist item is never lower than MEDIUM.

It may also read any source file in the repo (for example, the whole file around a hunk), since several
checks need surrounding code. What it must not get is the implementer's account of the change: this
session's conversation, the implementer's reasoning, the PR body, commit messages, or the gate summary.
Tell it not to run any command that shows PR metadata or commit history: `gh pr view`, `gh pr checks`,
`gh api` for the PR, `git log`, `git show` or `git blame`. Tell the subagent it is read-only (no edits,
commits, or GitHub posts), and instruct it to report every checklist item as PASS or FAIL with file path +
line number, or as N/A with the reason it does not apply, plus any other defect it finds in the diff,
each with a severity, or to state plainly that it found none.

Merge its output into the verdict:
- Every finding it reports — each checklist FAIL and each other defect — goes into the verdict, marked
  accepted or dismissed. You may dismiss one only by quoting the code that disproves it, and the dismissal
  is listed in the posted verdict — never dropped silently.
- An accepted HIGH finding always blocks APPROVED, on any item. An accepted MEDIUM finding blocks,
  except on an item marked *(advisory)*. An accepted LOW finding never blocks. A finding that does not
  block is still reported. Keep the severity the subagent assigned; you may
  raise it, and you may lower it only with a stated reason in the verdict. Two floors never move: a repeat
  or a break of an AGENTS.md or `invariants.md` rule stays HIGH, and a required checklist FAIL stays at
  least MEDIUM.
- Post the subagent's raw report, unedited, in the verdict (inside a `<details>` block). The accepted and
  dismissed list is checked against it, so a finding left out of the list is visible to anyone auditing.
- If a subagent cannot be spawned in this runtime, run the checklists here instead, apply the same
  severity, blocking and advisory rules, and write `Judgment checks: NOT isolated (subagent
  unavailable)` in the verdict.

### Design compliance checks
*Only applies to PRs that touch `Views/` or add new UI components. Read `docs/design-system.md` and `FinanceTracker/Theme/` before running these checks.*

- [ ] No hardcoded colors where a `Theme.Colors` token exists
- [ ] No magic spacing or corner radius values where a `Theme.Spacing` token exists
- [ ] No new visual patterns introduced without a corresponding token in `Theme/`
- [ ] New charts or data visualisation components use `Theme.Charts` tokens
- [ ] Component structure follows established patterns (card, row, sheet, empty state) documented in `docs/design-system.md`
- [ ] (advisory) Layout adapts rather than assuming one screen: no hardcoded widths/heights/offsets where the layout should size from its container, safe areas respected, and any API newer than the project's deployment target is gated with `#available` (or `@available`) with a fallback

### Code quality checks

- [ ] No commented-out code committed
- [ ] No TODO/FIXME in new code (unless tracked in an issue)
- [ ] Functions do one thing
- [ ] No magic numbers for monetary thresholds — use named constants

## Output format

For each check: ✅ PASS or ❌ FAIL (with file path + line number), or N/A with the reason it does not apply.

Lead the verdict with a **Gate verification** block: the PR HEAD SHA, whether it matched the summary's
SHA, each re-run script/grep and its result, the `gates` CI job state (or "not yet configured"), and
which gates were not re-run. Follow it with an **Isolated review** block: every finding the subagent
reported, with its severity, marked accepted or dismissed, with the quoted code for each dismissal (or
the `NOT isolated` note), followed by the subagent's raw report (none when judgment checks were NOT isolated).

Final verdict:
- **APPROVED** — every gate-verification check passes and no accepted finding blocks (see "Merge its output" above: HIGH always blocks, MEDIUM blocks except on advisory items, LOW never blocks), eligible to merge once `/test` and `code-review:code-review` also pass (see AGENTS.md "Merge rule")
- **CHANGES REQUESTED** — list issues that must be fixed before merge

## Logging violations to rejections.md

Append one entry per violation to `.claude/context/rejections.md` in **two** cases, not just one:

1. This review's own verdict is CHANGES REQUESTED — log each issue found here.
2. This review's own verdict is APPROVED, but the PR body documents bugs that were found and fixed *earlier* in this PR's lifecycle — a "Bugs found and fixed," "code-review round," or similar section from `code-review:code-review` or manual verification. Log each of those too. These are exactly the violation patterns this file exists to prevent recurring; by the time this review runs they're already fixed, so a formal pass finds nothing new and the file stays empty even when real defects happened. Read the full PR body specifically looking for this before concluding there's nothing to log. Skip any item that already has an entry for this PR in `rejections.md`, however it was logged (an earlier `/review` round, a code-review round, or by hand). Logging it again would double the history that repeat detection reads.

```
## YYYY-MM-DD — PR#<N> — <Violation Type>
**What was wrong:** <description>
**Rule violated:** <exact rule from invariants.md or AGENTS.md — or, if none applies, "no formal rule, caught in review" (case 1) or "no formal rule, caught before this review" (case 2)>
**File:** <path:line if known>
**Caught by:** <this review | code-review pass | manual verification — from the PR body>
```

Skip this step only if there is truly nothing new to log: no CHANGES REQUESTED issues from this review, *and* no fix documented in the PR body that lacks an entry for this PR.

## Context isolation: what is and isn't isolated

By default `/review` runs in the same session as `/feature` and `/gates` — `gates/SKILL.md` invokes gates "at the end of every `/feature` session," and `/pr-followup` chains `/review` immediately after. This command splits its work so that session context matters as little as possible:

- **Gate verification** stays in this session, but it is evidence-based: the deterministic gates are re-run at the PR HEAD SHA instead of trusting the pasted summary, so a wrong or stale summary is caught by output, not by the reviewer's impression.
- **Judgment checks** (design compliance, code quality) run in a fresh-context subagent. It sees the diff, the plan's acceptance criteria, the project rules, and any repo source file it needs, but never the implementer's transcript, the PR body, commit messages, or the gate summary. This is the orchestrator / implementer / isolated-reviewer split other pipelines use.

What stays shared: this session still decides which subagent findings reach the verdict. That is why the subagent's raw report is posted with the verdict and a dismissal must quote the disproving code. Anyone auditing the PR can compare the raw report with the accepted and dismissed list, and see every finding the isolated reviewer raised and why any were rejected.

FinanceTracker also gets **external auditability**: posting the verdict as a real, separate GitHub review object (below) means anyone auditing the repo from outside the session can see review happened and compare its content against the diff.

Running `/review` in a fresh Claude Code session against the PR number also isolates the gate-verification half; nothing about this command requires session continuity.

## Posting the verdict to GitHub

Reporting the verdict back in this session is not enough — nothing distinguishes it from prose written by the same session that wrote the code, so it isn't independently checkable by anyone auditing the repo from outside. Post it as a real, separate GitHub review object:

```bash
gh pr review <PR> --comment --body "$(cat <<'EOF'
## Review Agent verdict: <APPROVED | CHANGES REQUESTED>

<the check-by-check output from Output format above>
EOF
)"
```

Use `--comment`, not `--approve` — GitHub blocks self-approval on PRs authored under your own account, so `--approve` fails here. `--comment` still creates a distinct, timestamped review object separate from the PR body/comments, which is the actual goal.

## Tip — automate the review-fix loop
While a PR sits in CHANGES REQUESTED (or waiting on CI), the user can avoid manually re-checking by running, as a separate top-level command:
```
/loop 5m "Check PR <N> for new review comments or failing CI. If found, fix them, push, and rebase on develop if behind. Stop once the PR is approved and CI is green."
```
This is the generic `/loop` skill with a literal prompt — there is no dedicated `/babysit` command. `/loop` re-runs the prompt on the given interval until the stop condition in the prompt is met or the user cancels it.

## Done when
Any required `rejections.md` entries are appended, the verdict is posted to GitHub via `gh pr review`, and the verdict is reported to the user. Do **not** merge the PR — per AGENTS.md's "Merge rule," merging only happens once `/test` and `code-review:code-review` also pass, and the user merges it themselves.
