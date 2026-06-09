# Sync Workflow Agent

Sync the pragma template repo so it stays consistent with FinanceTracker's current conventions.

## Trigger
Run manually after any change to CLAUDE.md, branch strategy, build commands, or agent conventions: `/sync-workflow`

## Process

### 1. Read the source of truth
- Read `CLAUDE.md` from FinanceTracker — branch strategy, build commands, simulator name, architecture rules
- Read all files in `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/.claude/commands/` — the project-specific versions

### 2. Read the template
- Read all files in `/Users/akshaypimprikar/Desktop/Claude/pragma/.claude/commands/`

### 3. Compare and update
Check for drift in these areas (keep `<AppName>` placeholders — pragma is a template):

| What to check | Source of truth |
|---|---|
| Branch strategy (`main` vs `develop`) | FinanceTracker CLAUDE.md |
| Simulator name | FinanceTracker CLAUDE.md |
| Build command structure | FinanceTracker CLAUDE.md |
| Test framework (`import Testing` vs XCTest) | FinanceTracker CLAUDE.md |
| Pre-flight check commands in `/release` | FinanceTracker `/release` command |
| Architecture rules checklist in `/review` | FinanceTracker `/review` command |

### 4. Apply updates
Edit only the lines that differ. Do not copy FinanceTracker-specific paths (e.g. `/Users/akshaypimprikar/...`) into the template.

### 5. Open a PR — never push directly to main
```bash
# Create a branch, commit, push, open PR
git -C /Users/akshaypimprikar/Desktop/Claude/pragma checkout develop && git -C /Users/akshaypimprikar/Desktop/Claude/pragma pull
git -C /Users/akshaypimprikar/Desktop/Claude/pragma checkout -b sync/<YYYY-MM-DD>
git -C /Users/akshaypimprikar/Desktop/Claude/pragma add .claude/commands/
git -C /Users/akshaypimprikar/Desktop/Claude/pragma commit -m "chore: sync commands from FinanceTracker — <brief summary>"
git -C /Users/akshaypimprikar/Desktop/Claude/pragma push -u origin sync/<YYYY-MM-DD>
gh pr create --repo akshaypimprikar/pragma \
  --title "chore: sync commands from FinanceTracker — <brief summary>" \
  --body "## Changes\n<bullet list of what changed and why>\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)" \
  --base develop
```

If nothing changed, do not create a branch or PR — report "no changes needed" instead.

### 6. Report
List every file changed and what was updated, plus the PR URL. If nothing needed changing, say so explicitly.

## Done when
PR is open on pragma (or "no changes needed" confirmed), report delivered.
