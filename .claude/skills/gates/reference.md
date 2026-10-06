# Gates — reference

Background for `SKILL.md`. Nothing here is a gate command, threshold or pass rule; those all stay in `SKILL.md`, which `/review` re-runs as written.

## Gate 1 — why no pipeline; Xcode 27 advisory

`xcodebuild` writes to a log file and `xcsift` reads that file afterwards — there is no pipeline, so
its own exit status is captured directly (a `| xcsift` pipeline hides it unless `pipefail`,
`PIPESTATUS` (bash) or `pipestatus` (zsh) is used, and `2>&1 | xcsift` on an empty or crashed run

Advisory: a compile error in SwiftUI code that built before an Xcode major-version update may be an SDK
source-compatibility break rather than a bug in the change — see
[`docs/xcode-27-sdk-migration.md`](https://github.com/akshaypimprikar/pragma/blob/develop/docs/xcode-27-sdk-migration.md)
for the two known Xcode 27 patterns.

## Gate 2 — why zero executed tests fails

Pass: `GATE 2 PASS` with an executed-test count above zero. The count is required because
`xcodebuild test` reports `** TEST SUCCEEDED **` with exit 0 when a test filter or scheme change
matches nothing (verified 2026-09-20: `-only-testing:FinanceTrackerTests/<nonexistent suite>` ran zero
tests and still printed `TEST SUCCEEDED`). Fail: empty log, non-zero exit, any failed test case, or zero

## Gate 11 — why commit order is checked

This exists because `/feature`'s
"write failing test first" instruction is unverifiable on its own: nothing distinguishes an
agent that watched the test fail from one that wrote both together and never ran it red. Git
history is the only outside evidence, and only a RED-then-GREEN commit split preserves it. A
2026-08-15 audit of three merged feature branches found every ViewModel task commit bundled
the test and implementation together — this gate exists to close that gap going forward, not
to relitigate history.

## Gate 12 — screenshot procedure

If any `Views/` files changed, capture what the change actually looks like before the PR opens.
By this point Gate 1 already built FinanceTracker successfully — reuse that build instead of
repeating it. Gate 2's simulator is **not** reusable: verified 2026-09-20 (Xcode 27 / Device
Hub) that `xcodebuild test` always tears down its ephemeral simulator clone the moment the test
run completes, on both a single-suite run and the full suite — no simulator is left booted by
the time Gate 12 runs. Expect to `boot_sim` every time; it is the normal path here, not a
fallback.
1. Call `session_show_defaults` — confirm project, scheme (`FinanceTracker`), and simulator
   (`iPhone 17`, `OS=26.4.1`) are set; call `session_set_defaults` if not.
2. Call `get_sim_app_path` (`platform: "iOS Simulator"`) to find the app Gate 1 already built,
   then `boot_sim`, `install_app_sim`, and `launch_app_sim`. Do **not** call `build_run_sim` —
   it triggers a second full build identical to Gate 1's.
3. If the plan document for this feature (`docs/superpowers/plans/*.md`) names a specific
   screen to reach, use `snapshot_ui` to find tappable elements and navigate there; otherwise
   capture the app's default launch screen.
4. Call `screenshot` with `returnFormat: "base64"` so it renders inline in this session in one
   call — Akshay reviews it directly in the transcript. Only fall back to `returnFormat: "path"`
   saved under `.gates-artifacts/gate12-<branch-name>-<screen-or-task>.png` (gitignored) if the
   base64 payload is rejected as too large, then Read that path back to render it.

This gate captures evidence; it does **not** evaluate it. No pass/fail judgment is made against
the plan's UI intent — scoring that automatically would make this an LLM-as-judge check, which
every other gate here avoids (see Gate 10 above, the existing precedent for "advisory, reports
candidates/evidence, never blocks"). Report status as `[i]`, the same symbol Gate 10 uses for
the same "advisory" contract — never `[✓]`/`[✗]`, since this gate cannot fail. The "does this
look right" call is Akshay's, made by looking at the screenshot before merging.

If `install_app_sim`/`launch_app_sim` fails for a reason unrelated to a missing build, that's
likely already caught by Gate 1; don't treat it as a new failure mode here — note "could not
capture screenshot, see Gate 1" and move on.

## Autonomous gate-fixing loop

If any gate fails and needs iterative fixes, run this as a separate top-level command (not from within this agent):
```
/loop Fix failing gates and re-check. Stop when all blocking gates pass (13 total, 2 advisory — Abstraction bloat and Visual verification, both `[i]`/`[–]` only, never block): tree clean and SHA recorded, build succeeds, all tests pass with a non-zero executed count, no TODO/FIXME/HACK in changed files, branch name valid, CHANGELOG Unreleased section populated, coverage ≥80% on new files, security review clean, CSV import concurrency shape correct, architecture & layer-rule compliance clean, RED commit precedes GREEN commit for every new ViewModel/Service/Repository file, gate integrity clean.
```
Claude iterates on fixes and re-checks until all conditions hold. Keep the condition deterministic and verifiable — exit-code or grep-checkable facts only. "implement the feature correctly" is not verifiable and risks the loop satisfying the literal wording without a real fix.

To drive the full feature-to-PR cycle autonomously (no interval = Claude self-paces):
```
/loop run /feature on the next uncovered task from the plan. Then run /gates. Stop when all blocking gates pass.
```

## Guard — what each layer covers

Gates 0–13 are agent-instruction-driven checks, so an agent under pressure to make a stuck gate pass — most exposed during an unattended `/loop` run with no human turn in between — could edit a gate definition instead of fixing the underlying violation, then report a clean gate summary. Two layers cut against that:

- **Live:** `.claude/hooks/guard_protected_paths.py`, wired as a `PreToolUse` hook in `.claude/settings.json`, blocks `Write`/`Edit`/`MultiEdit` and, best effort, Bash writes to `.claude/skills/*/SKILL.md`, `.claude/skills/*/reference.md`, `scripts/check_*`, `AGENTS.md`, `CLAUDE.md`, `CONSTRAINTS.md`, `.claude/context/invariants.md`, `.claude/settings.json`, `.claude/hooks/*` and `FinanceTrackerTests/ImportHashGoldenTests.swift` while the branch matches `feature/*` (exit 2, with the remedy printed). Each is matched at the repo root or under any subdirectory. `python3 .claude/hooks/guard_protected_paths.py --self-test` exercises the allow/block matrix and checks that its glob list matches the CI script's.
- **CI backstop:** Gate 13 (`scripts/check_gate_integrity.py`, check 1) flags the same set on a `feature/*` PR through `GUARDED_PATH_GLOBS`, including a guarded file renamed or copied away. The `gates` CI job (`.github/workflows/gates.yml`) repeats it outside the session using the base branch's copy of the script and runs on every PR, a step in that job runs the hook's self-test (which fails if the hook's and the script's glob lists differ; it runs the PR's own copy, so it catches an honest slip, not a deliberate one), and `/review` re-runs the script. This catches a plain commit and push that never went through Claude Code.

What is not covered:
- The hook's Bash detection is a best-effort parse. `python -c`, interpreter heredocs, variable or glob expansion (including `cd $VAR`), `find -exec`/`-delete`, `xargs rm` fed from stdin, `git checkout <ref> -- file`, `git restore` and `rm -rf <dir that only contains a nested project>` are not detected, and a symlink created and written through in one command is not followed.
- The hook fails open on a detached HEAD, a missing script or malformed input, and it allows every edit off `feature/*`. That includes the hook and its `settings.json` entry (editing them on a `chore/*` or `fix/*` branch is the intended route, reviewed as its own PR, including a `fewer-permission-prompts` prune of `settings.json`).
- **It only runs in sessions that load this repo's `.claude/settings.json`.** Verified 2026-09-23: in a session started from `~/Desktop/Claude` (the parent directory), an `Edit` to `.claude/skills/status/SKILL.md` on a `feature/*` branch succeeded, so the hook did not fire. Start the session from this repo's root for the live layer to apply; the CI backstop applies either way.
- Neither layer catches an agent that renames its branch away from `feature/*`. `.claude/settings.local.json` (which can carry `disableAllHooks`), `.github/workflows/*` and `.githooks/*` are not on the protected list.

`/pipeline-review`'s Settings hygiene check (item 7) still reads `.claude/settings.json` for hook-config hygiene, but that is a periodic audit. The hook pattern is sourced from a practitioner design (`karanb192/claude-code-hooks`'s "config-guard" hook, built in direct response to the ChainDrop npm worm persisting itself via `.claude/settings.json` rewrites) surfaced in the 2026-09-08 Agentic AI Intelligence Report.
