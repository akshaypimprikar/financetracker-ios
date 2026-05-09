# Sync Workflow Agent

Sync the ios-agent-workflow template repo so it stays consistent with FinanceTracker's current conventions.

## Trigger
Run manually after any change to CLAUDE.md, branch strategy, build commands, or agent conventions: `/sync-workflow`

## Process

### 1. Read the source of truth
- Read `CLAUDE.md` from FinanceTracker — branch strategy, build commands, simulator name, architecture rules
- Read all files in `/Users/akshaypimprikar/Desktop/FinanceTracker/.claude/commands/` — the project-specific versions

### 2. Read the template
- Read all files in `/Users/akshaypimprikar/Desktop/ios-agent-workflow/.claude/commands/`

### 3. Compare and update
Check for drift in these areas (keep `<AppName>` placeholders — ios-agent-workflow is a template):

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

### 5. Commit and push
```bash
git -C /Users/akshaypimprikar/Desktop/ios-agent-workflow add .claude/commands/
git -C /Users/akshaypimprikar/Desktop/ios-agent-workflow commit -m "chore: sync commands from FinanceTracker — <brief summary of what changed>"
git -C /Users/akshaypimprikar/Desktop/ios-agent-workflow push
```

### 6. Report
List every file changed and what was updated. If nothing needed changing, say so explicitly.

## Done when
ios-agent-workflow is committed and pushed, report delivered.
