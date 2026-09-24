---
name: sync-workflow
description: Sync the pragma template repo so it stays consistent with this project's current conventions (build commands, branch strategy, agent conventions). Invoke manually after any change to those.
disable-model-invocation: true
---

# Sync Workflow Agent

Sync the pragma template repo so it stays consistent with FinanceTracker's current conventions.

## Trigger
Run manually after any change to AGENTS.md/CLAUDE.md, branch strategy, build commands, or agent conventions: `/sync-workflow`

## Process

### 0. Sync pragma's local checkout and create the sync branch first
```bash
git -C /Users/akshaypimprikar/Desktop/Claude/pragma checkout develop && git -C /Users/akshaypimprikar/Desktop/Claude/pragma pull
git -C /Users/akshaypimprikar/Desktop/Claude/pragma checkout -B sync/<YYYY-MM-DD>
```
Do this before making any edits below — pulling *after* step 4 has already staged
uncommitted changes risks a checkout/pull conflict against your own in-progress edits.
All edits in steps 3-5 happen on this branch, not on `develop` directly. `-B` (not `-b`)
resets the branch if a same-day sync attempt left one behind from an earlier aborted run.
If `checkout develop` itself fails (e.g. mid-rebase), resolve or abort that first — don't
work around it by editing on the wrong branch.

### 1. Read the source of truth
- Read `AGENTS.md/CLAUDE.md` from FinanceTracker — branch strategy, build commands, simulator name, architecture rules
- Read all files in `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/.claude/skills/` — the project-specific versions

### 2. Read the template
- Read all files in `/Users/akshaypimprikar/Desktop/Claude/pragma/.claude/skills/`

### 3. Compare and update
Check for drift in these areas (keep `<AppName>` placeholders — pragma is a template):

| What to check | Source of truth |
|---|---|
| Branch strategy (`main` vs `develop`) | FinanceTracker AGENTS.md/CLAUDE.md |
| Simulator name | FinanceTracker AGENTS.md/CLAUDE.md |
| Build command structure | FinanceTracker AGENTS.md/CLAUDE.md |
| Test framework (`import Testing` vs XCTest) | FinanceTracker AGENTS.md/CLAUDE.md |
| Pre-flight check commands in `/release` | FinanceTracker `/release` skill |
| Architecture rules checklist in `/review` | FinanceTracker `/review` skill |
| New gates in `/gates` — **only if generalizable** | FinanceTracker `/gates` skill |
| CI workflow flags (simulator selection, coverage, parallelism) | FinanceTracker's `.github/workflows/*.yml` vs. pragma's `scaffold/.github/workflows/*.yml` |

### 4. Apply updates
Edit only the lines that differ. Do not copy FinanceTracker-specific paths (e.g. `/Users/akshaypimprikar/...`) into the template.

For new gates in FinanceTracker's `/gates`, judge each one individually — do not copy-paste:
- **Generalizable** (checks a pattern any iOS MVVM+Repository project would want — e.g. a layer-rule compliance gate): port it as a *templated* gate with `<placeholder>` values, matching the style of Gates 1/2/7. Do not hardcode FinanceTracker's literal grep patterns (money field names, `Services/` path, etc.) into the template.
- **App-specific** (checks something only FinanceTracker's domain has — e.g. the CSV import concurrency-shape gate tied to `TransactionImportActor.swift`): leave it out of pragma entirely. It has no equivalent in a template repo.

### 5. Self-review the diff before committing
Pragma has no `AGENTS.md/CLAUDE.md` and no equivalent to FinanceTracker's `/review` — this is the
only check that runs before a sync PR opens. Keep it lightweight: it exists to catch the
specific ways a *template* repo can drift, not to re-litigate content already reviewed once
in FinanceTracker. Run against the staged diff, before `git commit` — stage first, since the
checks below read `git diff --cached`. Stage everything this sync touched, not just
`.claude/skills/` — a CI workflow flag change under `scaffold/.github/workflows/` is just
as much a sync output and must go through the same review:
```bash
git -C /Users/akshaypimprikar/Desktop/Claude/pragma add .claude/skills/ scaffold/
```

**a. No FinanceTracker-specific literals leaked into template content (advisory — eyeball each hit):**
```bash
git -C /Users/akshaypimprikar/Desktop/Claude/pragma diff --cached | grep -E '^\+' | grep -iE 'FinanceTracker|/Users/akshaypimprikar|iPhone 17|AccountViewModel|SwiftData[A-Z]\w*Repository'
```
A worked example in prose is fine (pragma's own files already do this, e.g. `/gates feature/recurring-transactions`). A hardcoded value standing in for what should be a `<placeholder>` is not — generalize it before committing.

**b. `<placeholder>` convention held where FinanceTracker's source used a concrete name:**
For every newly templated section (an architecture rule, a gate), confirm it uses
`<placeholder>` tokens for anything project-specific — a type name, a file path, a field
name — matching the style already used throughout pragma's `gates/SKILL.md` Gate 9/10 examples.
Zero placeholders in a section that generalizes a FinanceTracker-specific check is the leak.

**c. Gate numbering and counts stay internally consistent (deterministic):**
`Gate 0` (the build-relevant change check) is intentionally excluded from both the sequence and
the count — the pattern below starts from Gate 1 on purpose, not an oversight. `deterministic-pr-gates/SKILL.md`
is excluded from the count-reference grep below: it's a standalone skill with its own independent
gate numbering (one fewer than `gates/SKILL.md`), not a second copy of the same list.
```bash
awk 'BEGIN{expected=1} {if($1!=expected) print "non-sequential: expected "expected" got "$1; expected=$1+1}' \
  <(grep -oE '^### Gate [1-9][0-9]*' /Users/akshaypimprikar/Desktop/Claude/pragma/.claude/skills/gates/SKILL.md | grep -oE '[0-9]+' | sort -n)
MAX=$(grep -oE '^### Gate [1-9][0-9]*' /Users/akshaypimprikar/Desktop/Claude/pragma/.claude/skills/gates/SKILL.md | grep -oE '[0-9]+' | sort -n | tail -1)
if [ -z "$MAX" ]; then echo "ERROR: no '### Gate N' headers found in gates/SKILL.md — check the file, not the count"; else
grep -rniE "all [0-9]+ gates" /Users/akshaypimprikar/Desktop/Claude/pragma/.claude/skills/*/SKILL.md | grep -v "deterministic-pr-gates/SKILL.md" | grep -viE "all $MAX gates"
fi
```
Pass: the sequential check prints nothing, and the count-reference grep returns no lines
disagreeing with `$MAX`. Fail: fix the stale number before committing — this is the "10
gates" vs "11 gates" mismatch class of bug from FinanceTracker's own history. If `MAX` comes
back empty, `gates/SKILL.md`'s header format has changed or the file is missing gate sections
entirely — investigate that directly rather than trusting the count-reference grep (an empty
`$MAX` would otherwise match every "all N gates" line as "stale," which is noise, not the real
problem).

### 6. Open a PR — never push directly to main
The branch was already created in step 0. Re-stage before committing regardless of step 5's
staging — if self-review in 5a/5b caught something and you fixed it, the fix is unstaged
until you add it again:
```bash
git -C /Users/akshaypimprikar/Desktop/Claude/pragma add .claude/skills/ scaffold/
git -C /Users/akshaypimprikar/Desktop/Claude/pragma commit -m "chore: sync skills from FinanceTracker — <brief summary>"
git -C /Users/akshaypimprikar/Desktop/Claude/pragma push -u origin sync/<YYYY-MM-DD>
gh pr create --repo akshaypimprikar/pragma \
  --title "chore: sync skills from FinanceTracker — <brief summary>" \
  --body "## Changes\n<bullet list of what changed and why>\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)" \
  --base develop \
  --head sync/<YYYY-MM-DD>
```

If nothing changed, do not create a branch or PR — report "no changes needed" instead.

**Verify before trusting the PR:** `--repo` alone does not fix the head branch — see AGENTS.md/CLAUDE.md's Cross-repo rule. Always confirm with:
```bash
gh pr view <N> --repo akshaypimprikar/pragma --json headRefName,baseRefName,files
```

### 7. Report
List every file changed and what was updated, plus the PR URL. If nothing needed changing, say so explicitly.

## Done when
PR is open on pragma (or "no changes needed" confirmed), report delivered.
